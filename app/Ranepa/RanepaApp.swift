import SwiftUI
import TipKit
import UserNotifications

@main
struct RanepaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState()

    init() {
        WatchSync.shared.activate()
        if Clock.screenshotMode || Clock.recordingMode { Tips.hideAllTipsForTesting() }
        try? Tips.configure()
        // Подсказки, закрытые во Flutter-версии, не показываем снова.
        let d = UserDefaults.standard
        d.migrateFromFlutter()
        if d.bool(forKey: "tip.refresh") { RefreshTip().invalidate(reason: .actionPerformed) }
        if d.bool(forKey: "tip.account") { AccountTip().invalidate(reason: .actionPerformed) }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if state.loggedIn {
                    HomeView()
                } else {
                    AuthFlow()
                }
            }
            .environment(state)
            .preferredColorScheme(state.colorScheme)
            .animation(.default, value: state.loggedIn)
            .onAppear {
                delegate.state = state
                // Задача могла не зарегистрироваться (обновление со старой версии).
                if state.loggedIn && !state.demo { Background.schedule() }
            }
            // ranepa://lesson?start=<секунды по настоящим часам> — из Live
            // Activity и виджета.
            .onOpenURL { url in
                guard url.host == "lesson",
                      let start = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                          .queryItems?.first(where: { $0.name == "start" })?.value.flatMap(Double.init)
                else { return }
                state.pendingLesson = Date(timeIntervalSince1970: start).addingTimeInterval(Clock.shift)
            }
        }
        .backgroundTask(.appRefresh(Background.taskID)) {
            await Background.run()
        }
    }
}

/// Уведомления: показывать и в открытом приложении, по нажатию — открыть пару.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor var state: AppState?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let start = Notifications.lessonStart(response.notification.request.content.userInfo) else { return }
        // При холодном старте состояние ещё не создано — ждём его.
        Task { @MainActor in
            while state == nil { try? await Task.sleep(for: .milliseconds(50)) }
            state?.pendingLesson = start
        }
    }
}
