import XCTest
@testable import Ranepa

final class ExamSessionTests: XCTestCase {
    private func lesson(_ day: Int, _ month: Int, _ subject: String, _ kind: String, cancelled: Bool = false) -> Lesson {
        let start = date(month == 1 ? 2027 : 2026, month, day, 10)
        return Lesson(start: start, end: start.addingTimeInterval(80 * 60), subject: subject, kind: kind,
                      room: "5 - 307", lecturer: "", email: "", groups: [], lmsLink: "", comment: "", cancelled: cancelled)
    }

    private let now = date(2026, 12, 20, 12)

    func testGroupsConsultationWithExam() throws {
        let s = try XCTUnwrap(ExamSession(lessons: [
            lesson(18, 1, "Информатика", "зачёт"),
            lesson(20, 1, "Высшая математика", "консультация"),
            lesson(21, 1, "Высшая математика", "экзамен"),
            lesson(22, 1, "Высшая математика", "лекция"),
        ], now: now))
        XCTAssertEqual(s.items.map(\.exam.subject), ["Информатика", "Высшая математика"])
        XCTAssertNil(s.items[0].consultation)
        XCTAssertEqual(s.items[1].consultation?.kind, "консультация")
        XCTAssertEqual(s.summary, "экзамен и зачёт")
        XCTAssertEqual(s.dates, "18–21 января")
    }

    func testNoExamsNoSession() {
        XCTAssertNil(ExamSession(lessons: [lesson(18, 1, "Информатика", "лекция")], now: now))
        XCTAssertNil(ExamSession(lessons: [lesson(18, 1, "Информатика", "зачёт", cancelled: true)], now: now))
    }

    func testCardMonthBefore() throws {
        let s = try XCTUnwrap(ExamSession(lessons: [lesson(18, 1, "Информатика", "зачёт")], now: now))
        XCTAssertTrue(s.showsCard(now: now))
        XCTAssertFalse(s.showsCard(now: date(2026, 12, 1, 12)))
    }

    func testWords() {
        XCTAssertEqual(daysUntil(date(2026, 12, 21, 9), from: now), "завтра")
        XCTAssertEqual(daysUntil(date(2026, 12, 22, 9), from: now), "через 2 дня")
        XCTAssertEqual(daysUntil(date(2027, 1, 2, 9), from: now), "через 13 дней")
        XCTAssertEqual(daysUntil(date(2027, 1, 10, 9), from: now), "через 21 день")
    }
}
