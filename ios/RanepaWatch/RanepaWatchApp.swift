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
            TodayView().environmentObject(store)
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

struct TodayView: View {
    @EnvironmentObject var store: LessonStore

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                let now = context.date.addingTimeInterval(clockShift())
                let state = LessonState(lessons: store.lessons, now: now)
                List {
                    if store.lessons.isEmpty {
                        Text("Открой «Расписание» на iPhone — пары появятся здесь.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Section {
                            NowCard(state: state, now: now)
                        }
                        // Пара из карточки «Сейчас» в списке не повторяется.
                        let inCard = state.current ?? state.next
                        let upcoming = state.today.filter { $0.start > now && $0 != inCard }
                        Section {
                            ForEach(upcoming, id: \.self) { lesson in
                                LessonRowView(lesson: lesson, now: now)
                            }
                        } header: {
                            if !upcoming.isEmpty { Text("Дальше") }
                        } footer: {
                            if let at = store.receivedAt {
                                Text("Получено с iPhone \(dayLabel(at, from: Date()).lowercased()) в \(hm(at))")
                            }
                        }
                    }
                }
                .navigationTitle("Сегодня")
            }
        }
        .tint(watchAccent)
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
        let ongoing = lesson.start <= now && now < lesson.end
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(kindColor(lesson.k))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(lesson.t)
                    .font(.system(size: 15, weight: ongoing ? .semibold : .regular))
                    .lineLimit(2)
                Text("\(hm(lesson.start)) · \(lesson.r)")
                    .font(.footnote)
                    .foregroundStyle(ongoing ? watchAccent : .secondary)
                    .lineLimit(1)
            }
        }
        .opacity(lesson.end <= now ? 0.45 : 1)
    }
}
