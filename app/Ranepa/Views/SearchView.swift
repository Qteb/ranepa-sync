import SwiftUI

/// Поиск по семестру: предмет, преподаватель или аудитория.
struct SearchView: View {
    @Environment(AppState.self) private var state
    @State private var query = ""
    @State private var lesson: Lesson?

    var body: some View {
        NavigationStack {
            results
                .navigationTitle("Поиск")
                .routes()
        }
        .searchable(text: $query, prompt: "Предмет, преподаватель, аудитория")
        .sheet(item: $lesson) { LessonSheet(lesson: $0) }
    }

    @ViewBuilder
    private var results: some View {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let now = Clock.now
        if q.isEmpty {
            ContentUnavailableView("Поиск по семестру", systemImage: "magnifyingglass",
                                   description: Text("Ищи по названию предмета, фамилии преподавателя или номеру аудитории."))
        } else {
            let subjects = Subject.all(state.lessons, now: now).filter { $0.name.lowercased().contains(q) }
            let lecturers = Dictionary(grouping: state.lessons.filter { $0.lecturer.lowercased().contains(q) }, by: \.lecturer)
            let lessons = state.lessons.filter { l in
                !l.cancelled && l.end > now && (l.subject.lowercased().contains(q) || l.lecturer.lowercased().contains(q)
                                                || l.room.lowercased().contains(q))
            }
            if subjects.isEmpty && lecturers.isEmpty && lessons.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List {
                    if !subjects.isEmpty {
                        Section("Предметы") {
                            ForEach(subjects) { s in
                                NavigationLink(value: Route.subject(s.name)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.name)
                                        Text(s.upcomingSummary).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                    if !lecturers.isEmpty {
                        Section("Преподаватели") {
                            ForEach(lecturers.keys.sorted(), id: \.self) { name in
                                let own = lecturers[name]!
                                let subjectNames = Array(Set(own.map(\.subject))).sorted()
                                NavigationLink(value: Route.lecturer(name)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(name)
                                        Text(subjectNames.joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    if !lessons.isEmpty {
                        Section("Ближайшие пары") {
                            ForEach(lessons.prefix(30)) { l in
                                Button { lesson = l } label: { LessonLine(lesson: l) }
                                .foregroundStyle(Color(.label))
                            }
                        }
                    }
                }
            }
        }
    }
}
