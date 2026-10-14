import SwiftUI

/// Карточка «Сессия через 13 дней» над лентой сегодняшнего дня.
struct ExamCard: View {
    let session: ExamSession
    let open: () -> Void

    var body: some View {
        let now = Clock.now
        let days = session.first.start.days(since: now)
        Button(action: open) {
            HStack(spacing: 14) {
                Image(systemName: "graduationcap.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(kindColor("экзамен")))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(days <= 0 ? "Сессия идёт" : "Сессия \(daysUntil(session.first.start, from: now))")
                        .font(.headline)
                        .foregroundStyle(Color(.label))
                    Text(days <= 0
                         ? "\(session.first.kind.capitalizedFirst) \(whenLabel(session.first.start)) · \(session.first.subject)"
                         : "\(session.summary.capitalizedFirst) · первый \(session.first.start.day) \(monthsGenitive[session.first.start.month - 1])")
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
}

/// Сессия: карточка на каждый зачёт и экзамен, консультация — внутри.
struct ExamsView: View {
    let session: ExamSession
    @Environment(\.dismiss) private var dismiss
    @State private var lesson: Lesson?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(session.items) { item in
                        Button { lesson = item.exam } label: { card(item) }
                            .buttonStyle(.plain)
                    }
                    Text("Вечером накануне каждого зачёта и экзамена придёт напоминание.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Сессия")
            .navigationSubtitle("\(session.summary.capitalizedFirst) · \(session.dates)")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .sheet(item: $lesson) { LessonSheet(lesson: $0) }
    }

    /// «сб, 7 ноября».
    private func shortDay(_ d: Date) -> String {
        "\(weekdaysShort[d.isoWeekday - 1].lowercased()), \(d.day) \(monthsGenitive[d.month - 1])"
    }

    private func place(_ l: Lesson) -> String { l.isRemote ? "дистанционно" : l.shortLocation }

    private func card(_ item: ExamSession.Item) -> some View {
        let exam = item.exam
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(exam.kind.capitalizedFirst, systemImage: kindSymbol(exam.kind))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(kindTextColor(exam.kind))
                Spacer()
                Text(daysUntil(exam.start, from: Clock.now))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            Text(exam.subject)
                .font(.title3.bold())
                .foregroundStyle(Color(.label))
                .multilineTextAlignment(.leading)
            Text("\(shortDay(exam.start)), \(hm(exam.start)) · \(place(exam))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let c = item.consultation {
                Label {
                    Text("Консультация — \(shortDay(c.start)), \(hm(c.start)) · \(place(c))")
                } icon: {
                    Image(systemName: kindSymbol(c.kind)).foregroundStyle(kindColor(c.kind))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
        .accessibilityElement(children: .combine)
    }
}
