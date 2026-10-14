import SwiftUI

/// Карточка «Сессия через 13 дней» над лентой сегодняшнего дня.
struct ExamCard: View {
    let session: ExamSession
    let open: () -> Void

    var body: some View {
        let now = Clock.now
        Button(action: open) {
            HStack(spacing: 14) {
                Image(systemName: "graduationcap.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(kindColor("экзамен")))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(now)).font(.headline).foregroundStyle(Color(.label))
                    Text(subtitle(now))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Открывает список зачётов и экзаменов")
    }

    private func title(_ now: Date) -> String {
        guard let first = session.firstDate, !session.isRunning(now: now) else { return "Сессия идёт" }
        return "Сессия \(daysUntil(first, from: now))"
    }

    private func subtitle(_ now: Date) -> String {
        if session.isRunning(now: now), let next = session.nextEvent {
            return "\(next.kind.capitalizedFirst) \(whenLabel(next.start)) · \(next.subject)"
        }
        return [session.dates, session.summary].filter { !$0.isEmpty }.joined(separator: " · ").capitalizedFirst
    }
}

/// Сессия: экзамены карточками, зачёты списком. Без даты — «Дата не назначена».
struct ExamsView: View {
    let session: ExamSession
    @Environment(\.dismiss) private var dismiss
    @State private var lesson: Lesson?

    var body: some View {
        NavigationStack {
            List {
                if !session.exams.isEmpty {
                    Section(session.exams.count == 1 ? "Экзамен" : "Экзамены") {
                        ForEach(session.exams) { examRow($0) }
                    }
                }
                if !session.credits.isEmpty {
                    Section(session.credits.count == 1 ? "Зачёт" : "Зачёты") {
                        ForEach(session.credits) { creditRow($0) }
                    }
                }
                Section {
                } footer: {
                    Text("Вечером накануне каждого экзамена и зачёта с датой придёт напоминание.")
                }
            }
            .listSectionSpacing(.compact)
            .routes()
            .navigationTitle("Сессия")
            .navigationSubtitle([session.dates, session.summary].filter { !$0.isEmpty }.joined(separator: " · "))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .sheet(item: $lesson) { LessonSheet(lesson: $0) }
    }

    @ViewBuilder
    private func examRow(_ e: ExamSession.Entry) -> some View {
        if let event = e.event {
            Button { lesson = event } label: { examLabel(e) }
                .foregroundStyle(Color(.label))
        } else {
            NavigationLink(value: Route.subject(e.subject)) { examLabel(e) }
        }
    }

    private func examLabel(_ e: ExamSession.Entry) -> some View {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Label(e.form, systemImage: kindSymbol("экзамен"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(kindTextColor("экзамен"))
                    Spacer()
                    if let event = e.event {
                        Text(daysUntil(event.start, from: Clock.now))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(e.subject).font(.title3.bold()).foregroundStyle(Color(.label)).multilineTextAlignment(.leading)
                Text(e.event.map { "\(shortDay($0.start)), \(hm($0.start)) · \(place($0))" } ?? "Дата не назначена")
                    .font(.subheadline)
                    .foregroundStyle(e.event == nil ? .tertiary : .secondary)
                if let c = e.consultation {
                    Label {
                        Text("Консультация — \(shortDay(c.start)), \(hm(c.start)) · \(place(c))")
                    } icon: {
                        Image(systemName: kindSymbol(c.kind)).foregroundStyle(kindColor(c.kind))
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
    }

    private func creditRow(_ e: ExamSession.Entry) -> some View {
        NavigationLink(value: Route.subject(e.subject)) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(e.subject)
                    if e.form != "Зачёт" {
                        Text(e.form).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                Text(e.event.map { "\(shortDay($0.start)), \(hm($0.start)) · \(place($0))" } ?? "Дата не назначена")
                    .font(.subheadline)
                    .foregroundStyle(e.event == nil ? .tertiary : .secondary)
            }
        }
    }

    /// «сб, 7 ноября».
    private func shortDay(_ d: Date) -> String {
        "\(weekdaysShort[d.isoWeekday - 1].lowercased()), \(d.day) \(monthsGenitive[d.month - 1])"
    }

    private func place(_ l: Lesson) -> String { l.isRemote ? "дистанционно" : l.shortLocation }
}
