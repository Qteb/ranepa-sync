import SwiftUI
import WatchConnectivity
import WidgetKit

/// Приложение для Apple Watch: пары на сегодня. Расписание приходит с iPhone
/// (ios/Runner/WatchBridge.swift) и хранится на часах, поэтому открывается
/// без телефона рядом.
@main
struct RanepaWatchApp: App {
    @StateObject private var store = LessonStore.shared

    var body: some Scene {
        WindowGroup {
            WeekView().environmentObject(store)
        }
        .backgroundTask(.watchConnectivity) {
            await LessonStore.shared.waitForDelivery()
        }
    }
}

/// Принимает пары с iPhone и сохраняет их в общую с усложнениями группу.
final class LessonStore: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = LessonStore()

    @Published private(set) var lessons: [LessonItem] = loadLessons()
    @Published private(set) var receivedAt: Date?

    private let defaults = UserDefaults(suiteName: appGroup)

    override init() {
        super.init()
        if let at = defaults?.object(forKey: SharedKeys.receivedAt) as? Double {
            receivedAt = Date(timeIntervalSince1970: at)
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Фоновая задача ждёт, пока сессия отдаст накопленные данные.
    func waitForDelivery() async {
        for _ in 0..<20 where WCSession.default.hasContentPending {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private func save(_ context: [String: Any]) {
        guard let raw = context[SharedKeys.lessons] as? String else { return }
        let now = Date()
        defaults?.set(raw, forKey: SharedKeys.lessons)
        defaults?.set(context[SharedKeys.nowShift] as? Double ?? 0, forKey: SharedKeys.nowShift)
        defaults?.set(now.timeIntervalSince1970, forKey: SharedKeys.receivedAt)
        WidgetCenter.shared.reloadAllTimelines()
        let fresh = loadLessons()
        DispatchQueue.main.async {
            self.lessons = fresh
            self.receivedAt = now
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if !session.receivedApplicationContext.isEmpty { save(session.receivedApplicationContext) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        save(context)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        save(userInfo)
    }
}

/// Акцент приложения в тёмной теме — на часах она всегда тёмная.
let watchAccent = Color(red: 0.90, green: 0.45, blue: 0.50)

/// Текущая неделя: колёсико или свайп листают дни, открывается на сегодня.
struct WeekView: View {
    @EnvironmentObject var store: LessonStore
    @State private var selected: Date?

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                let now = context.date.addingTimeInterval(clockShift())
                if store.lessons.isEmpty {
                    List {
                        Text("Открой «Расписание» на iPhone — пары появятся здесь.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .navigationTitle("Сегодня")
                } else {
                    let days = weekDays(around: now)
                    TabView(selection: $selected) {
                        ForEach(days, id: \.self) { day in
                            DayPage(day: day, now: now, lessons: store.lessons, receivedAt: store.receivedAt)
                                .tag(Optional(day))
                        }
                    }
                    .tabViewStyle(.verticalPage)
                    .onAppear { selected = Calendar.current.startOfDay(for: now) }
                }
            }
        }
        .tint(watchAccent)
    }

    /// Понедельник–воскресенье недели, в которой [now].
    private func weekDays(around now: Date) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let today = cal.startOfDay(for: now)
        let weekday = (cal.component(.weekday, from: today) + 5) % 7  // пн = 0
        let monday = cal.date(byAdding: .day, value: -weekday, to: today)!
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: monday)! }
    }
}

/// Один день недели. Сегодня — карточка «Сейчас» и следующие пары,
/// другие дни — все пары дня.
struct DayPage: View {
    let day: Date
    let now: Date
    let lessons: [LessonItem]
    let receivedAt: Date?

    var body: some View {
        let cal = Calendar.current
        let isToday = cal.isDate(day, inSameDayAs: now)
        let dayLessons = lessons.filter { cal.isDate($0.start, inSameDayAs: day) }
        List {
            Text(subtitle(dayLessons))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
            if isToday {
                let state = LessonState(lessons: lessons, now: now)
                Section { NowCard(state: state, now: now) }
                // Пара из карточки «Сейчас» в списке не повторяется.
                let inCard = state.current ?? state.next
                let upcoming = dayLessons.filter { $0.start > now && $0 != inCard }
                if !upcoming.isEmpty {
                    Section("Дальше") {
                        ForEach(upcoming, id: \.self) { LessonRowView(lesson: $0, now: now) }
                    }
                }
            } else if dayLessons.isEmpty {
                Text("Пар нет").foregroundStyle(.secondary)
            } else {
                ForEach(dayLessons, id: \.self) { LessonRowView(lesson: $0, now: now) }
            }
            if isToday, let at = receivedAt {
                Text("Получено с iPhone \(dayLabel(at, from: Date()).lowercased()) в \(hm(at))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(title)
    }

    private var title: String {
        let cal = Calendar.current
        if cal.isDate(day, inSameDayAs: now) { return "Сегодня" }
        if let d = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(day, inSameDayAs: d) { return "Завтра" }
        if let d = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(day, inSameDayAs: d) { return "Вчера" }
        return upperFirst(format("EEEE"))
    }

    /// «Вторник, 13 октября · 3 пары».
    private func subtitle(_ dayLessons: [LessonItem]) -> String {
        let n = dayLessons.filter { !$0.cancelled }.count
        let date = upperFirst(format("EEEE, d MMMM"))
        return n == 0 ? date : "\(date) · \(n) \(pairs(n))"
    }

    private func format(_ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = pattern
        return f.string(from: day)
    }

    private func upperFirst(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    private func pairs(_ n: Int) -> String {
        let m10 = n % 10, m100 = n % 100
        if m10 == 1 && m100 != 11 { return "пара" }
        if (2...4).contains(m10) && !(12...14).contains(m100) { return "пары" }
        return "пар"
    }
}

struct NowCard: View {
    let state: LessonState
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let current = state.current {
                caption("СЕЙЧАС", "ещё \(durationLabel(current.end.timeIntervalSince(now)))")
                Text(current.t).font(.headline).lineLimit(2)
                Text(current.r).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                ThinProgress(value: now.timeIntervalSince(current.start)
                    / current.end.timeIntervalSince(current.start))
                    .padding(.top, 4)
            } else if let next = state.next, Calendar.current.isDate(next.start, inSameDayAs: now) {
                let wait = next.start.timeIntervalSince(now)
                caption("ДАЛЕЕ", wait < 7200 ? "через \(durationLabel(wait))" : "в \(hm(next.start))")
                Text(next.t).font(.headline).lineLimit(2)
                Text("\(hm(next.start)) · \(next.r)").font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            } else {
                caption(state.today.isEmpty ? "СЕГОДНЯ ПАР НЕТ" : "ПАРЫ ЗАКОНЧИЛИСЬ", nil)
                if let next = state.next {
                    Text("Следующая \(dayLabel(next.start, from: now).lowercased()) в \(hm(next.start))")
                        .font(.headline)
                    Text(next.t).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    Text("Отдыхай").font(.headline)
                }
            }
        }
    }

    private func caption(_ title: String, _ trailing: String?) -> some View {
        HStack {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(watchAccent)
            Spacer()
            if let trailing { Text(trailing).font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

/// Тонкая полоса прогресса, как в карточке «Сейчас» на iPhone.
struct ThinProgress: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(watchAccent).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 4)
    }
}

struct LessonRowView: View {
    let lesson: LessonItem
    let now: Date

    var body: some View {
        let ongoing = !lesson.cancelled && lesson.start <= now && now < lesson.end
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(kindColor(lesson.k))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(lesson.t)
                    .font(.system(size: 15, weight: ongoing ? .semibold : .regular))
                    .strikethrough(lesson.cancelled)
                    .lineLimit(2)
                Text("\(hm(lesson.start)) · \(lesson.cancelled ? "отменена" : lesson.r)")
                    .font(.footnote)
                    .foregroundStyle(ongoing ? watchAccent : .secondary)
                    .lineLimit(1)
            }
        }
        .opacity(lesson.end <= now || lesson.cancelled ? 0.45 : 1)
    }
}
