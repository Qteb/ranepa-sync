import SwiftUI
import UIKit
import WidgetKit

// Как акцент приложения: в тёмной теме светлее, иначе тонет в фоне.
private let accent = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.90, green: 0.45, blue: 0.50, alpha: 1)
        : UIColor(red: 0.56, green: 0.11, blue: 0.18, alpha: 1)
})

/// До пары меньше трёх часов — показываем обратный отсчёт, иначе время.
private let countdownWindow: TimeInterval = 3 * 3600

// MARK: - Тексты

extension LessonsEntry {
    /// Пара, о которой виджет говорит в первую очередь: идущая или следующая.
    var lead: LessonItem? { state.current ?? state.next }

    func isOngoing(_ l: LessonItem) -> Bool { l.start <= now && now < l.end }

    /// Отсчёт до начала: пара сегодня и скоро.
    func countsDown(to l: LessonItem) -> Bool {
        display == .remaining && Calendar.current.isDate(l.start, inSameDayAs: now)
            && l.start.timeIntervalSince(now) <= countdownWindow
    }

    func link(_ l: LessonItem?) -> URL? { l.map { lessonURL(real($0.start)) } }

    /// «Сегодня», «Завтра», «Четверг».
    func dayName(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) { return "Сегодня" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: tomorrow) {
            return "Завтра"
        }
        return format(date, "EEEE").capitalizedFirst
    }

    /// Подпись над крупным числом, само число и строка справа вверху.
    func leadText(_ l: LessonItem) -> (caption: String, value: String, trailing: String) {
        if isOngoing(l) {
            return display == .remaining
                ? ("До конца", durationLabel(l.end.timeIntervalSince(now)), "до \(hm(l.end))")
                : ("Идёт до", hm(l.end), "с \(hm(l.start))")
        }
        if countsDown(to: l) {
            return ("До начала", durationLabel(l.start.timeIntervalSince(now)), "в \(hm(l.start))")
        }
        return (dayName(l.start), hm(l.start), "до \(hm(l.end))")
    }
}

func format(_ date: Date, _ pattern: String) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ru_RU")
    f.dateFormat = pattern
    return f.string(from: date)
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Раскладка, которая прячет то, что не влезло

/// Заголовок дня: показываем, только если под ним влезает хотя бы одна пара.
private struct FitHeader: LayoutValueKey {
    static let defaultValue = false
}

/// Столбец, который не обрезает строку посередине: всё, что не влезло
/// целиком, просто не показывается.
private struct FitStack: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = ProposedViewSize(width: bounds.width, height: nil)
        let heights = subviews.map { $0.sizeThatFits(width).height }
        var y = bounds.minY
        var full = false
        for (i, view) in subviews.enumerated() {
            var needed = heights[i]
            if view[FitHeader.self], i + 1 < subviews.count { needed += spacing + heights[i + 1] }
            full = full || y + needed > bounds.maxY + 0.5
            if full {
                view.place(at: CGPoint(x: bounds.minX, y: bounds.maxY + 1000), proposal: .zero)
                continue
            }
            view.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: heights[i]))
            y += heights[i] + spacing
        }
    }
}

// MARK: - Общие части

private struct Stripe: View {
    let lesson: LessonItem
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(lesson.cancelled ? Color.secondary.opacity(0.5) : kindColor(lesson.k))
            .frame(width: 3)
            .widgetAccentable()
    }
}

private struct EmptyLessons: View {
    let loaded: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Расписание").font(.system(size: 13, weight: .bold)).foregroundStyle(accent).widgetAccentable()
            Text(loaded ? "Ближайших пар нет" : "Открой приложение, чтобы загрузить пары")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Крупно — сколько осталось или время; ниже предмет и аудитория.
private struct LeadBlock: View {
    let entry: LessonsEntry
    let lesson: LessonItem

    var body: some View {
        let text = entry.leadText(lesson)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: kindSymbol(lesson.k))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(kindColor(lesson.k))
                    .widgetAccentable()
                    .accessibilityHidden(true)
                Spacer(minLength: 4)
                Text(text.trailing).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Text(text.caption)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .widgetAccentable()
            Text(text.value)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText(countsDown: true))
                .padding(.bottom, 2)
            Text(lesson.t).font(.system(size: 13, weight: .semibold)).lineLimit(2)
            Text(lesson.r).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).padding(.top, 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - «Следующая пара»

struct NextLessonView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LessonsEntry

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(entry.link(family == .accessoryCircular ? entry.state.next : entry.lead))
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        case .accessoryCircular: NextCircle(entry: entry)
        default:
            if let lead = entry.lead {
                LeadBlock(entry: entry, lesson: lead)
            } else {
                EmptyLessons(loaded: !entry.lessons.isEmpty)
            }
        }
    }

    /// «1 - 2317 · ещё 55 мин», «12:20 · Стадион», «Завтра 10:40 · 5 - 201».
    private func detail(_ l: LessonItem) -> String {
        let now = entry.now
        if entry.isOngoing(l) {
            return entry.display == .remaining
                ? "\(l.r) · ещё \(durationLabel(l.end.timeIntervalSince(now)))"
                : "\(l.r) · до \(hm(l.end))"
        }
        if entry.countsDown(to: l) { return "\(l.r) · через \(durationLabel(l.start.timeIntervalSince(now)))" }
        let day = entry.dayName(l.start)
        return day == "Сегодня" ? "\(hm(l.start)) · \(l.r)" : "\(day) \(hm(l.start)) · \(l.r)"
    }

    @ViewBuilder private var rectangular: some View {
        if let l = entry.lead {
            VStack(alignment: .leading, spacing: 1) {
                Text(l.t).font(.headline).lineLimit(entry.isOngoing(l) ? 1 : 2)
                if entry.isOngoing(l) {
                    // Аудитория слева, время справа: одной строкой не влезает.
                    HStack {
                        Text(l.r).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(entry.display == .remaining
                             ? durationLabel(l.end.timeIntervalSince(entry.now)) : "до \(hm(l.end))")
                            .layoutPriority(1)
                    }
                } else {
                    Text(rectUpcoming(l)).lineLimit(1)
                }
                if entry.isOngoing(l) {
                    // Полоска идёт сама, без новых записей в ленте.
                    ProgressView(timerInterval: entry.real(l.start)...entry.real(l.end), countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(entry.lessons.isEmpty ? "Нет расписания" : "Ближайших пар нет")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// «12:20 · Стадион», «Завтра 10:40 · 5 - 201».
    private func rectUpcoming(_ l: LessonItem) -> String {
        let day = entry.dayName(l.start)
        return day == "Сегодня" ? "\(hm(l.start)) · \(l.r)" : "\(day) \(hm(l.start)) · \(l.r)"
    }

    @ViewBuilder private var inline: some View {
        if let l = entry.lead {
            ViewThatFits {
                Label { Text(detail(l)) } icon: { Image(systemName: kindSymbol(l.k)) }
                Text(detail(l))
            }
        } else {
            Text("Пар нет")
        }
    }
}

/// Круглый: когда начнётся следующая пара.
private struct NextCircle: View {
    let entry: LessonsEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let next = entry.state.next {
                VStack(spacing: 1) {
                    if Calendar.current.isDate(next.start, inSameDayAs: entry.now) {
                        Image(systemName: kindSymbol(next.k)).font(.system(size: 14, weight: .semibold))
                    } else {
                        Text(format(next.start, "EE").uppercased()).font(.system(size: 11, weight: .semibold))
                    }
                    Text(hm(next.start)).font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Следующая пара: \(entry.dayName(next.start)), \(hm(next.start)), \(next.t)")
            } else {
                Image(systemName: "moon.zzz.fill").font(.system(size: 18))
                    .accessibilityLabel("Пар нет")
            }
        }
    }
}

// MARK: - «До конца пары»

struct ProgressCircleView: View {
    let entry: LessonsEntry

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(entry.link(entry.lead))
    }

    @ViewBuilder private var content: some View {
        if let c = entry.state.current {
            let total = c.end.timeIntervalSince(c.start)
            let done = entry.now.timeIntervalSince(c.start)
            let left = Int((c.end.timeIntervalSince(entry.now) / 60).rounded(.up))
            Gauge(value: done / total) {
                EmptyView()
            } currentValueLabel: {
                VStack(spacing: -2) {
                    Text("\(left)").font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("мин").font(.system(size: 10, weight: .medium))
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityLabel("\(c.t): до конца \(durationLabel(c.end.timeIntervalSince(entry.now)))")
        } else {
            // Перерыв и вечер: когда следующая.
            NextCircle(entry: entry)
        }
    }
}

// MARK: - «Пары»

struct LessonsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LessonsEntry

    var body: some View {
        Group {
            if let lead = entry.lead {
                switch family {
                case .systemLarge: large(lead)
                case .accessoryRectangular: lockList(lead)
                default: medium(lead)
                }
            } else {
                EmptyLessons(loaded: !entry.lessons.isEmpty)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(entry.link(entry.lead))
    }

    /// Дни с оставшимися парами (и отменёнными), начиная с дня ведущей.
    private func days(from lead: LessonItem) -> [(day: Date, lessons: [LessonItem])] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: lead.start)
        var result: [(day: Date, lessons: [LessonItem])] = []
        for l in entry.lessons where l.end > entry.now && l.start >= dayStart {
            if let last = result.last, cal.isDate(last.day, inSameDayAs: l.start) {
                result[result.count - 1].lessons.append(l)
            } else if result.count < 2 {
                result.append((l.start, [l]))
            } else {
                break
            }
        }
        return result
    }

    // Средний: слева — как «Следующая пара», справа — что потом.
    private func medium(_ lead: LessonItem) -> some View {
        let days = days(from: lead)
        let rest = days.first?.lessons.filter { $0.start > lead.start } ?? []
        let later = rest.isEmpty ? days.dropFirst().first : nil
        return HStack(alignment: .top, spacing: 16) {
            LeadBlock(entry: entry, lesson: lead).frame(width: 138)
            FitStack(spacing: 9) {
                if !rest.isEmpty {
                    Text("Потом").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        .layoutValue(key: FitHeader.self, value: true)
                    ForEach(rest, id: \.self) { CompactRow(lesson: $0) }
                } else if let later {
                    Text(entry.dayName(later.day)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        .layoutValue(key: FitHeader.self, value: true)
                    ForEach(later.lessons, id: \.self) { CompactRow(lesson: $0) }
                } else {
                    Text("Больше пар нет").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
        }
    }

    // Экран блокировки: три ближайшие пары строками «12:20 Физкультура».
    private func lockList(_ lead: LessonItem) -> some View {
        let items = entry.lessons.filter { !$0.cancelled && $0.start >= lead.start }.prefix(3)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items), id: \.self) { l in
                HStack(spacing: 4) {
                    Text(hm(l.start)).fontWeight(.semibold).monospacedDigit()
                    Text(l.t).lineLimit(1)
                }
            }
        }
        .font(.system(size: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Большой: день по порядку, со временем, аудиторией и преподавателем.
    private func large(_ lead: LessonItem) -> some View {
        FitStack(spacing: 10) {
            ForEach(Array(days(from: lead).enumerated()), id: \.offset) { _, day in
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.dayName(day.day))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(accent)
                        .widgetAccentable()
                    Spacer()
                    // «Сегодня · вторник, 13 октября», «Четверг · 15 октября».
                    Text(format(day.day, ["Сегодня", "Завтра"].contains(entry.dayName(day.day)) ? "EEEE, d MMMM" : "d MMMM"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .layoutValue(key: FitHeader.self, value: true)
                ForEach(day.lessons, id: \.self) { BigRow(entry: entry, lesson: $0) }
            }
        }
    }
}

private struct CompactRow: View {
    let lesson: LessonItem
    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Stripe(lesson: lesson)
            VStack(alignment: .leading, spacing: 1) {
                Text(lesson.t)
                    .font(.system(size: 13, weight: .semibold))
                    .strikethrough(lesson.cancelled)
                    .foregroundStyle(lesson.cancelled ? .secondary : .primary)
                    .lineLimit(1)
                Text(lesson.cancelled ? "\(hm(lesson.start)) · отменена" : "\(hm(lesson.start))–\(hm(lesson.end)) · \(lesson.r)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

private struct BigRow: View {
    let entry: LessonsEntry
    let lesson: LessonItem

    private var place: String {
        guard entry.address, let a = lesson.a else { return lesson.r }
        return "\(lesson.r) · \(a)"
    }

    var body: some View {
        let ongoing = !lesson.cancelled && entry.isOngoing(lesson)
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(hm(lesson.start)).font(.system(size: 13, weight: .semibold))
                Text(hm(lesson.end)).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .frame(width: 40, alignment: .trailing)
            Stripe(lesson: lesson)
            VStack(alignment: .leading, spacing: 1) {
                Text(lesson.t)
                    .font(.system(size: 14, weight: .semibold))
                    .strikethrough(lesson.cancelled)
                    .foregroundStyle(lesson.cancelled ? .secondary : .primary)
                    .lineLimit(2)
                Text(place).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                if entry.lecturer, let lecturer = lesson.l, !lesson.cancelled {
                    Text(lecturer).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                if lesson.cancelled {
                    Text("Отменена").font(.system(size: 12, weight: .semibold)).foregroundStyle(.red)
                } else if ongoing {
                    Text("ещё \(durationLabel(lesson.end.timeIntervalSince(entry.now)))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                        .widgetAccentable()
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}
