import MapKit
import UIKit

/// Где проходит пара: адрес из строки аудитории ЛК и точка на карте.
/// «1 - 2262 (24) П+ПК Блок 2F (Вернадского, 84 - корпус 1)» →
/// «Москва, проспект Вернадского, 84, корпус 1».
enum Places {
    /// Адрес в последних скобках строки аудитории.
    static func address(from room: String) -> String? {
        guard let open = room.range(of: "(", options: .backwards),
              let close = room.range(of: ")", options: .backwards), open.upperBound < close.lowerBound
        else { return nil }
        let raw = room[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)
        // В скобках бывает и вместимость: «(24)».
        guard raw.contains(where: \.isLetter) else { return nil }
        return raw.replacingOccurrences(of: " - ", with: ", ")
    }

    /// «Вернадского, 84, корпус 1» — для подписи и копирования.
    static func query(for address: String) -> String {
        var a = address
        if a.hasPrefix("Вернадского") { a = "проспект " + a }
        return "Москва, " + a
    }

    private static let cacheKey = "places"

    /// Точка корпуса: из кэша или геокодером Apple. nil — не нашлось.
    static func locate(_ address: String) async -> CLLocationCoordinate2D? {
        let d = UserDefaults.standard
        var cache = d.dictionary(forKey: cacheKey) as? [String: [Double]] ?? [:]
        if let c = cache[address], c.count == 2 {
            return CLLocationCoordinate2D(latitude: c[0], longitude: c[1])
        }
        guard let request = MKGeocodingRequest(addressString: query(for: address)),
              let item = try? await request.mapItems.first else { return nil }
        let c = item.location.coordinate
        cache[address] = [c.latitude, c.longitude]
        d.set(cache, forKey: cacheKey)
        return c
    }
}

/// Приложения карт, которые умеют открываться на точке.
enum MapApp: String, CaseIterable, Identifiable {
    case apple, yandex, dgis, google

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "Карты"
        case .yandex: "Яндекс Карты"
        case .dgis: "2ГИС"
        case .google: "Google Maps"
        }
    }

    /// Схема для проверки, установлено ли приложение (LSApplicationQueriesSchemes).
    private var scheme: String? {
        switch self {
        case .apple: nil
        case .yandex: "yandexmaps"
        case .dgis: "dgis"
        case .google: "comgooglemaps"
        }
    }

    @MainActor var installed: Bool {
        guard let scheme else { return true }
        return UIApplication.shared.canOpenURL(URL(string: "\(scheme)://")!)
    }

    @MainActor static var installedApps: [MapApp] { allCases.filter(\.installed) }

    func url(_ c: CLLocationCoordinate2D, name: String) -> URL {
        let lat = c.latitude, lon = c.longitude
        let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return switch self {
        case .apple: URL(string: "maps://?ll=\(lat),\(lon)&q=\(q)")!
        case .yandex: URL(string: "yandexmaps://maps.yandex.ru/?pt=\(lon),\(lat)&z=17&l=map")!
        case .dgis: URL(string: "dgis://2gis.ru/geo/\(lon),\(lat)")!
        case .google: URL(string: "comgooglemaps://?q=\(lat),\(lon)&center=\(lat),\(lon)&zoom=17")!
        }
    }

    /// Поиск по адресу — если точку найти не удалось.
    func url(search address: String) -> URL {
        let q = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return switch self {
        case .apple: URL(string: "maps://?q=\(q)")!
        case .yandex: URL(string: "yandexmaps://maps.yandex.ru/?text=\(q)")!
        case .dgis: URL(string: "dgis://2gis.ru/search/\(q)")!
        case .google: URL(string: "comgooglemaps://?q=\(q)")!
        }
    }

    /// Выбранное в настройках приложение; nil — спрашивать каждый раз.
    @MainActor static var preferred: MapApp? {
        get {
            let app = UserDefaults.standard.string(forKey: "mapApp").flatMap(MapApp.init(rawValue:))
            return app?.installed == true ? app : nil
        }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: "mapApp") }
    }
}
