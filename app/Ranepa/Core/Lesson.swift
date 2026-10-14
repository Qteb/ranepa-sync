import Foundation

/// Пара из ЛК. Время — в часовом поясе устройства (сайт отдаёт московское
/// время без зоны).
struct Lesson: Identifiable, Hashable {
    let start: Date
    let end: Date
    let subject: String
    /// «лекция», «семинар», …
    let kind: String
    let room: String
    let lecturer: String
    let email: String
    let groups: [String]
    let lmsLink: String
    let comment: String
    let cancelled: Bool

    var id: String { "\(start.timeIntervalSince1970)|\(subject)|\(kind)" }

    var title: String { kind.isEmpty ? subject : "\(subject) (\(kind))" }
    var isRemote: Bool { room.hasPrefix("СДО") }
    var location: String { isRemote ? "Дистанционно" : room }

    /// «1 - 1112 (20) ТВ+ПК Блок 1В (Вернадского, 84 …)» → «1 - 1112».
    var shortLocation: String {
        if isRemote { return "Дистанционно" }
        if let i = room.range(of: " (") { return String(room[..<i.lowerBound]) }
        return room
    }

    /// «1 - 2262, корпус 1» или «Дистанционно» — для уведомлений.
    var placeLabel: String {
        if isRemote { return "Дистанционно" }
        guard let match = room.firstMatch(of: /корпус\s*(\d+)/) else { return shortLocation }
        return "\(shortLocation), корпус \(match.1)"
    }

    /// «1 - 2262, блок 2F» — подпись точки в Картах.
    var mapTitle: String {
        guard let block = room.firstMatch(of: /Блок\s+(\S+)/) else { return shortLocation }
        return "\(shortLocation), блок \(block.1)"
    }

    /// Описание события в календаре.
    var details: String {
        [lecturer, email, groups.joined(separator: ", "), lmsLink, comment]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    func isOngoing(at now: Date) -> Bool { !cancelled && start <= now && now < end }
}

/// Тип занятия из ЛК → короткое название. Физкультура в ЛК — обычное
/// практическое занятие, её узнаём по названию предмета.
func kindOf(type: String, subject: String) -> String {
    let t = type.lowercased()
    if subject.lowercased().contains("физической культур") { return "физкультура" }
    if t.contains("лекц") { return "лекция" }
    if t.contains("практ") || t.contains("семин") { return "семинар" }
    if t.contains("лаборатор") { return "лабораторная" }
    if t.contains("консульт") { return "консультация" }
    if t.contains("экзамен") { return "экзамен" }
    if t.contains("зач") { return "зачёт" }
    return t
}

private let moscowFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Europe/Moscow")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return f
}()

/// «2026-10-12T09:00:00» — московское время без смещения.
func moscowDate(_ value: String) -> Date? {
    moscowFormatter.date(from: String(value.prefix(19)))
}

/// Момент → строка в формате ЛК (московское время).
func moscowStamp(_ date: Date) -> String { moscowFormatter.string(from: date) }

private func str(_ v: Any?) -> String {
    switch v {
    case let s as String: s.trimmingCharacters(in: .whitespacesAndNewlines)
    case let n as NSNumber: n.stringValue
    default: ""
    }
}

/// Разбирает сырые дни из n-api/schedule: [{"date": …, "discs": […]}, …].
func parseLessons(_ days: [Any]) -> [Lesson] {
    var lessons: [Lesson] = []
    for case let day as [String: Any] in days {
        for case let disc as [String: Any] in day["discs"] as? [Any] ?? [] {
            guard let start = moscowDate(str(disc["start_date"])),
                  let end = moscowDate(str(disc["end_date"])) else { continue }
            let subject = str(disc["disc"])
            // Группы приходят словарём {"0": …, "1": …}.
            let groups = (disc["groups"] as? [String: Any] ?? [:])
                .sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }
                .map { str($0.value) }
            lessons.append(Lesson(
                start: start, end: end, subject: subject,
                kind: kindOf(type: str(disc["type"]), subject: subject),
                room: str(disc["room"]), lecturer: str(disc["lecturer"]),
                email: str(disc["sam_email"]), groups: groups,
                lmsLink: str(disc["lms_link"]), comment: str(disc["comment"]),
                cancelled: str(disc["status"]).lowercased().contains("отмен")))
        }
    }
    return lessons.sorted { $0.start < $1.start }
}

/// Сырые дни из кэша.
func cachedDays(_ d: UserDefaults = .standard) -> [Any] {
    guard let raw = d.string(forKey: Keys.days)?.data(using: .utf8),
          let days = try? JSONSerialization.jsonObject(with: raw) as? [Any] else { return [] }
    return days
}

func cachedLessons(_ d: UserDefaults = .standard) -> [Lesson] { parseLessons(cachedDays(d)) }

func saveDays(_ days: [Any], _ d: UserDefaults = .standard) {
    if let data = try? JSONSerialization.data(withJSONObject: days) {
        d.set(String(decoding: data, as: UTF8.self), forKey: Keys.days)
    }
}
