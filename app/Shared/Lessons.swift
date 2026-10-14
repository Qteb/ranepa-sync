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
    /// Отменена.
    var c: Bool? = nil
    /// Преподаватель, адрес корпуса и ссылка на корпус в выбранных Картах.
    /// Есть только в данных для виджетов iPhone.
    var l: String? = nil
    var a: String? = nil
    var m: String? = nil

    var cancelled: Bool { c ?? false }
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

/// Иконка типа пары — как в приложении (LessonColors.iconOf).
func kindSymbol(_ kind: String) -> String {
    switch kind {
    case "лекция": return "person.wave.2.fill"
    case "семинар": return "bubble.left.and.bubble.right.fill"
    case "физкультура": return "figure.run"
    case "лабораторная": return "flask.fill"
    case "консультация": return "questionmark.bubble.fill"
    case "экзамен", "зачёт": return "checkmark.seal.fill"
    default: return "book.fill"
    }
}

/// Цветная иконка типа.
struct KindIcon: View {
    let kind: String
    var size: CGFloat = 14

    var body: some View {
        Image(systemName: kindSymbol(kind))
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(kindColor(kind))
            // Тип и так звучит в тексте рядом — имя символа не читать.
            .accessibilityHidden(true)
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
        let active = lessons.filter { !$0.cancelled }
        today = lessons.filter { cal.isDate($0.start, inSameDayAs: now) }
        current = active.first { $0.start <= now && now < $0.end }
        next = active.first { $0.start > now }
    }
}
