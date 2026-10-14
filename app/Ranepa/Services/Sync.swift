import UIKit

/// Полная загрузка: месяц вперёд, то есть текущая неделя и ещё 4.
/// Делается при входе и первым обновлением за день.
let fetchWeeks = 5

/// Напоминание о паре по умолчанию, пока пользователь не выбрал своё.
let defaultReminderMinutes = 15

enum SyncTrigger {
    case background, open, manual
    /// Кнопка в отладке: без проверок интервалов и тихих часов.
    case debug
}

enum SkipReason {
    /// Обновление выключено удалённым конфигом.
    case paused
    /// Пауза после ошибки сервера.
    case backoff
    /// Ночь — фон не ходит в ЛК.
    case quietHours
    /// С прошлого обновления прошло слишком мало времени.
    case tooSoon
    /// Обновлять нечего: воскресенье, каникулы или данные свежие.
    case notNeeded
}

struct SyncResult {
    /// Изменения в ближайшие дни по сравнению с прошлой загрузкой.
    var changes: [String] = []
    var sideEffectError: String?
    /// Почему в ЛК не ходили; nil — обновление было.
    var skipped: SkipReason?
}

/// Когда и сколько загружать из ЛК.
enum Sync {
    /// Данные старше этого обновляются при открытии приложения.
    static let staleAfter: TimeInterval = 4 * 3600
    /// При открытии не пытаемся чаще, даже если прошлая попытка не удалась.
    private static let openRetryAfter: TimeInterval = 15 * 60
    /// Ночью фон в ЛК не ходит.
    private static let quietUntilHour = 7
    /// Допуск к интервалу фона: система запускает задачу с разбросом.
    private static let intervalSlack: TimeInterval = 15 * 60
    /// Пауза после ответа 429/5xx: 8 → 16 → 24 часа.
    private static let backoffBase: TimeInterval = 4 * 3600
    private static let backoffMax: TimeInterval = 24 * 3600
    /// Фото весит под мегабайт — качаем его при входе и потом раз в неделю.
    private static let photoMaxAge: TimeInterval = 7 * 24 * 3600

    private static func since(_ d: UserDefaults, _ key: String, _ now: Date) -> TimeInterval {
        d.time(key).map { now.timeIntervalSince($0) } ?? 365 * 24 * 3600
    }

    /// Обновление стоит на паузе: выключено конфигом или после ошибки сервера.
    static func paused(_ d: UserDefaults = .standard) -> Bool {
        !RemoteConfig.cached(d).sync || (d.time(Keys.backoffUntil).map { $0 > Clock.now } ?? false)
    }

    /// Почему не надо идти в ЛК, или nil — надо. Отдельно от загрузки, чтобы
    /// проверять правила тестами.
    static func skipReason(_ d: UserDefaults, _ trigger: SyncTrigger, config: RemoteConfig, now: Date) -> SkipReason? {
        if !config.sync { return .paused }
        if let until = d.time(Keys.backoffUntil), until > now { return .backoff }
        let full = isFullDue(d, now: now)
        switch trigger {
        case .background:
            if now.hour < quietUntilHour { return .quietHours }
            if since(d, Keys.lastAttemptAt, now) < config.minInterval - intervalSlack { return .tooSoon }
            // В воскресенье и на каникулах — только ежедневная полная загрузка.
            if !full && (now.isoWeekday == 7 || !lessonsSoon(d, now)) { return .notNeeded }
        case .open:
            if since(d, Keys.fetchedAt, now) < staleAfter || since(d, Keys.lastAttemptAt, now) < openRetryAfter {
                return .notNeeded
            }
        case .manual:
            if since(d, Keys.fetchedAt, now) < config.manualCooldown { return .tooSoon }
        case .debug:
            break
        }
        return nil
    }

    /// Первое обновление за день — полное.
    static func isFullDue(_ d: UserDefaults, now: Date) -> Bool {
        guard let last = d.time(Keys.lastFullAt) else { return true }
        return !last.sameDay(now)
    }

    /// Решает, идти ли в ЛК и сколько грузить, и загружает расписание через
    /// невидимый WebView. Месяц — первым обновлением за день, иначе текущую
    /// неделю (с пятницы — и следующую).
    @MainActor
    static func run(_ trigger: SyncTrigger, _ d: UserDefaults = .standard) async throws -> SyncResult {
        if d.bool(forKey: Keys.demo) { return await Demo.sync(trigger, d) }
        let config = await RemoteConfig.load(d)
        let now = Clock.now
        if let reason = skipReason(d, trigger, config: config, now: now) { return SyncResult(skipped: reason) }

        let full = isFullDue(d, now: now)
        d.setTime(now, Keys.lastAttemptAt)
        let monday = now.monday
        let weeks = full ? fetchWeeks : (now.isoWeekday >= 5 ? 2 : 1)
        let result: FetchResult
        do {
            result = try await LKWebView.refresh(monday: monday, weeks: weeks, withProfile: full,
                                                 withPhoto: full && photoStale(d))
        } catch LKError.serverBusy(let status, let retryAfter) {
            startBackoff(d, retryAfter: retryAfter)
            throw LKError.serverBusy(status: status, retryAfter: retryAfter)
        }
        d.removeObject(forKey: Keys.backoffUntil)
        d.removeObject(forKey: Keys.backoffFailures)
        return await save(result, monday: monday, weeks: weeks, d)
    }

    /// Есть ли пары в ближайшие 14 дней — если нет, это каникулы.
    private static func lessonsSoon(_ d: UserDefaults, _ now: Date) -> Bool {
        let until = now.adding(days: 14)
        return cachedLessons(d).contains { $0.end > now && $0.start < until }
    }

    private static func startBackoff(_ d: UserDefaults, retryAfter: Int?) {
        let failures = d.integer(forKey: Keys.backoffFailures) + 1
        var pause = min(backoffBase * Double(1 << failures), backoffMax)
        pause = max(pause, Double(retryAfter ?? 0))
        d.set(failures, forKey: Keys.backoffFailures)
        d.setTime(Clock.now.addingTimeInterval(pause), Keys.backoffUntil)
    }

    private static func photoStale(_ d: UserDefaults) -> Bool {
        d.time(Keys.photoFetchedAt).map { Clock.now.timeIntervalSince($0) > photoMaxAge } ?? true
    }

    /// data:image/png;base64,… → PNG 256×256 в base64 (несколько десятков КБ).
    private static func shrinkPhoto(_ dataURL: String) -> String? {
        guard let comma = dataURL.firstIndex(of: ",") else { return nil }
        // Сайт режет base64 переносами строк каждые 64 символа.
        let base64 = dataURL[dataURL.index(after: comma)...].filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: String(base64)), let image = UIImage(data: data) else { return nil }
        let side: CGFloat = 256
        let scale = side / min(image.size.width, image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let png = UIGraphicsImageRenderer(size: size, format: format).pngData { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return png.base64EncodedString()
    }

    /// Сохраняет загруженное расписание, сравнивает с прошлым и обновляет
    /// напоминания, виджет и календарь. Полная загрузка заменяет всё
    /// расписание, лёгкая — только загруженные недели.
    @MainActor
    static func save(_ result: FetchResult, monday: Date, weeks: Int = fetchWeeks,
                     _ d: UserDefaults = .standard) async -> SyncResult {
        let full = weeks >= fetchWeeks
        let hadCache = d.object(forKey: Keys.days) != nil
        let before = cachedLessons(d)
        let days = full ? result.days : merge(d, fresh: result.days, monday: monday, weeks: weeks)
        let after = parseLessons(days)

        saveDays(days, d)
        if let group = result.group { d.set(group, forKey: Keys.group) }
        if let program = result.program { d.set(program, forKey: Keys.program) }
        if let name = result.fullName, !name.isEmpty { d.set(name, forKey: Keys.fullName) }
        if let photo = result.photo {
            // Битое фото — останутся инициалы, попробуем в следующий раз.
            if let small = photo.isEmpty ? nil : shrinkPhoto(photo) {
                d.set(small, forKey: Keys.photo)
            } else {
                d.removeObject(forKey: Keys.photo)
            }
            d.setTime(Clock.now, Keys.photoFetchedAt)
        }
        d.setTime(Clock.now, Keys.fetchedAt)
        if let until = result.sessionUntil { d.setTime(until, Keys.sessionUntil) }
        if full {
            d.setTime(monday, Keys.rangeStart)
            d.setTime(Clock.now, Keys.lastFullAt)
        }
        d.set(true, forKey: Keys.loggedIn)
        d.removeObject(forKey: Keys.sessionExpiredNotified)

        return SyncResult(changes: hadCache ? describeChanges(before: before, after: after, now: Clock.now) : [],
                          sideEffectError: await applySideEffects(after, d))
    }

    /// Сохранённые дни вне загруженных недель + свежие дни.
    private static func merge(_ d: UserDefaults, fresh: [Any], monday: Date, weeks: Int) -> [Any] {
        let end = monday.adding(days: 7 * weeks)
        // Дата дня — без зоны, сравниваем как местную, как и раньше.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let kept = cachedDays(d).filter { day in
            let raw = "\((day as? [String: Any])?["date"] ?? "")"
            guard let date = f.date(from: String(raw.prefix(19))) else { return true }
            return date < monday || date >= end
        }
        return kept + fresh
    }

    /// Напоминания, виджет, Live Activity и календарь строятся из расписания.
    /// Возвращает текст ошибки или nil.
    @MainActor
    static func applySideEffects(_ lessons: [Lesson], _ d: UserDefaults = .standard) async -> String? {
        let minutes = d.object(forKey: Keys.reminderMinutes) == nil
            ? defaultReminderMinutes : d.integer(forKey: Keys.reminderMinutes)
        await Notifications.scheduleReminders(lessons, minutes: minutes)
        // В демо сессии ЛК нет — напоминать о ней незачем.
        if let fetchedAt = d.time(Keys.fetchedAt), !d.bool(forKey: Keys.demo) {
            await Notifications.scheduleKeepAlive(lastSync: fetchedAt, sessionUntil: d.time(Keys.sessionUntil))
        }
        Outputs.update(lessons)
        await LiveActivities.update(lessons, enabled: d.bool(Keys.liveActivity, default: true))
        guard d.bool(forKey: Keys.calendarExport) else { return nil }
        let from = d.time(Keys.rangeStart) ?? Clock.now.monday
        return await CalendarExport.export(lessons, from: from, to: from.adding(days: 7 * fetchWeeks),
                                           reminderMinutes: minutes)
    }
}
