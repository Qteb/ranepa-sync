import ActivityKit
import Foundation
import UIKit
import WatchConnectivity
import WidgetKit

/// Виджет, часы и Live Activity получают пары из приложения: сами в ЛК
/// они не ходят.
enum Outputs {
    private static func item(_ l: Lesson) -> LessonItem {
        LessonItem(s: l.start.timeIntervalSince1970, e: l.end.timeIntervalSince1970,
                   t: l.subject, k: l.kind, r: l.shortLocation, c: l.cancelled ? true : nil)
    }

    /// Для виджетов — ещё преподаватель, адрес и корпус в Картах: сами они
    /// не знают ни схемы кампуса, ни какие Карты установлены.
    @MainActor private static func widgetItem(_ l: Lesson) -> LessonItem {
        var item = item(l)
        item.l = l.lecturer.isEmpty ? nil : l.lecturer
        if !l.isRemote, let address = Places.address(from: l.room) {
            item.a = address
            let app = MapApp.preferred ?? .apple
            item.m = (Places.cachedLocation(address).map { app.url($0, name: l.mapTitle) }
                ?? app.url(search: Places.query(for: address))).absoluteString
        }
        return item
    }

    private static func json(_ items: [LessonItem]) -> String {
        (try? JSONEncoder().encode(items)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
    }

    /// Виджету — пары на две недели вперёд: какие показать «сейчас», он решает
    /// сам по часам. Часам — ещё прошедшие дни недели и отменённые пары: там
    /// можно листать неделю.
    @MainActor static func update(_ lessons: [Lesson]) {
        let now = Clock.now
        let horizon = now.adding(days: 14)
        // Отменённые тоже: виджет показывает их зачёркнутыми.
        let widget = lessons.filter { $0.end > now && $0.start < horizon }.map(widgetItem)
        let watch = lessons.filter { $0.start >= now.monday && $0.start < horizon }.map(item)
        let shared = UserDefaults(suiteName: appGroup)
        shared?.set(json(widget), forKey: SharedKeys.lessons)
        shared?.set(Clock.shift, forKey: SharedKeys.nowShift)
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        WatchSync.shared.send(lessons: json(watch))
    }
}

/// Передаёт пары на Apple Watch тем же контекстом, что и Flutter-версия.
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()
    private var pending: [String: Any]?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        if session.activationState != .activated { session.activate() }
    }

    func send(lessons: String) {
        send(["lessons": lessons, "nowShift": Clock.shift, "sentAt": Date().timeIntervalSince1970])
    }

    private func send(_ context: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            pending = context
            return activate()
        }
        guard session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(context)
        // Усложнение на циферблате: так часы обновят его сразу. У системы
        // на это дневной лимит.
        if session.isComplicationEnabled, session.remainingComplicationUserInfoTransfers > 0 {
            session.transferCurrentComplicationUserInfo(context)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard state == .activated, let context = pending else { return }
        pending = nil
        send(context)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    // Пользователь сменил часы — активируем сессию для новых.
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}

/// Пара на экране блокировки и в Dynamic Island. Запустить активность iOS
/// разрешает только из открытого приложения, обновлять и завершать — и из фона.
enum LiveActivities {
    static func update(_ lessons: [Lesson], enabled: Bool) async {
        typealias A = LessonActivityAttributes
        let now = Clock.now
        // Таймеры активности идут по настоящим часам — убираем сдвиг скриншотов.
        let items = enabled ? lessons.filter { !$0.cancelled && $0.start.sameDay(now) && $0.end > now } : []
        let real = items.map {
            A.Lesson(title: $0.subject, kind: $0.kind, room: $0.shortLocation, fullRoom: $0.location,
                     start: $0.start.addingTimeInterval(-Clock.shift), end: $0.end.addingTimeInterval(-Clock.shift))
        }
        let running = Activity<A>.activities
        guard let first = real.first else {
            for a in running { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let realNow = Date()
        let state = A.ContentState(lesson: first, next: real.dropFirst().first, isCurrent: first.start <= realNow)
        // Когда пара закончится, расширение покажет перемену или «пары
        // закончились», даже если приложение не успеет обновить активность.
        let content = ActivityContent(state: state, staleDate: first.start > realNow ? first.start : first.end)
        if let current = running.first {
            await current.update(content)
            for extra in running.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let active = await MainActor.run { UIApplication.shared.applicationState == .active }
        guard active, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        _ = try? Activity<A>.request(attributes: A(), content: content)
    }
}
