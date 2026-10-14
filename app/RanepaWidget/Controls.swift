import AppIntents
import SwiftUI
import WidgetKit

/// Ближайшая пара в корпусе: дистанционные пропускаем.
private func nextInBuilding() -> LessonItem? {
    let now = Date().addingTimeInterval(clockShift())
    return loadLessons().first { !$0.cancelled && $0.end > now && $0.m != nil }
}

struct OpenBuildingIntent: AppIntent {
    static let title: LocalizedStringResource = "Корпус следующей пары"
    static let description = IntentDescription("Открывает в Картах корпус следующей пары.")

    func perform() async throws -> some IntentResult & OpensIntent {
        // Ссылку на точку в выбранных Картах готовит приложение. Пар нет —
        // открываем расписание.
        let url = nextInBuilding()?.m.flatMap(URL.init(string:)) ?? URL(string: "ranepa://today")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct OpenTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Расписание на сегодня"
    static let description = IntentDescription("Открывает расписание на сегодняшнем дне.")

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "ranepa://today")!))
    }
}

/// Аудитория ближайшей пары — подпись под названием в Пункте управления.
struct NextRoomProvider: ControlValueProvider {
    let previewValue = "1 - 2317"

    func currentValue() async throws -> String {
        nextInBuilding()?.r ?? "Пар нет"
    }
}

struct BuildingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "BuildingControl", provider: NextRoomProvider()) { room in
            ControlWidgetButton(action: OpenBuildingIntent()) {
                Label {
                    Text("Корпус")
                    Text(room)
                } icon: {
                    Image(systemName: "map.fill")
                }
            }
        }
        .displayName("Корпус пары")
        .description("Открывает в Картах корпус следующей пары.")
    }
}

struct TodayControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TodayControl") {
            ControlWidgetButton(action: OpenTodayIntent()) {
                Label("Расписание", systemImage: "calendar.day.timeline.left")
            }
        }
        .displayName("Расписание")
        .description("Открывает расписание на сегодня.")
    }
}
