import SwiftUI

/// План обучения: все семестры с предметами, объёмом и формой контроля.
struct PlanView: View {
    @Environment(AppState.self) private var state
    /// Раскрытые семестры; текущий показывает первые предметы сразу.
    @State private var expanded: Set<Int> = []
    private let preview = 4

    var body: some View {
        let now = Clock.now
        let plan = state.plan
        let current = plan?.currentSemester(now: now)
        List {
            if let program = state.program {
                Section {
                    Text(program).foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                }
            }
            ForEach(plan?.semesters ?? [], id: \.self) { semester in
                let items = plan!.subjects(semester: semester)
                let open = expanded.contains(semester)
                let shown = open ? items : semester == current ? Array(items.prefix(preview)) : []
                Section {
                    ForEach(shown, id: \.self) { item in
                        NavigationLink(value: Route.subject(item.name)) { row(item) }
                    }
                    if shown.count < items.count {
                        Button(shown.isEmpty ? "Показать \(items.count) \(plural(items.count, "предмет", "предмета", "предметов"))"
                               : "Показать ещё \(items.count - shown.count)") {
                            withAnimation { _ = expanded.insert(semester) }
                        }
                    }
                } header: {
                    Text(header(semester, plan: plan!, current: current))
                }
            }
        }
        .navigationTitle("План обучения")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { if let current { expanded.remove(current) } }
    }

    private func row(_ item: StudyPlan.Item) -> some View {
        HStack(spacing: 10) {
            Text(item.name)
            Spacer(minLength: 4)
            if item.ze > 0 {
                Text("\(item.ze) з. е.").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            if let form = item.form { FormBadge(form: form) }
        }
    }

    /// «1-й семестр · сейчас · сессия 11–30 января».
    private func header(_ semester: Int, plan: StudyPlan, current: Int?) -> String {
        var parts = ["\(semester)-й семестр"]
        if semester == current { parts.append("сейчас") }
        let dates = plan.sessions(semester: semester).compactMap { s -> String? in
            guard let a = s.startDate, let b = s.endDate?.adding(days: -1) else { return nil }
            let range = dateRange(a, b)
            return a.year == Clock.now.year || (a.year == Clock.now.year + 1 && a.month < Clock.now.month) ? range : "\(range) \(a.year)"
        }
        if !dates.isEmpty { parts.append("сессия " + dates.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}
