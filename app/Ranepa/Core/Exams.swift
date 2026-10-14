import Foundation

/// Сессия: зачёты и экзамены впереди, у каждого — консультация по тому же
/// предмету, если она есть.
struct ExamSession {
    struct Item: Identifiable {
        let exam: Lesson
        let consultation: Lesson?
        var id: String { exam.id }
    }

    let items: [Item]

    /// Карточка на главном экране — за столько дней до первого зачёта или экзамена.
    static let cardDays = 30

    /// nil — впереди нет ни зачётов, ни экзаменов.
    init?(lessons: [Lesson], now: Date) {
        let active = lessons.filter { !$0.cancelled && $0.end > now }
        let exams = active.filter { $0.kind == "экзамен" || $0.kind == "зачёт" }
        guard !exams.isEmpty else { return nil }
        var used = Set<String>()
        items = exams.map { exam in
            // Ближайшая перед экзаменом консультация по тому же предмету.
            let consultation = active.last {
                $0.kind == "консультация" && $0.subject == exam.subject && $0.start < exam.start && !used.contains($0.id)
            }
            if let consultation { used.insert(consultation.id) }
            return Item(exam: exam, consultation: consultation)
        }
    }

    var first: Lesson { items[0].exam }
    var last: Lesson { items[items.count - 1].exam }

    /// Показывать ли карточку: до первого зачёта или экзамена не больше месяца.
    func showsCard(now: Date) -> Bool { first.start.days(since: now) <= Self.cardDays }

    /// «2 экзамена и зачёт», «3 зачёта», «экзамен».
    var summary: String {
        let exams = items.filter { $0.exam.kind == "экзамен" }.count
        let credits = items.count - exams
        let parts = [countLabel(exams, "экзамен", "экзамена", "экзаменов"),
                     countLabel(credits, "зачёт", "зачёта", "зачётов")].compactMap { $0 }
        return parts.joined(separator: " и ")
    }

    /// «18–26 января», «28 декабря – 26 января», «18 января».
    var dates: String {
        let a = first.start, b = last.start
        if a.sameDay(b) { return "\(a.day) \(monthsGenitive[a.month - 1])" }
        if a.month == b.month { return "\(a.day)–\(b.day) \(monthsGenitive[b.month - 1])" }
        return "\(a.day) \(monthsGenitive[a.month - 1]) – \(b.day) \(monthsGenitive[b.month - 1])"
    }
}

/// nil для нуля, «экзамен» для одного, «2 экзамена» дальше.
private func countLabel(_ n: Int, _ one: String, _ few: String, _ many: String) -> String? {
    guard n > 0 else { return nil }
    return n == 1 ? one : "\(n) \(plural(n, one, few, many))"
}

func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let m10 = n % 10, m100 = n % 100
    if m10 == 1 && m100 != 11 { return one }
    if (2...4).contains(m10) && !(12...14).contains(m100) { return few }
    return many
}

/// «сегодня», «завтра», «через 13 дней».
func daysUntil(_ date: Date, from now: Date) -> String {
    switch date.days(since: now) {
    case ...0: "сегодня"
    case 1: "завтра"
    case let n: "через \(n) \(plural(n, "день", "дня", "дней"))"
    }
}
