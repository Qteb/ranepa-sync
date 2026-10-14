import SwiftUI

/// Вкладки: расписание, предметы, сессия и поиск.
struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        let now = Clock.now
        let session = state.session
        // Во время сессии на значке — сколько осталось сдавать.
        let badge = session.map { $0.isRunning(now: now) ? $0.remaining(now: now) : 0 } ?? 0
        TabView(selection: $state.tab) {
            Tab("Расписание", systemImage: "calendar", value: .schedule) { HomeView() }
            Tab("Предметы", systemImage: "books.vertical", value: .subjects) { SubjectsView() }
            Tab("Сессия", systemImage: "graduationcap", value: .session) { SessionTab() }
                .badge(badge)
            Tab(value: .search, role: .search) { SearchView() }
        }
        // Уведомление, виджет или Пункт управления открывают расписание.
        .onChange(of: state.pendingLesson) { _, start in if start != nil { state.tab = .schedule } }
        .onChange(of: state.pendingToday) { _, today in if today { state.tab = .schedule } }
    }
}

enum RootTab: Hashable { case schedule, subjects, session, search }

/// Предметы семестра — из плана обучения (с формой контроля), иначе из
/// расписания. Сессия — первой секцией, внизу — весь план.
struct SubjectsView: View {
    @Environment(AppState.self) private var state
    @State private var showAccount = false

    /// Строка списка: предмет из плана и/или расписания.
    struct Entry: Identifiable {
        let name: String
        let form: String?
        let subject: Subject
        var id: String { name }
    }

    private func entries(now: Date) -> [Entry] {
        let fromSchedule = Subject.all(state.lessons, now: now)
        guard let plan = state.plan, let semester = plan.currentSemester(now: now) else {
            return fromSchedule.map { Entry(name: $0.name, form: nil, subject: $0) }
        }
        let items = plan.subjects(semester: semester)
        func subject(_ name: String) -> Subject {
            fromSchedule.first { $0.name.lowercased() == name.lowercased() } ?? Subject(name: name, lessons: [], now: now)
        }
        var list = items.map { Entry(name: $0.name, form: $0.form, subject: subject($0.name)) }
        // Предметы из расписания, которых нет в плане семестра.
        for s in fromSchedule where !list.contains(where: { $0.name.lowercased() == s.name.lowercased() }) {
            list.append(Entry(name: s.name, form: nil, subject: s))
        }
        // Сначала те, у которых скоро пара; без пар — в конце.
        return list.sorted { ($0.subject.next?.start ?? .distantFuture, $0.name) < ($1.subject.next?.start ?? .distantFuture, $1.name) }
    }

    var body: some View {
        let now = Clock.now
        let list = entries(now: now)
        let semester = state.plan?.currentSemester(now: now)
        NavigationStack {
            List {
                Section(list.isEmpty ? "" : "Предметы семестра · \(list.count)") {
                    ForEach(list) { e in
                        NavigationLink(value: Route.subject(e.name)) { SubjectRow(entry: e) }
                    }
                }
                if let plan = state.plan, !plan.items.isEmpty {
                    Section {
                        NavigationLink(value: Route.plan) {
                            HStack(spacing: 12) {
                                SettingsIcon("list.bullet.rectangle", Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("План обучения")
                                    Text("\(plan.semesters.count) \(plural(plan.semesters.count, "семестр", "семестра", "семестров"))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .overlay {
                if list.isEmpty {
                    ContentUnavailableView("Предметов пока нет", systemImage: "books.vertical",
                                           description: Text("Они появятся, когда загрузится расписание."))
                }
            }
            .navigationTitle("Предметы")
            .navigationSubtitle(semester.flatMap { s in state.plan?.course(semester: s).map { "\($0) · \(s)-й семестр" } } ?? "")
            .routes()
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
    }
}

private struct SubjectRow: View {
    let entry: SubjectsView.Entry

    var body: some View {
        let subject = entry.subject
        let kind = subject.kinds.max { $0.upcoming < $1.upcoming }?.kind
        HStack(spacing: 12) {
            Image(systemName: kind.map(kindSymbol) ?? "calendar.badge.exclamationmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(kind.map(kindColor) ?? Color(.systemGray)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).lineLimit(2)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(subject.lessons.isEmpty ? Color.orange : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let form = entry.form { FormBadge(form: form) }
        }
    }

    private var subtitle: String {
        let subject = entry.subject
        if subject.lessons.isEmpty { return "Пар в расписании нет" }
        guard let next = subject.next else { return "Пар больше нет" }
        return "\(shortWhen(next.start)) · впереди \(subject.upcoming.count)"
    }
}

/// «Экзамен» — цветом сессии, остальное серым.
struct FormBadge: View {
    let form: String

    var body: some View {
        let exam = form.hasPrefix("Экз")
        Text(form)
            .font(.caption.weight(.semibold))
            .foregroundStyle(exam ? kindTextColor("экзамен") : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(exam ? kindColor("экзамен").opacity(0.12) : Color(.tertiarySystemFill)))
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
