import SwiftUI
import UIKit
import WidgetKit

struct LessonsEntry: TimelineEntry {
    /// Когда WidgetKit показывает запись — по настоящим часам.
    let shown: Date
    let lessons: [LessonItem]
    let shift: TimeInterval

    init(date: Date, lessons: [LessonItem], shift: TimeInterval = clockShift()) {
        self.shown = date.addingTimeInterval(-shift)
        self.lessons = lessons
        self.shift = shift
    }

    var date: Date { shown }

    /// Время, которое видит виджет: с учётом сдвига для скриншотов.
    var now: Date { shown.addingTimeInterval(shift) }

    /// Ближайший учебный день начиная с момента записи и его оставшиеся пары.
    var day: (date: Date, lessons: [LessonItem])? {
        let cal = Calendar.current
        guard let first = lessons.first(where: { $0.end > now }) else { return nil }
        let items = lessons.filter { $0.end > now && cal.isDate($0.start, inSameDayAs: first.start) }
        return (first.start, items)
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> LessonsEntry {
        let now = Date().addingTimeInterval(clockShift())
        return LessonsEntry(date: now, lessons: [
            LessonItem(s: now.timeIntervalSince1970 + 600, e: now.timeIntervalSince1970 + 6000,
                       t: "Микроэкономика", k: "лекция", r: "Ауд. 101"),
            LessonItem(s: now.timeIntervalSince1970 + 6600, e: now.timeIntervalSince1970 + 12000,
                       t: "Высшая математика", k: "семинар", r: "Ауд. 202"),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (LessonsEntry) -> Void) {
        let lessons = loadLessons()
        completion(lessons.isEmpty && context.isPreview ? placeholder(in: context)
                                                        : LessonsEntry(date: Date().addingTimeInterval(clockShift()), lessons: lessons))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LessonsEntry>) -> Void) {
        let lessons = loadLessons()
        let now = Date().addingTimeInterval(clockShift())
        let cal = Calendar.current
        // Новая запись к концу каждой пары и к каждой полуночи: виджет сам
        // убирает прошедшее, даже если приложение давно не открывали.
        var dates = Set([now])
        for l in lessons where l.end > now { dates.insert(l.end) }
        for d in 1...3 {
            if let midnight = cal.date(byAdding: .day, value: d, to: cal.startOfDay(for: now)) {
                dates.insert(midnight)
            }
        }
        let entries = dates.sorted().prefix(40).map { LessonsEntry(date: $0, lessons: lessons) }
        completion(Timeline(entries: Array(entries), policy: .atEnd))
    }
}

// Как акцент приложения: в тёмной теме светлее, иначе тонет в фоне.
private let accent = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.90, green: 0.45, blue: 0.50, alpha: 1)
        : UIColor(red: 0.56, green: 0.11, blue: 0.18, alpha: 1)
})

struct LessonRow: View {
    let lesson: LessonItem
    let now: Date
    let compact: Bool

    var body: some View {
        let ongoing = lesson.start <= now && now < lesson.end
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(kindColor(lesson.k))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(lesson.t)
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .lineLimit(compact ? 2 : 1)
                Text("\(hm(lesson.start))–\(hm(lesson.end))\(lesson.r.isEmpty ? "" : " · \(lesson.r)")")
                    .font(.system(size: 11))
                    .foregroundStyle(ongoing ? accent : .secondary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct RanepaWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: LessonsEntry

    var body: some View {
        switch family {
        case .accessoryRectangular: lockScreen
        default: home
        }
    }

    private var maxRows: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 3
        default: return 7
        }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let day = entry.day {
                Text(dayLabel(day.date, from: entry.now))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accent)
                ForEach(day.lessons.prefix(maxRows), id: \.self) {
                    LessonRow(lesson: $0, now: entry.now, compact: family == .systemSmall)
                }
                if day.lessons.count > maxRows {
                    Text("ещё \(day.lessons.count - maxRows)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Расписание").font(.system(size: 13, weight: .bold)).foregroundStyle(accent)
                Text("Пар пока нет. Открой приложение, чтобы обновить.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let lesson = entry.day?.lessons.first {
                Text("\(hm(lesson.start)) · \(lesson.r)").font(.system(size: 12, weight: .semibold))
                Text(lesson.t).font(.system(size: 13)).lineLimit(2)
            } else {
                Text("Пар нет").font(.system(size: 13))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@main
struct RanepaWidget: Widget {
    let kind = "RanepaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            RanepaWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Пары")
        .description("Ближайшие пары на сегодня или следующий учебный день.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}
