import XCTest
@testable import Ranepa

/// Проверяем только решения «идти или нет»: все случаи ниже не доходят до ЛК.
final class SyncPolicyTests: XCTestCase {
    private var d: UserDefaults!
    /// Вторник, 13 октября 2026, полдень.
    private let tuesday = date(2026, 10, 13, 12)

    override func setUp() {
        d = UserDefaults(suiteName: "SyncPolicyTests")!
        d.removePersistentDomain(forName: "SyncPolicyTests")
        d.setTime(tuesday.addingTimeInterval(-3600), Keys.lastFullAt)
    }

    private func skip(_ trigger: SyncTrigger, _ now: Date) -> SkipReason? {
        Sync.skipReason(d, trigger, now: now)
    }

    private func lesson(on day: Date) {
        let stamp = moscowStamp(day.dateOnly).prefix(10)
        saveDays([["date": "\(stamp)T00:00:00",
                   "discs": [["start_date": "\(stamp)T10:00:00", "end_date": "\(stamp)T11:30:00"]]]], d)
    }

    func testBackoffAfterServerError() {
        d.setTime(tuesday.addingTimeInterval(8 * 3600), Keys.backoffUntil)
        XCTAssertEqual(skip(.manual, tuesday), .backoff)
    }

    /// Сессия истекла: фон и открытие в ЛК не ходят, «потянуть вниз» пробует.
    func testExpiredSessionSkipsAutomatic() {
        d.set(true, forKey: Keys.sessionExpired)
        XCTAssertEqual(skip(.background, tuesday), .needLogin)
        XCTAssertEqual(skip(.open, tuesday), .needLogin)
        XCTAssertNil(skip(.manual, tuesday))
    }

    /// Ночью тоже ходим — иначе сессия ЛК истечёт.
    func testNightStillRuns() {
        XCTAssertNil(skip(.background, date(2026, 10, 13, 3)))
    }

    func testBackgroundInterval() {
        lesson(on: date(2026, 10, 14, 0))
        d.setTime(tuesday.addingTimeInterval(-30 * 60), Keys.lastAttemptAt)
        XCTAssertEqual(skip(.background, tuesday), .tooSoon)
        // Будни днём — раз в час.
        d.setTime(tuesday.addingTimeInterval(-3600), Keys.lastAttemptAt)
        XCTAssertNil(skip(.background, tuesday))
    }

    func testIntervals() {
        XCTAssertEqual(Sync.interval(at: date(2026, 10, 13, 3)), 4 * 3600)       // ночь в будни
        XCTAssertEqual(Sync.interval(at: date(2026, 10, 13, 6)), 3600)           // будни утром
        XCTAssertEqual(Sync.interval(at: date(2026, 10, 13, 22)), 3 * 3600)
        XCTAssertEqual(Sync.interval(at: date(2026, 10, 17, 12)), 2 * 3600)      // суббота
        XCTAssertEqual(Sync.interval(at: date(2026, 10, 17, 3)), 4 * 3600)       // ночь на субботу
        XCTAssertEqual(Sync.interval(at: date(2026, 10, 18, 12)), 12 * 3600)     // воскресенье днём
        XCTAssertEqual(Sync.interval(at: date(2026, 10, 18, 19)), 3 * 3600)      // воскресенье вечером
    }

    /// Пн–Сб — не реже раза в 4 часа, в воскресенье — раз в 12.
    func testMaxGaps() {
        var t = date(2026, 10, 12, 0)
        let end = date(2026, 10, 19, 0)
        while t < end {
            let next = Sync.nextRun(after: t)
            let limit: TimeInterval = t.isoWeekday == 7 || next.isoWeekday == 7 ? 12 * 3600 : 4 * 3600
            XCTAssertLessThanOrEqual(next.timeIntervalSince(t), limit, "\(t)")
            t = next
        }
    }

    func testNextRun() {
        XCTAssertEqual(Sync.nextRun(after: tuesday), tuesday.addingTimeInterval(3600))
        // Вторник 23:30 → ночью через 4 часа.
        XCTAssertEqual(Sync.nextRun(after: date(2026, 10, 13, 23, 30)), date(2026, 10, 14, 3, 30))
        // Воскресенье 14:00 → не ждать 12 часов, а в 18:00.
        XCTAssertEqual(Sync.nextRun(after: date(2026, 10, 18, 14)), date(2026, 10, 18, 18))
    }

    func testHolidaysEveryFourHours() {
        d.setTime(tuesday.addingTimeInterval(-3 * 3600), Keys.lastAttemptAt)
        XCTAssertEqual(skip(.background, tuesday), .tooSoon)
        d.setTime(tuesday.addingTimeInterval(-4 * 3600), Keys.lastAttemptAt)
        XCTAssertNil(skip(.background, tuesday))
    }

    func testBackgroundRunsWhenLessonsSoon() {
        lesson(on: date(2026, 10, 14, 0))
        XCTAssertNil(skip(.background, tuesday))
    }

    func testSemesterWeekly() {
        XCTAssertTrue(Sync.isSemesterDue(d, now: tuesday))
        d.setTime(tuesday.addingTimeInterval(-6 * 24 * 3600), Keys.lastSemesterAt)
        XCTAssertFalse(Sync.isSemesterDue(d, now: tuesday))
        d.setTime(tuesday.addingTimeInterval(-7 * 24 * 3600), Keys.lastSemesterAt)
        XCTAssertTrue(Sync.isSemesterDue(d, now: tuesday))
    }

    func testFutureTimestampIsStale() {
        lesson(on: date(2026, 10, 14, 0))
        d.setTime(date(2027, 1, 20, 11), Keys.lastAttemptAt)
        d.setTime(date(2027, 1, 20, 11), Keys.fetchedAt)
        XCTAssertNil(skip(.background, tuesday))
        XCTAssertNil(skip(.open, tuesday))
    }

    func testManualRightAfterPrevious() {
        d.setTime(tuesday.addingTimeInterval(-30), Keys.fetchedAt)
        XCTAssertEqual(skip(.manual, tuesday), .tooSoon)
    }

    func testOpenWithFreshData() {
        d.setTime(tuesday.addingTimeInterval(-30 * 60), Keys.fetchedAt)
        XCTAssertEqual(skip(.open, tuesday), .notNeeded)
        // Днём в будни данные старше часа обновляются при открытии.
        d.setTime(tuesday.addingTimeInterval(-3600), Keys.fetchedAt)
        XCTAssertNil(skip(.open, tuesday))
    }
}

func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}
