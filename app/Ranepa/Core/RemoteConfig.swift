import Foundation

/// Удалённый выключатель: файл в ветке `config` репозитория. Через него можно
/// остановить обращения к ЛК или сделать их реже без новой сборки.
/// jsDelivr — запасной адрес на случай, если GitHub недоступен.
struct RemoteConfig {
    private static let urls = [
        "https://raw.githubusercontent.com/Qteb/ranepa-sync/config/config.json",
        "https://cdn.jsdelivr.net/gh/Qteb/ranepa-sync@config/config.json",
    ]
    /// Конфиг проверяется не чаще раза в сутки.
    private static let maxAge: TimeInterval = 24 * 3600

    /// false — приложение не ходит в ЛК совсем, показывает сохранённое.
    var sync = true
    /// Минимальный интервал между фоновыми обновлениями.
    var minInterval: TimeInterval = 4 * 3600
    /// Ручное обновление чаще этого не делает запросов.
    var manualCooldown: TimeInterval = 2 * 60
    /// Пояснение для пользователя, когда обновление остановлено.
    var message: String?

    init() {}

    init(json: [String: Any]) {
        if let v = json["sync"] as? Bool { sync = v }
        if let h = json["minIntervalHours"] as? Double { minInterval = (h * 60).rounded() * 60 }
        if let m = json["manualCooldownMinutes"] as? Double { manualCooldown = (m * 60).rounded() }
        if let s = (json["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            message = s
        }
    }

    /// Сохранённый конфиг; без сети и до первой загрузки — значения по умолчанию.
    static func cached(_ d: UserDefaults = .standard) -> RemoteConfig {
        guard let raw = d.string(forKey: Keys.remoteConfig)?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
        else { return RemoteConfig() }
        return RemoteConfig(json: json)
    }

    /// Раз в сутки перечитывает конфиг. Если оба адреса недоступны, остаётся
    /// последний сохранённый.
    static func load(_ d: UserDefaults = .standard) async -> RemoteConfig {
        let fresh = d.time(Keys.remoteConfigCheckedAt).map { Date().timeIntervalSince($0) < maxAge } ?? false
        if !fresh {
            for url in urls {
                guard let raw = await download(url) else { continue }
                d.set(raw, forKey: Keys.remoteConfig)
                d.setTime(Date(), Keys.remoteConfigCheckedAt)
                break
            }
        }
        return cached(d)
    }

    private static func download(_ url: String) async -> String? {
        var request = URLRequest(url: URL(string: url)!)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              // Проверяем, что это наш JSON, а не страница-заглушка провайдера.
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
