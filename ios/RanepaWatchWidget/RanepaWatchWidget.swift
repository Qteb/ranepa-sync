import SwiftUI
import WidgetKit

/// Усложнения циферблата и виджет смарт-стопки на Apple Watch. Пары
/// сохраняет приложение для часов, когда получает их с iPhone.
struct WatchEntry: TimelineEntry {
    /// Когда WidgetKit показывает запись — по настоящим часам.
    let date: Date
    let lessons: [LessonItem]
    let shift: TimeInterval

    /// Время, которое видит усложнение: со сдвигом для скриншотов.
    var now: Date { date.addingTimeInterval(shift) }
    var state: LessonState { LessonState(lessons: lessons, now: now) }
}

struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry {
        let now = Date().timeIntervalSince1970
        return WatchEntry(date: Date(), lessons: [
            LessonItem(s: now - 1200, e: now + 3600, t: "Иностранный язык", k: "семинар", r: "1 - 2317"),
            LessonItem(s: now + 4800, e: now + 9600, t: "Физкультура", k: "физкультура", r: "Спорткомплекс"),
        ], shift: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        let lessons = loadLessons()
        completion(lessons.isEmpty && context.isPreview
            ? placeholder(in: context)
            : WatchEntry(date: Date(), lessons: lessons, shift: clockShift()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let lessons = loadLessons()
        let shift = clockShift()
        let now = Date()
        // Новая запись к началу и концу каждой пары и к полуночи: усложнение
        // переключается само, даже если телефон далеко.
        var dates = Set([now])
        for l in lessons {
            for t in [l.start, l.end] {
                let shown = t.addingTimeInterval(-shift)
                if shown > now { dates.insert(shown) }
            }
        }
        let cal = Calendar.current
        for d in 1...2 {
            if let midnight = cal.date(byAdding: .day, value: d, to: cal.startOfDay(for: now)) {
                dates.insert(midnight)
            }
        }
        let entries = dates.sorted().prefix(60).map { WatchEntry(date: $0, lessons: lessons, shift: shift) }
        completion(Timeline(entries: Array(entries), policy: .atEnd))
    }
}

private let accent = Color(red: 0.90, green: 0.45, blue: 0.50)

/// Пара в усложнении: идущая или ближайшая.
private struct Focus {
    let lesson: LessonItem
    let ongoing: Bool
}

private func focus(_ entry: WatchEntry) -> Focus? {
    let s = entry.state
    if let c = s.current { return Focus(lesson: c, ongoing: true) }
    if let n = s.next { return Focus(lesson: n, ongoing: false) }
    return nil
}

/// «12:20», «завтра 09:00», «пт 09:00».
private func whenShort(_ date: Date, now: Date) -> String {
    let cal = Calendar.current
    if cal.isDate(date, inSameDayAs: now) { return hm(date) }
    if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: tomorrow) {
        return "завтра \(hm(date))"
    }
    let f = DateFormatter()
    f.locale = Locale(identifier: "ru_RU")
    f.dateFormat = "EE"
    return "\(f.string(from: date)) \(hm(date))"
}

struct WatchWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: WatchEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryCorner: corner
        case .accessoryInline: inline
        default: rectangular
        }
    }

    // Смарт-стопка и прямоугольное усложнение.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let f = focus(entry) {
                let l = f.lesson
                HStack {
                    Text(f.ongoing ? "СЕЙЧАС" : whenShort(l.start, now: entry.now).uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                        .widgetAccentable()
                    Spacer(minLength: 4)
                    if f.ongoing {
                        Text("ещё \(durationLabel(l.end.timeIntervalSince(entry.now)))")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                // Длинное название — в две строки, тогда «Дальше» не помещается.
                ViewThatFits(in: .horizontal) {
                    VStack(alignment: .leading, spacing: 1) {
                        lessonBlock(l, titleLines: 1)
                        if f.ongoing, let next = entry.state.next {
                            Text("Дальше \(whenShort(next.start, now: entry.now)) · \(next.t)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    lessonBlock(l, titleLines: 2)
                }
            } else {
                Text("РАСПИСАНИЕ").font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
                Text("Пар нет").font(.system(size: 15, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lessonBlock(_ l: LessonItem, titleLines: Int) -> some View {
        HStack(alignment: .top, spacing: 5) {
            KindIcon(kind: l.k, size: 13).padding(.top, 2)
            VStack(alignment: .leading, spacing: 0) {
                Text(l.t)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(titleLines)
                    // Одна строка — по полной ширине: если не влезает,
                    // ViewThatFits выберет вариант в две строки.
                    .fixedSize(horizontal: titleLines == 1, vertical: true)
                Text("\(hm(l.start))–\(hm(l.end)) · \(l.r)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // Круг: прогресс идущей пары или время следующей.
    @ViewBuilder private var circular: some View {
        if let f = focus(entry), f.ongoing {
            let l = f.lesson
            Gauge(value: entry.now.timeIntervalSince(l.start), in: 0...l.end.timeIntervalSince(l.start)) {
                Text("пара")
            } currentValueLabel: {
                // Иконка типа в кольце; минуты — в прямоугольном и угловом.
                Image(systemName: kindSymbol(l.k))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(accent)
        } else if let f = focus(entry) {
            VStack(spacing: 0) {
                Image(systemName: kindSymbol(f.lesson.k)).font(.system(size: 11)).widgetAccentable()
                Text(hm(f.lesson.start)).font(.system(size: 13, weight: .semibold)).minimumScaleFactor(0.7)
            }
        } else {
            Image(systemName: "calendar").widgetAccentable()
        }
    }

    // Угол: минуты до конца или время следующей, с полоской прогресса.
    @ViewBuilder private var corner: some View {
        if let f = focus(entry) {
            let l = f.lesson
            Text(f.ongoing ? "\(max(0, Int((l.end.timeIntervalSince(entry.now) / 60).rounded(.up))))м" : hm(l.start))
                .font(.system(size: 14, weight: .semibold))
                .widgetAccentable()
                .widgetLabel {
                    if f.ongoing {
                        Gauge(value: entry.now.timeIntervalSince(l.start), in: 0...l.end.timeIntervalSince(l.start)) {
                            Text(l.r)
                        }
                        .tint(accent)
                    } else {
                        Text(l.r.isEmpty ? l.t : l.r)
                    }
                }
        } else {
            Image(systemName: "calendar").widgetAccentable()
        }
    }

    // Строка над временем.
    private var inline: some View {
        if let f = focus(entry) {
            let l = f.lesson
            let place = l.r.isEmpty ? "" : " · \(l.r)"
            return Text(f.ongoing ? "До \(hm(l.end))\(place)" : "\(whenShort(l.start, now: entry.now)) \(l.t)\(place)")
        }
        return Text("Пар нет")
    }
}

@main
struct RanepaWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RanepaWatchWidget", provider: WatchProvider()) { entry in
            WatchWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Пары")
        .description("Идущая или ближайшая пара.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}
