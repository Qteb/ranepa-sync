import ActivityKit
import Foundation

/// Live Activity с идущей или ближайшей парой. Запускает приложение
/// (ios/Runner/LiveActivityBridge.swift), показывает расширение виджета.
@available(iOS 16.2, *)
struct LessonActivityAttributes: ActivityAttributes {
    struct Lesson: Codable, Hashable {
        let title: String
        let kind: String
        /// «1 - 2317».
        let room: String
        /// Полный адрес аудитории для развёрнутого вида.
        let fullRoom: String
        let start: Date
        let end: Date

        /// Для свёрнутого Dynamic Island: «1 - 2317» → «2317».
        var compactRoom: String {
            if room == "Дистанционно" { return "СДО" }
            if let dash = room.range(of: " - ", options: .backwards) {
                return String(room[dash.upperBound...])
            }
            return room
        }
    }

    struct ContentState: Codable, Hashable {
        /// Идущая пара или ближайшая, если сейчас перемена.
        let lesson: Lesson
        /// Следующая после неё сегодня.
        let next: Lesson?
        /// lesson уже идёт. Активность устаревает к концу идущей пары или
        /// к началу ближайшей — по isCurrent расширение понимает, что
        /// показать после этого, если приложение не успело обновить её.
        let isCurrent: Bool
    }
}
