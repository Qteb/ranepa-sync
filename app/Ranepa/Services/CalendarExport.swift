import CoreLocation
import EventKit
import UIKit

/// Отдельный календарь «РАНХиГС» на телефоне. Он принадлежит только
/// приложению, поэтому проще всего удалить события в диапазоне и создать заново.
enum CalendarExport {
    static let name = "РАНХиГС"
    private static let store = EKEventStore()

    /// Пересобирает календарь за [from]..[to]. Возвращает текст ошибки или nil.
    static func export(_ lessons: [Lesson], from: Date, to: Date, reminderMinutes: Int) async -> String? {
        do {
            guard try await store.requestFullAccessToEvents() else {
                return "Нет доступа к календарю: разреши его в настройках телефона"
            }
            let calendar = try ownCalendar()
            let existing = store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: [calendar]))
            for event in existing { try store.remove(event, span: .thisEvent, commit: false) }
            for l in lessons where !l.cancelled && l.start >= from && l.start < to {
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                event.title = l.title
                event.startDate = l.start
                event.endDate = l.end
                if let place = await place(for: l) {
                    event.structuredLocation = place
                } else {
                    event.location = l.location
                }
                event.notes = l.details
                if reminderMinutes > 0 { event.addAlarm(EKAlarm(relativeOffset: -Double(reminderMinutes) * 60)) }
                try store.save(event, span: .thisEvent, commit: false)
            }
            try store.commit()
            return nil
        } catch {
            return "Не удалось выгрузить в календарь: \(error.localizedDescription)"
        }
    }

    /// Место события с точкой корпуса: Календарь покажет карту и откроет
    /// нужное здание, а не будет сам угадывать по тексту адреса.
    /// «1 - 2317, корпус 1, проспект Вернадского, 84».
    private static func place(for l: Lesson) async -> EKStructuredLocation? {
        guard !l.isRemote, let address = Places.address(from: l.room),
              let c = await Places.locate(address) else { return nil }
        let place = EKStructuredLocation(title: "\(l.shortLocation) · \(Places.query(for: address).replacingOccurrences(of: "Москва, ", with: ""))")
        place.geoLocation = CLLocation(latitude: c.latitude, longitude: c.longitude)
        // Радиус — чтобы карта в Календаре открывалась на здании, а не на районе.
        place.radius = 60
        return place
    }

    private static func ownCalendar() throws -> EKCalendar {
        if let found = store.calendars(for: .event).first(where: { $0.title == name }) { return found }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = name
        calendar.cgColor = UIColor(red: 0x8E / 255, green: 0x1B / 255, blue: 0x2E / 255, alpha: 1).cgColor
        calendar.source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .local }
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    static func remove() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        for c in store.calendars(for: .event) where c.title == name {
            try? store.removeCalendar(c, commit: true)
        }
    }
}
