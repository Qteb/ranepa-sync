import BackgroundTasks
import Foundation

/// Фоновое обновление примерно раз в 4 часа: refresh-токен ЛК живёт сутки
/// и продлевается при каждом обновлении, так что сессия с запасом не
/// истекает. Время запуска выбирает система.
enum Background {
    /// Совпадает с BGTaskSchedulerPermittedIdentifiers в Info.plist.
    static let taskID = "com.qteb.ranepaTimetable.refresh"
    private static let period: TimeInterval = 4 * 3600

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: period)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
    }

    /// Запуск системой. Итог пишется в настройки — его видно в разделе «Отладка».
    @MainActor
    static func run(debug: Bool = false) async {
        let d = UserDefaults.standard
        guard d.bool(forKey: Keys.loggedIn), !d.bool(forKey: Keys.demo) else { return }
        // Следующий запуск — сразу: задача могла не успеть.
        schedule()
        let outcome: String
        do {
            let result = try await Sync.run(debug ? .debug : .background, d)
            await Notifications.showChanges(result.changes)
            outcome = switch result.skipped {
            case nil: result.changes.isEmpty ? "без изменений" : "изменений: \(result.changes.count)"
            case .paused: "обновление остановлено"
            case .backoff: "пауза после ошибки ЛК"
            case .quietHours: "ночь, пропущено"
            case .tooSoon: "рано, пропущено"
            case .notNeeded: "нет пар, пропущено"
            }
            // Пока обновление остановлено, напоминать об истекающей сессии незачем.
            if result.skipped == .paused { Notifications.cancelKeepAlive() }
        } catch LKError.needLogin {
            d.set(false, forKey: Keys.loggedIn)
            Notifications.cancelKeepAlive()
            if !d.bool(forKey: Keys.sessionExpiredNotified) {
                await Notifications.showSessionExpired()
                d.set(true, forKey: Keys.sessionExpiredNotified)
            }
            outcome = "сессия истекла"
        } catch {
            outcome = "ошибка: \(error.localizedDescription)"
        }
        d.setTime(Date(), Keys.lastBackgroundRun)
        d.set(outcome, forKey: Keys.lastBackgroundResult)
    }

    /// Отладка: сдвигает в кэше ближайшую будущую пару на час раньше, чтобы
    /// следующее обновление нашло «перенос» и прислало уведомление.
    static func debugShiftNextLesson() {
        var days = cachedDays()
        let now = Date()
        for (i, day) in days.enumerated() {
            guard var dayDict = day as? [String: Any], var discs = dayDict["discs"] as? [[String: Any]] else { continue }
            for (j, disc) in discs.enumerated() {
                guard let start = moscowDate("\(disc["start_date"] ?? "")"), start > now,
                      let end = moscowDate("\(disc["end_date"] ?? "")") else { continue }
                discs[j]["start_date"] = moscowStamp(start.addingTimeInterval(-3600))
                discs[j]["end_date"] = moscowStamp(end.addingTimeInterval(-3600))
                dayDict["discs"] = discs
                days[i] = dayDict
                return saveDays(days)
            }
        }
    }
}
