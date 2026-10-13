import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity: экран блокировки и Dynamic Island.
@available(iOS 16.2, *)
struct LessonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LessonActivityAttributes.self) { context in
            LockScreenView(phase: Phase(context.state, stale: context.isStale))
                .padding(14)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let phase = Phase(context.state, stale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    // Всё в нижней области: по краям «остров» скруглён
                    // и обрезает подписи в боковых.
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(phase.caption)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(liveAccent)
                                .lineLimit(1)
                            Spacer()
                            CountdownText(phase: phase).font(.system(size: 17, weight: .semibold))
                        }
                        if let lesson = phase.lesson {
                            Text(lesson.title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                            Text("\(hm(lesson.start))–\(hm(lesson.end)) · \(lesson.fullRoom)")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            ProgressBar(phase: phase).padding(.vertical, 4)
                            if let next = phase.after {
                                Text("Дальше \(hm(next.start)) · \(next.title)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                if let lesson = phase.lesson {
                    HStack(spacing: 4) {
                        Circle().fill(kindColor(lesson.kind)).frame(width: 8, height: 8)
                        Text(lesson.compactRoom).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    }
                }
            } compactTrailing: {
                CountdownText(phase: phase)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(liveAccent)
                    .frame(maxWidth: 64)
            } minimal: {
                if let lesson = phase.lesson, phase.ongoing {
                    ProgressView(timerInterval: lesson.start...lesson.end, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.circular)
                    .tint(liveAccent)
                } else {
                    Image(systemName: "calendar").foregroundStyle(liveAccent)
                }
            }
        }
    }
}

private let liveAccent = Color(red: 0.90, green: 0.45, blue: 0.50)

/// Что показывать сейчас. Активность устаревает к концу идущей пары или
/// к началу ближайшей; если приложение не успело её обновить, следующий
/// шаг выводится отсюда.
@available(iOS 16.2, *)
private struct Phase {
    typealias Lesson = LessonActivityAttributes.Lesson

    /// Пара, о которой карточка: идущая или ближайшая.
    let lesson: Lesson?
    /// Идёт ли она.
    let ongoing: Bool
    /// Следующая после неё.
    let after: Lesson?

    init(_ state: LessonActivityAttributes.ContentState, stale: Bool) {
        switch (state.isCurrent, stale) {
        case (true, false):  // идёт пара
            lesson = state.lesson; ongoing = true; after = state.next
        case (true, true):   // пара закончилась — перемена или конец дня
            lesson = state.next; ongoing = false; after = nil
        case (false, false): // перемена до ближайшей
            lesson = state.lesson; ongoing = false; after = state.next
        case (false, true):  // ближайшая началась
            lesson = state.lesson; ongoing = true; after = state.next
        }
    }

    var caption: String {
        guard let lesson else { return "ПАРЫ ЗАКОНЧИЛИСЬ" }
        let kind = lesson.kind.isEmpty ? "" : " · \(lesson.kind.uppercased())"
        return (ongoing ? "СЕЙЧАС" : "ДАЛЕЕ") + kind
    }
}

/// До конца идущей пары или до начала ближайшей. Идёт сам, без обновлений.
@available(iOS 16.2, *)
private struct CountdownText: View {
    let phase: Phase

    var body: some View {
        if let lesson = phase.lesson {
            if phase.ongoing {
                Text(timerInterval: lesson.start...lesson.end, countsDown: true)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            } else {
                Text(lesson.start, style: .timer)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
        } else {
            Text("")
        }
    }
}

@available(iOS 16.2, *)
private struct ProgressBar: View {
    let phase: Phase

    var body: some View {
        if let lesson = phase.lesson, phase.ongoing {
            ProgressView(timerInterval: lesson.start...lesson.end, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(liveAccent)
        }
    }
}

@available(iOS 16.2, *)
private struct LockScreenView: View {
    let phase: Phase

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(phase.caption)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(liveAccent)
                Spacer()
                if !phase.ongoing, phase.lesson != nil {
                    Text("через ").font(.system(size: 15)).foregroundStyle(.secondary)
                        + Text(phase.lesson!.start, style: .timer)
                        .font(.system(size: 20, weight: .semibold))
                } else {
                    CountdownText(phase: phase).font(.system(size: 20, weight: .semibold))
                }
            }
            if let lesson = phase.lesson {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5).fill(kindColor(lesson.kind)).frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(lesson.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        Text("\(hm(lesson.start))–\(hm(lesson.end)) · \(lesson.room)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                ProgressBar(phase: phase).padding(.top, 4)
                if let next = phase.after {
                    Text("Дальше \(hm(next.start)) · \(next.title) · \(next.room)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            } else {
                Text("На сегодня всё").font(.system(size: 16, weight: .semibold))
            }
        }
        .foregroundStyle(.white)
    }
}
