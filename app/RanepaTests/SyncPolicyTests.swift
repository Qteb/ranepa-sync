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

    private func skip(_ trigger: SyncTrigger, _ now: Date, config: RemoteConfig = RemoteConfig()) -> SkipReason? {
        Sync.skipReason(d, trigger, config: config, now: now)
    }

    private func lesson(on day: Date) {
        let stamp = moscowStamp(day.dateOnly).prefix(10)
        saveDays([["date": "\(stamp)T00:00:00",
                   "discs": [["start_date": "\(stamp)T10:00:00", "end_date": "\(stamp)T11:30:00"]]]], d)
    }

    func testKillSwitch() {
        var config = RemoteConfig()
        config.sync = false
        XCTAssertEqual(skip(.manual, tuesday, config: config), .paused)
    }

    func testBackoffAfterServerError() {
        d.setTime(tuesday.addingTimeInterval(8 * 3600), Keys.backoffUntil)
        XCTAssertEqual(skip(.manual, tuesday), .backoff)
    }

    func testQuietHours() {
        XCTAssertEqual(skip(.background, date(2026, 10, 13, 3)), .quietHours)
    }

    func testBackgroundInterval() {
        d.setTime(tuesday.addingTimeInterval(-3 * 3600), Keys.lastAttemptAt)
        XCTAssertEqual(skip(.background, tuesday), .tooSoon)
    }

    func testSundayOnlyDailyFullLoad() {
        let sunday = date(2026, 10, 18, 12)
        d.setTime(sunday.addingTimeInterval(-3600), Keys.lastFullAt)
        lesson(on: date(2026, 10, 19, 0))
        XCTAssertEqual(skip(.background, sunday), .notNeeded)
    }

    func testHolidaysOnlyDailyFullLoad() {
        XCTAssertEqual(skip(.background, tuesday), .notNeeded)
    }

    func testBackgroundRunsWhenLessonsSoon() {
        lesson(on: date(2026, 10, 14, 0))
        XCTAssertNil(skip(.background, tuesday))
    }

    func testManualRightAfterPrevious() {
        d.setTime(tuesday.addingTimeInterval(-30), Keys.fetchedAt)
        XCTAssertEqual(skip(.manual, tuesday), .tooSoon)
    }

    func testOpenWithFreshData() {
        d.setTime(tuesday.addingTimeInterval(-3600), Keys.fetchedAt)
        XCTAssertEqual(skip(.open, tuesday), .notNeeded)
    }
}

func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}
