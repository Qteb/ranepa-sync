import Foundation

/// За сколько дней вперёд сообщаем об изменениях: дальние недели в ЛК
/// часто правят, и уведомления о них — шум.
let changesHorizon: TimeInterval = 7 * 24 * 3600

/// Сравнивает старое и новое расписание и описывает изменения в ближайшие
/// дни строками вида «Микроэкономика, ср 22.10: перенесли с 12:20 на 14:00».
/// Пары сопоставляются по дню, предмету и типу занятия.
func describeChanges(before: [Lesson], after: [Lesson], now: Date) -> [String] {
    let horizon = now.addingTimeInterval(changesHorizon)
    func relevant(_ l: Lesson) -> Bool { l.start > now && l.start < horizon }
    func key(_ l: Lesson) -> String { "\(l.start.dateOnly.timeIntervalSince1970)|\(l.subject)|\(l.kind)" }

    let old = Dictionary(grouping: before, by: key)
    let fresh = Dictionary(grouping: after, by: key)
    var changes: [(Date, String)] = []
    func add(_ l: Lesson, _ what: String) {
        let day = weekdaysShort[l.start.isoWeekday - 1].lowercased()
        changes.append((l.start, "\(l.subject), \(day) \(String(format: "%02d.%02d", l.start.day, l.start.month)): \(what)"))
    }

    for k in Set(old.keys).union(fresh.keys) {
        let a = old[k] ?? [], b = fresh[k] ?? []
        for i in 0..<max(a.count, b.count) {
            let was = i < a.count ? a[i] : nil
            let cur = i < b.count ? b[i] : nil
            if let was, let cur {
                if !relevant(was) && !relevant(cur) { continue }
                if was.cancelled != cur.cancelled {
                    add(cur, cur.cancelled ? "пару отменили" : "пару вернули")
                } else if was.start != cur.start || was.end != cur.end {
                    add(cur, "перенесли с \(hm(was.start)) на \(hm(cur.start))")
                } else if was.room != cur.room {
                    add(cur, "аудитория: \(cur.shortLocation)")
                }
            } else if let cur, relevant(cur), !cur.cancelled {
                add(cur, "добавили пару в \(hm(cur.start))")
            } else if let was, relevant(was), !was.cancelled {
                add(was, "пару в \(hm(was.start)) убрали")
            }
        }
    }
    return changes.sorted { $0.0 < $1.0 }.map(\.1)
}
