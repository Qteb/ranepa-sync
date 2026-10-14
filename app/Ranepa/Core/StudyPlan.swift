import Foundation

/// План обучения из ЛК: предметы всех семестров с формой контроля и даты сессий.
struct StudyPlan: Codable {
    struct Item: Codable, Hashable {
        let name: String
        /// «Зачет», «Экзамен», «Зачет с оценкой»…; nil — код не из справочника.
        let control: String?
        let hours: Int
        let ze: Int
        let course: Int
        /// «1-й семестр».
        let semester: String
        let elective: Bool
        let practice: Bool
        let courseWork: Bool
        let facultative: Bool
        let selected: Bool

        var semesterNumber: Int { Int(semester.prefix { $0.isNumber }) ?? 0 }
        /// «СОЦИОГУМАНИТАРНАЯ ЧАСТЬ» — заголовок модуля, не предмет.
        var isHeader: Bool { name == name.uppercased() && name.contains(where: \.isLetter) }
        /// «Экзамен», «Зачёт», «Диф. зачёт», «Курсовая» — коротко для пометки.
        var form: String? { control.map(shortForm) }
        var isExam: Bool { control?.localizedCaseInsensitiveContains("экзамен") ?? false }
        var isCredit: Bool { !isExam && (control?.localizedCaseInsensitiveContains("зач") ?? false) }
    }

    struct Session: Codable, Hashable {
        let course: String
        let semester: String
        /// «11.01.2027».
        let start: String
        let end: String

        var semesterNumber: Int { Int(semester.prefix { $0.isNumber }) ?? 0 }
        var startDate: Date? { Self.date(start) }
        /// Конец дня последнего дня сессии.
        var endDate: Date? { Self.date(end)?.adding(days: 1) }

        private static func date(_ s: String) -> Date? {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "dd.MM.yyyy"
            return f.date(from: s)
        }
    }

    let items: [Item]
    let sessions: [Session]

    static func cached(_ d: UserDefaults = .standard) -> StudyPlan? {
        guard let data = d.string(forKey: Keys.plan)?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StudyPlan.self, from: data)
    }

    /// Предметы семестра без заголовков модулей и невыбранных дисциплин по выбору.
    func subjects(semester: Int) -> [Item] {
        var seen = Set<String>()
        return items.filter { $0.semesterNumber == semester && !$0.isHeader && $0.selected && seen.insert($0.name).inserted }
    }

    var semesters: [Int] { Array(Set(items.map(\.semesterNumber))).filter { $0 > 0 }.sorted() }

    /// Сессии семестра (бывает две — у последнего курса), по порядку.
    func sessions(semester: Int) -> [Session] {
        sessions.filter { $0.semesterNumber == semester }.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    /// Текущий семестр — тот, чья сессия ещё не закончилась.
    func currentSemester(now: Date) -> Int? {
        sessions.filter { ($0.endDate ?? .distantPast) > now }
            .min { ($0.endDate ?? .distantFuture) < ($1.endDate ?? .distantFuture) }?.semesterNumber
    }

    /// «1-й курс» для семестра.
    func course(semester: Int) -> String? { sessions(semester: semester).first?.course }

    /// Предмет из плана по названию в расписании.
    func item(named name: String, semester: Int?) -> Item? {
        let pool = semester.map { s in items.filter { $0.semesterNumber == s } } ?? items
        return pool.first { $0.name == name } ?? pool.first { $0.name.lowercased() == name.lowercased() }
    }
}

private func shortForm(_ control: String) -> String {
    let c = control.lowercased()
    if c.contains("экзамен") { return "Экзамен" }
    if c.contains("с оценкой") || c.contains("диф") { return "Диф. зачёт" }
    if c.contains("зачет") || c.contains("зачёт") { return "Зачёт" }
    if c.contains("курсов") { return "Курсовая" }
    return control
}

/// «11–30 января», «28 декабря – 26 января».
func dateRange(_ a: Date, _ b: Date) -> String {
    if a.sameDay(b) { return "\(a.day) \(monthsGenitive[a.month - 1])" }
    if a.month == b.month { return "\(a.day)–\(b.day) \(monthsGenitive[b.month - 1])" }
    return "\(a.day) \(monthsGenitive[a.month - 1]) – \(b.day) \(monthsGenitive[b.month - 1])"
}
