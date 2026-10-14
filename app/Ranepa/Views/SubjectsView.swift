import SwiftUI

/// Вкладки: расписание, предметы и поиск.
struct RootView: View {
    @Environment(AppState.self) private var state
    @State private var tab = RootTab.schedule

    var body: some View {
        TabView(selection: $tab) {
            Tab("Расписание", systemImage: "calendar", value: .schedule) { HomeView() }
            Tab("Предметы", systemImage: "books.vertical", value: .subjects) { SubjectsView() }
            Tab(value: .search, role: .search) { SearchView() }
        }
        // Уведомление, виджет или Пункт управления открывают расписание.
        .onChange(of: state.pendingLesson) { _, start in if start != nil { tab = .schedule } }
        .onChange(of: state.pendingToday) { _, today in if today { tab = .schedule } }
    }
}

enum RootTab: Hashable { case schedule, subjects, search }

/// Все предметы семестра; сессия — первой секцией, если зачёты уже в расписании.
struct SubjectsView: View {
    @Environment(AppState.self) private var state
    @State private var showAccount = false
    @State private var showExams = false

    var body: some View {
        let now = Clock.now
        let subjects = Subject.all(state.lessons, now: now)
        NavigationStack {
            List {
                if let session = ExamSession(lessons: state.lessons, now: now) {
                    Section("Сессия · \(session.dates)") {
                        Button { showExams = true } label: { SessionRow(session: session) }
                            .foregroundStyle(Color(.label))
                    }
                }
                Section {
                    ForEach(subjects) { subject in
                        NavigationLink(value: subject) { SubjectRow(subject: subject) }
                    }
                }
            }
            .overlay {
                if subjects.isEmpty {
                    ContentUnavailableView("Предметов пока нет", systemImage: "books.vertical",
                                           description: Text("Они появятся, когда загрузится расписание."))
                }
            }
            .navigationTitle("Предметы")
            .navigationDestination(for: Subject.self) { SubjectView(name: $0.name) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAccount = true } label: { AvatarView(size: 36) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Аккаунт и настройки")
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .sheet(isPresented: $showAccount) { AccountView() }
        .sheet(isPresented: $showExams) {
            if let session = ExamSession(lessons: state.lessons, now: Clock.now) { ExamsView(session: session) }
        }
    }
}

private struct SessionRow: View {
    let session: ExamSession

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "graduationcap.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(kindColor("экзамен")))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.summary.capitalizedFirst).font(.headline)
                Text("Первый — \(session.first.subject), \(daysUntil(session.first.start, from: Clock.now))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

private struct SubjectRow: View {
    let subject: Subject

    var body: some View {
        HStack(spacing: 12) {
            // Значок — по самому частому типу занятий.
            let kind = subject.kinds.max { $0.upcoming < $1.upcoming }?.kind ?? ""
            Image(systemName: kindSymbol(kind))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(kindColor(kind)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(subject.name).lineLimit(2)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let exam = subject.exam {
                Text(exam.kind.capitalizedFirst)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(kindTextColor(exam.kind))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(kindColor(exam.kind).opacity(0.12)))
            }
        }
    }

    private var subtitle: String {
        guard let next = subject.next else { return "Пар больше нет" }
        let left = subject.upcoming.count
        return "\(shortWhen(next.start)) · впереди \(left)"
    }
}

/// «Сегодня, 09:00», «Завтра, 12:20», «Пт, 10:40», «16 окт., 09:00».
func shortWhen(_ t: Date) -> String {
    let day = switch t.days(since: Clock.now) {
    case 0: "Сегодня"
    case 1: "Завтра"
    case 2...6: weekdaysShort[t.isoWeekday - 1]
    default: "\(t.day) \(monthsGenitive[t.month - 1].prefix(3)).".replacingOccurrences(of: "мая.", with: "мая")
    }
    return "\(day), \(hm(t))"
}
