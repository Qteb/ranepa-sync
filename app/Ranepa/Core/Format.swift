import Foundation

let weekdaysShort = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
let weekdaysLong = ["Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"]
let monthsNominative = ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль",
                        "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"]
let monthsGenitive = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля",
                      "августа", "сентября", "октября", "ноября", "декабря"]
private let weekdaysAccusative = ["в понедельник", "во вторник", "в среду", "в четверг",
                                  "в пятницу", "в субботу", "в воскресенье"]

/// Часы приложения. Для скриншотов их можно перевести аргументом запуска
/// `-DEMO_AT 2026-10-13T11:05`: дальше они идут как обычно.
enum Clock {
    static let shift: TimeInterval = {
        guard let raw = UserDefaults.standard.string(forKey: "DEMO_AT") else { return 0 }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f.date(from: raw).map { $0.timeIntervalSinceNow } ?? 0
    }()

    static var now: Date { Date().addingTimeInterval(shift) }

    /// Сборка для скриншотов App Store: демо выглядит как обычный аккаунт.
    static let screenshotMode = UserDefaults.standard.string(forKey: "DEMO_AT") != nil

    /// Запись видео: отладочная сборка, которая выглядит как релизная.
    static let recordingMode = UserDefaults.standard.bool(forKey: "RECORDING")

    /// Раздел «Отладка» в настройках.
    static var debugTools: Bool {
        #if DEBUG || TEST_TOOLS
        return !recordingMode && !screenshotMode
        #else
        return false
        #endif
    }
}

/// Григорианский календарь с понедельником в начале недели.
let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.locale = Locale(identifier: "ru_RU")
    c.firstWeekday = 2
    return c
}()

extension Date {
    var dateOnly: Date { calendar.startOfDay(for: self) }

    /// 1 — понедельник, 7 — воскресенье.
    var isoWeekday: Int { (calendar.component(.weekday, from: self) + 5) % 7 + 1 }

    var monday: Date { dateOnly.adding(days: 1 - isoWeekday) }

    var day: Int { calendar.component(.day, from: self) }
    var month: Int { calendar.component(.month, from: self) }
    var year: Int { calendar.component(.year, from: self) }
    var hour: Int { calendar.component(.hour, from: self) }

    func adding(days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: self)! }

    func sameDay(_ other: Date) -> Bool { calendar.isDate(self, inSameDayAs: other) }

    /// Целых дней от начала [other] до начала этого дня.
    func days(since other: Date) -> Int {
        calendar.dateComponents([.day], from: other.dateOnly, to: dateOnly).day ?? 0
    }
}

/// «Среда, 14 октября».
func dayTitle(_ d: Date) -> String {
    "\(weekdaysLong[d.isoWeekday - 1]), \(d.day) \(monthsGenitive[d.month - 1])"
}

/// «Сегодня», «Завтра», «Вчера» или день недели.
func relativeDayName(_ d: Date) -> String {
    switch d.days(since: Clock.now) {
    case 0: "Сегодня"
    case 1: "Завтра"
    case -1: "Вчера"
    default: weekdaysLong[d.isoWeekday - 1]
    }
}

/// «40 мин», «1 ч», «1 ч 40 мин». Минуты округляются вниз.
func durationText(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds / 60))
    let h = total / 60, m = total % 60
    if h == 0 { return "\(m) мин" }
    return m == 0 ? "\(h) ч" : "\(h) ч \(m) мин"
}

/// «сегодня в 12:20», «завтра в 09:00», «в среду 21 октября в 09:00».
func whenLabel(_ t: Date) -> String {
    let day = switch t.days(since: Clock.now) {
    case 0: "сегодня"
    case 1: "завтра"
    default: "\(weekdaysAccusative[t.isoWeekday - 1]) \(t.day) \(monthsGenitive[t.month - 1])"
    }
    return "\(day) в \(hm(t))"
}

/// «Обновлено сегодня в 14:20», «Обновлено 12.10 в 09:00».
func shortDate(_ d: Date) -> String {
    String(format: "%d.%02d", d.day, d.month)
}

extension String {
    var capitalizedFirst: String { isEmpty ? self : prefix(1).uppercased() + dropFirst() }
}
