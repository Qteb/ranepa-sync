import Foundation
import SwiftUI

/// Общая часть виджета iPhone, приложения для часов и усложнений.

let appGroup = "group.com.qteb.ranepatimetable"

/// Ключи в UserDefaults группы. Их пишет Flutter (home_widget) на iPhone
/// и приложение для часов — у себя, когда получает пары с iPhone.
enum SharedKeys {
    static let lessons = "lessons"
    static let nowShift = "nowShift"
    static let receivedAt = "receivedAt"
}

struct LessonItem: Codable, Hashable {
    let s: Double
    let e: Double
    let t: String
    let k: String
    let r: String

    var start: Date { Date(timeIntervalSince1970: s) }
    var end: Date { Date(timeIntervalSince1970: e) }
}

func loadLessons() -> [LessonItem] {
    guard
        let raw = UserDefaults(suiteName: appGroup)?.string(forKey: SharedKeys.lessons),
        let data = raw.data(using: .utf8),
        let items = try? JSONDecoder().decode([LessonItem].self, from: data)
    else { return [] }
    return items.sorted { $0.s < $1.s }
}

/// Сдвиг часов. Ненулевой только в сборке для скриншотов (DEMO_AT во Flutter).
func clockShift() -> TimeInterval {
    UserDefaults(suiteName: appGroup)?.double(forKey: SharedKeys.nowShift) ?? 0
}

/// Цвет типа пары — как в приложении (lib/widgets/lesson_colors.dart).
func kindColor(_ kind: String) -> Color {
    switch kind {
    case "лекция": return .blue
    case "семинар": return .green
    case "физкультура": return .orange
    case "лабораторная": return .purple
    case "консультация": return .teal
    case "экзамен", "зачёт": return .pink
    default: return .gray
    }
}

func dayLabel(_ date: Date, from now: Date) -> String {
    let cal = Calendar.current
    if cal.isDate(date, inSameDayAs: now) { return "Сегодня" }
    if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: tomorrow) {
        return "Завтра"
    }
    let f = DateFormatter()
    f.locale = Locale(identifier: "ru_RU")
    f.dateFormat = "EE, d MMMM"
    return f.string(from: date).capitalized
}

func hm(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f.string(from: date)
}

/// «40 мин», «1 ч», «1 ч 2 мин» — как в приложении.
func durationLabel(_ seconds: TimeInterval) -> String {
    let total = max(0, Int((seconds / 60).rounded(.up)))
    let h = total / 60, m = total % 60
    if h == 0 { return "\(m) мин" }
    return m == 0 ? "\(h) ч" : "\(h) ч \(m) мин"
}

/// Что сейчас: идущая пара, следующая сегодня или ближайшая в другой день.
struct LessonState {
    let current: LessonItem?
    let next: LessonItem?
    let today: [LessonItem]

    init(lessons: [LessonItem], now: Date) {
        let cal = Calendar.current
        today = lessons.filter { cal.isDate($0.start, inSameDayAs: now) }
        current = lessons.first { $0.start <= now && now < $0.end }
        next = lessons.first { $0.start > now }
    }
}
