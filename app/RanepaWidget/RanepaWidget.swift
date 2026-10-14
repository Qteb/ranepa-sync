import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Настройки виджетов

enum TimeDisplay: String, AppEnum {
    case remaining, clock

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Время"
    static let caseDisplayRepresentations: [TimeDisplay: DisplayRepresentation] = [
        .remaining: "Сколько осталось",
        .clock: "Время",
    ]
}

struct NextLessonConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Следующая пара"

    @Parameter(title: "Показывать", default: .remaining)
    var display: TimeDisplay
}

struct LessonsConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Пары"

    @Parameter(title: "Преподаватель", default: true)
    var lecturer: Bool

    @Parameter(title: "Адрес корпуса", default: false)
    var address: Bool
}

// MARK: - Записи

struct LessonsEntry: TimelineEntry {
    /// Когда WidgetKit показывает запись — по настоящим часам.
    let date: Date
    let lessons: [LessonItem]
    let shift: TimeInterval
    var relevance: TimelineEntryRelevance?
    /// Настройки виджета.
    var display = TimeDisplay.remaining
    var lecturer = true
    var address = false

    /// Время, которое видит виджет: с учётом сдвига для скриншотов.
    var now: Date { date.addingTimeInterval(shift) }
    var state: LessonState { LessonState(lessons: lessons, now: now) }

    /// Настоящее время пары — для таймеров и ссылок.
    func real(_ date: Date) -> Date { date.addingTimeInterval(-shift) }
}

/// Общая лента для всех виджетов. С [countdown] — запись каждую минуту,
/// пока идёт пара или до неё меньше трёх часов: «55 мин» не умеет
/// отсчитывать сама система.
func lessonsTimeline(countdown: Bool, configure: (inout LessonsEntry) -> Void = { _ in }) -> Timeline<LessonsEntry> {
    let lessons = loadLessons()
    let shift = clockShift()
    let realNow = Date()
    let now = realNow.addingTimeInterval(shift)
    let cal = Calendar.current
    let window: TimeInterval = 3 * 3600
    // Каждую запись виджет рисует заранее: длинная лента — долгая отрисовка.
    let horizon: TimeInterval = 90 * 60

    var dates = Set([now])
    for l in lessons where !l.cancelled {
        if l.start > now { dates.insert(l.start) }
        if l.end > now { dates.insert(l.end) }
        // К этому моменту «Сегодня 12:20» сменится на «До начала 3 ч».
        let countdownFrom = l.start.addingTimeInterval(-window)
        if countdownFrom > now { dates.insert(countdownFrom) }
    }
    for d in 1...3 {
        if let midnight = cal.date(byAdding: .day, value: d, to: cal.startOfDay(for: now)) { dates.insert(midnight) }
    }
    let reloadAt = now.addingTimeInterval(horizon)
    if countdown {
        let active = lessons.filter { !$0.cancelled }
        var minute = cal.dateInterval(of: .minute, for: now)!.end
        while minute < reloadAt {
            if active.contains(where: { $0.end > minute && $0.start.addingTimeInterval(-window) < minute }) {
                dates.insert(minute)
            }
            minute += 60
        }
    }
    let entries = dates.filter { $0 < reloadAt }.sorted().map { date in
        var entry = LessonsEntry(date: date.addingTimeInterval(-shift), lessons: lessons, shift: shift,
                                 relevance: relevance(lessons, at: date))
        configure(&entry)
        return entry
    }
    // Через полтора часа — новая лента со следующими минутами.
    return Timeline(entries: entries, policy: .after(reloadAt.addingTimeInterval(-shift)))
}

/// Смарт-стопка поднимает виджет за час до пары и пока она идёт.
private func relevance(_ lessons: [LessonItem], at date: Date) -> TimelineEntryRelevance {
    let soon = lessons.contains { !$0.cancelled && $0.end > date && $0.start.addingTimeInterval(-3600) <= date }
    return TimelineEntryRelevance(score: soon ? 1 : 0.1)
}

private func sampleLessons() -> [LessonItem] {
    let now = Date().addingTimeInterval(clockShift()).timeIntervalSince1970
    return [
        LessonItem(s: now - 1500, e: now + 3300, t: "Иностранный язык (английский)", k: "семинар", r: "1 - 2317",
                   l: "Морозова Ксения Олеговна", a: "Вернадского, 84, корпус 1"),
        LessonItem(s: now + 4500, e: now + 9300, t: "Физкультура", k: "физкультура", r: "Стадион",
                   l: "Васильев Денис Сергеевич", a: "Вернадского, 82"),
        LessonItem(s: now + 9300 + 1200, e: now + 9300 + 6000, t: "Информационные технологии в управлении",
                   k: "лабораторная", r: "1 - 1112", l: "Тихонов Павел Андреевич", a: "Вернадского, 84, корпус 1"),
    ]
}

private func sampleEntry() -> LessonsEntry {
    LessonsEntry(date: Date(), lessons: sampleLessons(), shift: clockShift())
}

/// В галерее виджетов до первого входа — пример, а не пустой виджет.
private func snapshotEntry(_ isPreview: Bool, configure: (inout LessonsEntry) -> Void = { _ in }) -> LessonsEntry {
    let lessons = loadLessons()
    var entry = lessons.isEmpty && isPreview ? sampleEntry() : LessonsEntry(date: Date(), lessons: lessons, shift: clockShift())
    configure(&entry)
    return entry
}

extension NextLessonConfig {
    func apply(_ e: inout LessonsEntry) { e.display = display }
}

extension LessonsConfig {
    func apply(_ e: inout LessonsEntry) {
        e.lecturer = lecturer
        e.address = address
    }
}

struct NextLessonProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LessonsEntry { sampleEntry() }
    func snapshot(for configuration: NextLessonConfig, in context: Context) async -> LessonsEntry {
        snapshotEntry(context.isPreview, configure: configuration.apply)
    }
    func timeline(for configuration: NextLessonConfig, in context: Context) async -> Timeline<LessonsEntry> {
        // Круглый виджет показывает только время начала — минуты ему не нужны.
        let countdown = configuration.display == .remaining && context.family != .accessoryCircular
        return lessonsTimeline(countdown: countdown, configure: configuration.apply)
    }
}

struct LessonsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LessonsEntry { sampleEntry() }
    func snapshot(for configuration: LessonsConfig, in context: Context) async -> LessonsEntry {
        snapshotEntry(context.isPreview, configure: configuration.apply)
    }
    func timeline(for configuration: LessonsConfig, in context: Context) async -> Timeline<LessonsEntry> {
        lessonsTimeline(countdown: true, configure: configuration.apply)
    }
}

struct ProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> LessonsEntry { sampleEntry() }
    func getSnapshot(in context: Context, completion: @escaping (LessonsEntry) -> Void) {
        completion(snapshotEntry(context.isPreview))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LessonsEntry>) -> Void) {
        completion(lessonsTimeline(countdown: true))
    }
}

// MARK: - Виджеты

@main
struct RanepaWidgets: WidgetBundle {
    var body: some Widget {
        NextLessonWidget()
        LessonsWidget()
        ProgressWidget()
        BuildingControl()
        TodayControl()
        LessonLiveActivity()
    }
}

struct NextLessonWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NextLesson", intent: NextLessonConfig.self, provider: NextLessonProvider()) { entry in
            NextLessonView(entry: entry)
        }
        .configurationDisplayName("Следующая пара")
        .description("Сколько осталось до конца пары или до начала следующей.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct LessonsWidget: Widget {
    var body: some WidgetConfiguration {
        // Старый kind: уже добавленные виджеты остаются на месте.
        AppIntentConfiguration(kind: "RanepaWidget", intent: LessonsConfig.self, provider: LessonsProvider()) { entry in
            LessonsView(entry: entry)
        }
        .configurationDisplayName("Пары")
        .description("Пары на сегодня, а после последней — на завтра.")
        // Прямоугольный на экране блокировки был у этого виджета и раньше:
        // без него перестают обновляться и уже добавленные средние и большие.
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct ProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PairProgress", provider: ProgressProvider()) { entry in
            ProgressCircleView(entry: entry)
        }
        .configurationDisplayName("До конца пары")
        .description("Кольцо заполняется по ходу пары.")
        .supportedFamilies([.accessoryCircular])
    }
}
