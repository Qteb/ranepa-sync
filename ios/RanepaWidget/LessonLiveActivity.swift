import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity: экран блокировки и Dynamic Island.
@available(iOS 16.2, *)
struct LessonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LessonActivityAttributes.self) { context in
            let phase = Phase(context.state, stale: context.isStale)
            LockScreenView(phase: phase)
                .padding(14)
                .widgetURL(phase.lesson?.url)
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
                            CaptionLabel(phase: phase)
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
                            if let next = phase.after { NextLine(next: next, withRoom: false) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                if let lesson = phase.lesson {
                    HStack(spacing: 5) {
                        KindIcon(kind: lesson.kind, size: 14)
                        // Дистанционно — камера вместо номера аудитории.
                        if lesson.room == "Дистанционно" {
                            Image(systemName: "video.fill").font(.system(size: 13))
                        } else {
                            Text(lesson.compactRoom).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        }
                    }
                }
            } compactTrailing: {
                CountdownText(phase: phase)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(liveAccent)
                    .frame(maxWidth: 64)
            } minimal: {
                if let lesson = phase.lesson {
                    KindIcon(kind: lesson.kind, size: 15)
                } else {
                    Image(systemName: "calendar").foregroundStyle(liveAccent)
                }
            }
            .widgetURL(phase.lesson?.url)
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

/// «СЕЙЧАС · СЕМИНАР» с иконкой типа.
@available(iOS 16.2, *)
private struct CaptionLabel: View {
    let phase: Phase

    var body: some View {
        HStack(spacing: 5) {
            if let lesson = phase.lesson { KindIcon(kind: lesson.kind, size: 13) }
            Text(phase.caption)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(liveAccent)
                .lineLimit(1)
        }
    }
}

/// «Дальше 12:20 · 🏃 Физкультура».
@available(iOS 16.2, *)
private struct NextLine: View {
    let next: LessonActivityAttributes.Lesson
    let withRoom: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("Дальше \(hm(next.start)) ·")
            KindIcon(kind: next.kind, size: 11)
            Text(withRoom ? "\(next.title) · \(next.room)" : next.title)
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .lineLimit(1)
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
                CaptionLabel(phase: phase)
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
                // Тип уже в иконке у подписи — полоска не нужна.
                VStack(alignment: .leading, spacing: 1) {
                    Text(lesson.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text("\(hm(lesson.start))–\(hm(lesson.end)) · \(lesson.room)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ProgressBar(phase: phase).padding(.top, 4)
                if let next = phase.after {
                    NextLine(next: next, withRoom: true).padding(.top, 2)
                }
            } else {
                Text("На сегодня всё").font(.system(size: 16, weight: .semibold))
            }
        }
        .foregroundStyle(.white)
    }
}
