import BackgroundTasks
import Observation
import SwiftUI
import TipKit

/// Состояние приложения: расписание из кэша, настройки и действия с ними.
@MainActor
@Observable
final class AppState {
    private let d = UserDefaults.standard

    var lessons: [Lesson] = []
    var fetchedAt: Date?
    var rangeStart: Date?
    var loading = false
    var error: String?
    /// Изменения, найденные последним ручным обновлением: главный экран
    /// показывает их баннером и сбрасывает.
    var pendingChanges: [String] = []
    /// Разрешены ли уведомления в настройках телефона; nil — ещё не знаем.
    var notificationsEnabled: Bool?
    /// Нажали на напоминание, Live Activity или виджет: главный экран
    /// листает к дню пары и открывает её карточку.
    var pendingLesson: Date?

    /// Настройки и профиль. Хранятся в UserDefaults, здесь — копия для
    /// интерфейса.
    var loggedIn = false
    var demo = false
    var reminderMinutes = defaultReminderMinutes
    var calendarExport = false
    var liveActivity = true
    var themeMode = 0
    var fullName: String?
    var group: String?
    var program: String?
    var photo: UIImage?

    init() {
        d.migrateFromFlutter()
        loadCache()
    }

    var lastBackgroundRun: Date? { d.time(Keys.lastBackgroundRun) }
    var lastBackgroundResult: String? { d.string(forKey: Keys.lastBackgroundResult) }
    /// Обновление остановлено конфигом или стоит на паузе после ошибки ЛК.
    var syncPaused: Bool { Sync.paused(d) }
    var pausedMessage: String? { RemoteConfig.cached(d).message }

    var colorScheme: ColorScheme? { themeMode == 1 ? .light : themeMode == 2 ? .dark : nil }

    /// Первый день загруженного диапазона — понедельник текущей недели.
    var firstDay: Date { Clock.now.monday }
    var dayCount: Int { fetchWeeks * 7 }

    func lessons(on day: Date) -> [Lesson] { lessons.filter { $0.start.sameDay(day) } }

    /// Ближайшая пара после [after] (не отменённая).
    func next(after: Date) -> Lesson? { lessons.first { !$0.cancelled && $0.start > after } }

    func loadCache() {
        lessons = cachedLessons(d)
        fetchedAt = d.time(Keys.fetchedAt)
        rangeStart = d.time(Keys.rangeStart)
        loggedIn = d.bool(forKey: Keys.loggedIn)
        demo = d.bool(forKey: Keys.demo)
        reminderMinutes = d.object(forKey: Keys.reminderMinutes) == nil
            ? defaultReminderMinutes : d.integer(forKey: Keys.reminderMinutes)
        calendarExport = d.bool(forKey: Keys.calendarExport)
        liveActivity = d.bool(Keys.liveActivity, default: true)
        themeMode = d.integer(forKey: Keys.themeMode)
        fullName = d.string(forKey: Keys.fullName)
        group = d.string(forKey: Keys.group)
        program = d.string(forKey: Keys.program)
        photo = d.string(forKey: Keys.photo).flatMap { Data(base64Encoded: $0) }.flatMap(UIImage.init(data:))
        if !loggedIn && d.bool(forKey: Keys.sessionExpiredNotified) {
            error = "Сессия ЛК истекла, войди заново"
        }
    }

    /// Вызывается экраном входа, когда страница ЛК уже авторизована.
    func completeLogin(_ result: FetchResult, monday: Date) async {
        error = nil
        let sync = await Sync.save(result, monday: monday, d)
        loadCache()
        error = sync.sideEffectError
        if !demo { Background.schedule() }
        // Разрешение нужно и для уведомлений об изменениях, не только для напоминаний.
        await checkNotifications(request: true)
    }

    /// Вход в демо долгим нажатием на логотип стартового экрана.
    func startDemo() async {
        d.set(true, forKey: Keys.demo)
        await completeLogin(Demo.fetch(d), monday: Clock.now.monday)
    }

    /// Отладка: демо, где сегодня 4 пары по 4 минуты, первая — через
    /// 3 минуты. Напоминания — за 1 минуту.
    func startFastDay() async {
        if loggedIn { await logout() }
        d.setTime(Clock.now.addingTimeInterval(3 * 60), Keys.demoFastFrom)
        d.set(1, forKey: Keys.reminderMinutes)
        await startDemo()
        await showLiveActivity()
    }

    /// Перечитывает разрешение на уведомления. С [request] — показывает
    /// системный запрос, если ещё не спрашивали.
    func checkNotifications(request: Bool = false) async {
        let allowed = request ? await Notifications.request() : await Notifications.allowed()
        guard allowed != notificationsEnabled else { return }
        let wasOff = notificationsEnabled == false
        notificationsEnabled = allowed
        // Включили в настройках — сразу ставим напоминания заново.
        if allowed && wasOff && loggedIn { await resync() }
    }

    /// .open — при открытии, если данные устарели; .manual — жестом «потянуть вниз».
    func refresh(_ trigger: SyncTrigger = .manual) async {
        guard !loading, loggedIn else { return }
        loading = true
        error = nil
        defer {
            loadCache()
            loading = false
        }
        do {
            let sync = try await Sync.run(trigger, d)
            // Данные только что обновлялись — запрос не нужен, но жест должен
            // выглядеть как обычное обновление.
            if sync.skipped == .tooSoon { try? await Task.sleep(for: .milliseconds(500)) }
            pendingChanges = sync.changes
            error = sync.sideEffectError
            if sync.skipped == .paused && trigger == .manual { error = pausedMessage }
        } catch LKError.needLogin {
            d.set(false, forKey: Keys.loggedIn)
            Background.cancel()
            Notifications.cancelKeepAlive()
            error = LKError.needLogin.errorDescription
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Фоновая задача и расширения могли поменять данные, пока приложение
    /// было свёрнуто.
    func resumed() async {
        loadCache()
        await checkNotifications()
        await Notifications.removeStale()
        await showLiveActivity()
        await refresh(.open)
    }

    private func resync() async {
        error = await Sync.applySideEffects(lessons, d)
    }

    func setReminderMinutes(_ minutes: Int) async {
        if minutes > 0, !(await Notifications.request()) {
            error = "Разреши уведомления в настройках телефона"
            return
        }
        d.set(minutes, forKey: Keys.reminderMinutes)
        reminderMinutes = minutes
        await resync()
    }

    func setCalendarExport(_ enabled: Bool) async {
        d.set(enabled, forKey: Keys.calendarExport)
        calendarExport = enabled
        if enabled { await resync() } else { CalendarExport.remove() }
    }

    func setLiveActivity(_ enabled: Bool) async {
        d.set(enabled, forKey: Keys.liveActivity)
        liveActivity = enabled
        await LiveActivities.update(lessons, enabled: enabled)
    }

    /// При открытии приложения: запустить активность iOS разрешает только сейчас.
    func showLiveActivity() async {
        await LiveActivities.update(lessons, enabled: loggedIn && liveActivity)
    }

    func setThemeMode(_ mode: Int) {
        d.set(mode, forKey: Keys.themeMode)
        themeMode = mode
    }

    func logout() async {
        // Сессию WebView чистим до перехода на экран входа, иначе страница ЛК
        // подхватит старые токены и снова «войдёт».
        await LKWebView.logout()
        Background.cancel()
        Notifications.cancelAll()
        if calendarExport { CalendarExport.remove() }
        Outputs.update([])
        await LiveActivities.update([], enabled: false)
        for key in Keys.session { d.removeObject(forKey: key) }
        error = nil
        pendingChanges = []
        loadCache()
    }
}
