import SwiftUI

/// Предмет: следующая пара, экзамен, преподаватели, где обычно проходит,
/// все пары по месяцам.
struct SubjectView: View {
    let name: String
    @Environment(AppState.self) private var state
    @Environment(\.openURL) private var openURL
    @State private var lesson: Lesson?
    @State private var expanded: Set<Int> = []
    @State private var copied: String?
    /// Заголовок в ленте ушёл под шапку — показываем его в шапке.
    @State private var titleHidden = false

    var body: some View {
        let subject = Subject(name: name, lessons: state.lessons.filter { $0.subject == name }, now: Clock.now)
        List {
            // Названия длинные («Элективные дисциплины по физической культуре
            // и спорту»): крупный заголовок навигации их обрезает, свой —
            // переносит.
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(name).font(.title.bold())
                    Text(subject.upcomingSummary).foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            }
            if let next = subject.next {
                Section("Следующая") {
                    Button { lesson = next } label: { NextRow(lesson: next) }
                        .foregroundStyle(Color(.label))
                }
            }
            if let exam = subject.exam {
                Section(exam.kind.capitalizedFirst) {
                    Button { lesson = exam } label: { ExamRow(exam: exam, consultation: subject.consultation) }
                        .foregroundStyle(Color(.label))
                }
            }
            if !subject.lecturers.isEmpty {
                Section(subject.lecturers.count == 1 ? "Преподаватель" : "Преподаватели") {
                    ForEach(subject.lecturers, id: \.name) { lecturerRow($0) }
                }
            }
            if !subject.kinds.isEmpty {
                Section("Занятия") {
                    ForEach(subject.kinds, id: \.kind) { kindRow($0) }
                    if let lms = subject.lmsLink {
                        Link(destination: lms) {
                            HStack {
                                Label("Курс в СДО", systemImage: "book")
                                Spacer()
                                Image(systemName: "arrow.up.right").foregroundStyle(Color(.tertiaryLabel))
                            }
                        }
                    }
                }
            }
            months(subject)
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .navigationTitle(titleHidden ? name : "")
        .navigationBarTitleDisplayMode(.inline)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 60 } action: { _, hidden in
            withAnimation(.easeInOut(duration: 0.15)) { titleHidden = hidden }
        }
        .sheet(item: $lesson) { LessonSheet(lesson: $0, from: .subject(name)) }
        .alert("Адрес скопирован", isPresented: Binding(get: { copied != nil }, set: { if !$0 { copied = nil } })) {
        } message: { Text(copied ?? "") }
    }

    private func lecturerRow(_ l: Subject.Lecturer) -> some View {
        NavigationLink(value: Route.lecturer(l.name)) { lecturerLabel(l) }
    }

    private func lecturerLabel(_ l: Subject.Lecturer) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(l.name)
                Text(([l.kinds.enumerated().map { $0 == 0 ? $1 : $1.lowercased() }.joined(separator: " и ")].filter { !$0.isEmpty } + (l.upcoming > 0 ? ["\(l.upcoming) впереди"] : []))
                        .joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !l.email.isEmpty {
                Button {
                    openMail(l.email, subject: name, openURL: openURL) { copied = l.email }
                } label: {
                    Image(systemName: "envelope.fill")
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.accentColor.opacity(0.12)))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Написать \(l.name)")
            }
        }
    }

    private func kindRow(_ k: Subject.KindSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: kindSymbol(k.kind))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(kindColor(k.kind)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(kindPlural(k.kind))
                Text([k.upcoming > 0 ? "\(k.upcoming) впереди" : "все прошли", k.usualRoom.map { "обычно \($0)" }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Все пары по месяцам: ближайший месяц развёрнут, остальные — по нажатию.
    @ViewBuilder
    private func months(_ subject: Subject) -> some View {
        let lessons = subject.lessons.filter { $0.end > Clock.now.dateOnly }
        let groups = Dictionary(grouping: lessons) { $0.start.year * 100 + $0.start.month }
        ForEach(Array(groups.keys.sorted().enumerated()), id: \.element) { index, key in
            let items = groups[key]!
            let open = index == 0 || expanded.contains(key)
            Section("\(monthsNominative[key % 100 - 1]) · \(items.count) \(plural(items.count, "пара", "пары", "пар"))") {
                if open {
                    ForEach(items) { l in
                        Button { lesson = l } label: { PairRow(lesson: l) }
                            .foregroundStyle(Color(.label))
                    }
                } else {
                    Button("Показать") { withAnimation { _ = expanded.insert(key) } }
                }
            }
        }
    }
}

private struct NextRow: View {
    let lesson: Lesson

    var body: some View {
        HStack(spacing: 12) {
            Stripe(kind: lesson.kind)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(shortWhen(lesson.start))–\(hm(lesson.end))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text("\(lesson.kind.capitalizedFirst) · \(lesson.isRemote ? "дистанционно" : lesson.shortLocation)")
                    .font(.headline)
                if !lesson.lecturer.isEmpty {
                    Text(lesson.lecturer).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ExamRow: View {
    let exam: Lesson
    let consultation: Lesson?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: kindSymbol(exam.kind))
                .font(.title2)
                .foregroundStyle(kindColor(exam.kind))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(daysUntil(exam.start, from: Clock.now).capitalizedFirst)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(kindTextColor(exam.kind))
                Text("\(dayTitle(exam.start).capitalizedFirst), \(hm(exam.start)) · \(exam.isRemote ? "дистанционно" : exam.shortLocation)")
                    .font(.headline)
                if let c = consultation {
                    Label {
                        Text("Консультация — \(dayTitle(c.start).lowercased()), \(hm(c.start))\(c.isRemote ? ", дистанционно" : "")")
                    } icon: {
                        Image(systemName: kindSymbol(c.kind)).foregroundStyle(kindColor(c.kind))
                    }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Пара в списке: число и день недели, полоска типа, время и аудитория.
struct PairRow: View {
    let lesson: Lesson

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text("\(lesson.start.day)").font(.title3.weight(.semibold)).monospacedDigit()
                Text(weekdaysShort[lesson.start.isoWeekday - 1].lowercased()).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 34)
            Stripe(kind: lesson.kind)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(hm(lesson.start)) · \(lesson.kind.capitalizedFirst)")
                    .strikethrough(lesson.cancelled)
                Text(place)
                    .font(.subheadline)
                    .foregroundStyle(lesson.room.hasPrefix("Уточняется") ? Color.orange : .secondary)
            }
            Spacer(minLength: 0)
        }
        .opacity(lesson.end < Clock.now ? 0.45 : 1)
        .accessibilityElement(children: .combine)
    }

    private var place: String {
        if lesson.cancelled { return "отменена" }
        if lesson.isRemote { return "дистанционно" }
        if lesson.room.hasPrefix("Уточняется") { return "аудитория уточняется" }
        return lesson.shortLocation
    }
}

private struct Stripe: View {
    let kind: String
    var body: some View {
        RoundedRectangle(cornerRadius: 2).fill(kindColor(kind)).frame(width: 4).frame(minHeight: 34)
    }
}
