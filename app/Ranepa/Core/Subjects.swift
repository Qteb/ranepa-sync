import Foundation

/// Предмет семестра: все его пары, преподаватели, где обычно проходит.
struct Subject: Identifiable, Hashable {
    struct Lecturer: Hashable {
        let name: String
        let email: String
        /// «Лекции», «Семинары» — что ведёт.
        let kinds: [String]
        let upcoming: Int
    }

    /// Занятия одного типа: сколько впереди и в какой аудитории обычно.
    struct KindSummary: Hashable {
        let kind: String
        let upcoming: Int
        /// Аудитория, где прошло больше всего таких пар; nil — дистанционно
        /// или аудитории разные.
        let usualRoom: String?
    }

    let name: String
    /// Все пары по времени, вместе с прошедшими и отменёнными.
    let lessons: [Lesson]
    let now: Date

    var id: String { name }

    var upcoming: [Lesson] { lessons.filter { !$0.cancelled && $0.end > now } }
    var next: Lesson? { upcoming.first }
    var exam: Lesson? { upcoming.first { $0.kind == "экзамен" || $0.kind == "зачёт" } }
    var consultation: Lesson? {
        guard let exam else { return nil }
        return upcoming.last { $0.kind == "консультация" && $0.start < exam.start }
    }
    /// Курс в СДО: ссылка с любой дистанционной пары.
    var lmsLink: URL? { lessons.lazy.compactMap { $0.lmsLink.isEmpty ? nil : URL(string: $0.lmsLink) }.first }

    /// Типы занятий (кроме сессии) в порядке: лекции, семинары, остальное.
    var kinds: [KindSummary] {
        let regular = lessons.filter { !["экзамен", "зачёт", "консультация"].contains($0.kind) && !$0.cancelled }
        let order = ["лекция", "семинар", "лабораторная", "физкультура"]
        let grouped = Dictionary(grouping: regular, by: \.kind)
        return grouped.keys.sorted { (order.firstIndex(of: $0) ?? 9, $0) < (order.firstIndex(of: $1) ?? 9, $1) }.map { kind in
            let all = grouped[kind]!
            return KindSummary(kind: kind, upcoming: all.filter { $0.end > now }.count, usualRoom: Self.usualRoom(all))
        }
    }

    /// Аудитория, где больше половины пар; иначе nil.
    private static func usualRoom(_ lessons: [Lesson]) -> String? {
        let rooms = lessons.filter { !$0.isRemote && !$0.room.isEmpty && !$0.room.hasPrefix("Уточняется") }.map(\.shortLocation)
        guard let (room, count) = Dictionary(grouping: rooms, by: { $0 }).mapValues(\.count).max(by: { $0.value < $1.value }),
              count * 2 > rooms.count, count >= 2 else { return nil }
        return room
    }

    var lecturers: [Lecturer] {
        let withName = lessons.filter { !$0.lecturer.isEmpty && !$0.cancelled }
        var order: [String] = []
        for l in withName where !order.contains(l.lecturer) { order.append(l.lecturer) }
        return order.map { name in
            let own = withName.filter { $0.lecturer == name }
            let kinds = Array(Set(own.map(\.kind).filter { !["экзамен", "зачёт", "консультация"].contains($0) }))
                .sorted().map(kindPlural)
            return Lecturer(name: name, email: own.first { !$0.email.isEmpty }?.email ?? "",
                            kinds: kinds, upcoming: own.filter { $0.end > now }.count)
        }
    }

    /// «Впереди 24 пары: 11 лекций, 11 семинаров, консультация и экзамен».
    var upcomingSummary: String {
        let list = upcoming
        guard !list.isEmpty else { return "Пар больше нет" }
        var parts = kinds.filter { $0.upcoming > 0 }.map { "\($0.upcoming) \(kindCount($0.kind, $0.upcoming))" }
        let consults = list.filter { $0.kind == "консультация" }.count
        if consults > 0 { parts.append(consults == 1 ? "консультация" : "\(consults) консультации") }
        if let exam { parts.append(exam.kind) }
        let total = "Впереди \(list.count) \(plural(list.count, "пара", "пары", "пар"))"
        // Один тип занятий — расшифровка ничего не добавляет.
        guard parts.count > 1 else { return total }
        return "\(total): \(parts.dropLast().joined(separator: ", ")) и \(parts.last!)"
    }

    static func all(_ lessons: [Lesson], now: Date) -> [Subject] {
        Dictionary(grouping: lessons, by: \.subject)
            .map { Subject(name: $0.key, lessons: $0.value.sorted { $0.start < $1.start }, now: now) }
            // Сначала те, у которых скоро пара; закончившиеся — в конце.
            .sorted { ($0.next?.start ?? .distantFuture, $0.name) < ($1.next?.start ?? .distantFuture, $1.name) }
    }

    static func == (a: Subject, b: Subject) -> Bool { a.name == b.name }
    func hash(into h: inout Hasher) { h.combine(name) }
}

/// «лекция» → «Лекции».
func kindPlural(_ kind: String) -> String {
    switch kind {
    case "лекция": "Лекции"
    case "семинар": "Семинары"
    case "лабораторная": "Лабораторные"
    case "физкультура": "Физкультура"
    default: kind.capitalizedFirst
    }
}

/// «11 лекций», «2 семинара».
private func kindCount(_ kind: String, _ n: Int) -> String {
    switch kind {
    case "лекция": plural(n, "лекция", "лекции", "лекций")
    case "семинар": plural(n, "семинар", "семинара", "семинаров")
    case "лабораторная": plural(n, "лабораторная", "лабораторные", "лабораторных")
    case "физкультура": plural(n, "занятие", "занятия", "занятий")
    default: kind
    }
}
