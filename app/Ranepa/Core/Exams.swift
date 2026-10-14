import Foundation

/// Сессия текущего семестра. Состав и даты — из плана обучения, конкретные
/// дата и аудитория — из расписания, когда появятся. Без плана (демо, план
/// не загрузился) — только события расписания.
struct ExamSession {
    struct Entry: Identifiable {
        let subject: String
        /// «Экзамен», «Зачёт», «Диф. зачёт».
        let form: String
        /// Событие в расписании; nil — дата не назначена.
        let event: Lesson?
        let consultation: Lesson?
        var id: String { subject + form }
    }

    let exams: [Entry]
    let credits: [Entry]
    /// Даты сессии по плану.
    let start: Date?
    let end: Date?

    /// Карточка на главном экране — за столько дней до начала сессии.
    static let cardDays = 30

    init?(lessons: [Lesson], plan: StudyPlan?, now: Date) {
        let active = lessons.filter { !$0.cancelled }
        let all = active.filter { $0.kind == "экзамен" || $0.kind == "зачёт" }
        let events = all.filter { $0.end > now }
        func consultation(for exam: Lesson?) -> Lesson? {
            guard let exam else { return nil }
            return active.last { $0.kind == "консультация" && $0.subject == exam.subject && $0.start < exam.start }
        }
        // С планом — и прошедшие события: сданное остаётся в сессии.
        func event(_ subject: String, exam: Bool) -> Lesson? {
            let match = all.filter { $0.subject.lowercased() == subject.lowercased() && ($0.kind == "экзамен") == exam }
            return match.first { $0.end > now } ?? match.last
        }

        if let plan, let semester = plan.currentSemester(now: now) {
            let items = plan.subjects(semester: semester)
            let sessions = plan.sessions(semester: semester)
            start = sessions.first?.startDate
            end = sessions.last?.endDate
            var exams = items.filter(\.isExam).map { i in
                let e = event(i.name, exam: true)
                return Entry(subject: i.name, form: i.form ?? "Экзамен", event: e, consultation: consultation(for: e))
            }
            var credits = items.filter(\.isCredit).map { i in
                Entry(subject: i.name, form: i.form ?? "Зачёт", event: event(i.name, exam: false), consultation: nil)
            }
            // События расписания, которых нет в плане, — тоже показываем.
            for e in events where !(exams + credits).contains(where: { $0.subject.lowercased() == e.subject.lowercased() }) {
                let entry = Entry(subject: e.subject, form: e.kind.capitalizedFirst, event: e, consultation: consultation(for: e))
                if e.kind == "экзамен" { exams.append(entry) } else { credits.append(entry) }
            }
            self.exams = exams.sorted(by: Self.order)
            self.credits = credits.sorted(by: Self.order)
        } else {
            start = nil
            end = nil
            exams = events.filter { $0.kind == "экзамен" }
                .map { Entry(subject: $0.subject, form: "Экзамен", event: $0, consultation: consultation(for: $0)) }
            credits = events.filter { $0.kind == "зачёт" }.map { Entry(subject: $0.subject, form: "Зачёт", event: $0, consultation: nil) }
        }
        guard !exams.isEmpty || !credits.isEmpty else { return nil }
        // Сессия прошла.
        if let end, end <= now, (exams + credits).allSatisfy({ $0.event == nil }) { return nil }
    }

    /// С датой — по времени, без даты — в конце по названию.
    private static func order(_ a: Entry, _ b: Entry) -> Bool {
        switch (a.event, b.event) {
        case let (x?, y?): x.start < y.start
        case (.some, nil): true
        case (nil, .some): false
        case (nil, nil): a.subject < b.subject
        }
    }

    var all: [Entry] { exams + credits }

    func isDone(_ e: Entry, now: Date) -> Bool { e.event.map { $0.end <= now } ?? false }
    /// Сколько ещё сдавать: без даты или впереди.
    func remaining(now: Date) -> Int { all.filter { !isDone($0, now: now) }.count }
    /// До конца сессии (последний день), «идёт» — после начала.
    func daysLeft(now: Date) -> Int? { lastDate.map { max(0, $0.days(since: now)) } }
    /// Ближайшее событие с датой, которое ещё впереди.
    var nextEvent: Lesson? { all.compactMap(\.event).filter { $0.end > Clock.now }.min { $0.start < $1.start } }
    /// С чего считать «через N дней»: начало сессии или первое событие.
    var firstDate: Date? { [start, nextEvent?.start].compactMap { $0 }.min() }
    /// Последний день: конец сессии или последнее событие.
    var lastDate: Date? { [end.map { $0.adding(days: -1) }, all.compactMap(\.event).map(\.start).max()].compactMap { $0 }.max() }

    func isRunning(now: Date) -> Bool { (firstDate.map { $0 <= now } ?? false) }

    /// Показывать ли карточку: до начала не больше месяца.
    func showsCard(now: Date) -> Bool { firstDate.map { $0.days(since: now) <= Self.cardDays } ?? false }

    /// «2 экзамена и 7 зачётов».
    var summary: String {
        [countLabel(exams.count, "экзамен", "экзамена", "экзаменов"),
         countLabel(credits.count, "зачёт", "зачёта", "зачётов")].compactMap { $0 }.joined(separator: " и ")
    }

    /// «11–30 января».
    var dates: String {
        guard let a = firstDate, let b = lastDate else { return "" }
        return dateRange(a, b)
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
