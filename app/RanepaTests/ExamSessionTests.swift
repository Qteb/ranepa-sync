import XCTest
@testable import Ranepa

final class ExamSessionTests: XCTestCase {
    private func lesson(_ day: Int, _ month: Int, _ subject: String, _ kind: String, cancelled: Bool = false) -> Lesson {
        let start = date(month == 1 ? 2027 : 2026, month, day, 10)
        return Lesson(start: start, end: start.addingTimeInterval(80 * 60), subject: subject, kind: kind,
                      room: "5 - 307", lecturer: "", email: "", groups: [], lmsLink: "", comment: "", cancelled: cancelled)
    }

    private func item(_ name: String, _ control: String?, semester: String = "1-й семестр") -> StudyPlan.Item {
        StudyPlan.Item(name: name, control: control, hours: 72, ze: 2, course: 1, semester: semester, elective: false,
                       practice: false, courseWork: false, facultative: false, selected: true)
    }

    private let now = date(2026, 12, 20, 12)

    private var plan: StudyPlan {
        StudyPlan(items: [
            item("ФУНДАМЕНТАЛЬНАЯ ЧАСТЬ", "Экзамен"),
            item("Высшая математика", "Экзамен"),
            item("Информатика", "Зачет"),
            item("История России", "Зачет"),
            item("Макроэкономика", "Экзамен", semester: "2-й семестр"),
        ], sessions: [
            StudyPlan.Session(course: "1-й курс", semester: "1-й семестр", start: "11.01.2027", end: "30.01.2027"),
            StudyPlan.Session(course: "1-й курс", semester: "2-й семестр", start: "14.06.2027", end: "03.07.2027"),
        ])
    }

    func testPlanDefinesSession() throws {
        let s = try XCTUnwrap(ExamSession(lessons: [
            lesson(18, 1, "Информатика", "зачёт"),
            lesson(20, 1, "Высшая математика", "консультация"),
            lesson(21, 1, "Высшая математика", "экзамен"),
        ], plan: plan, now: now))
        XCTAssertEqual(s.exams.map(\.subject), ["Высшая математика"])
        XCTAssertNotNil(s.exams[0].consultation)
        // Зачёт по истории — без даты, но в списке.
        XCTAssertEqual(s.credits.map(\.subject), ["Информатика", "История России"])
        XCTAssertNil(s.credits[1].event)
        XCTAssertEqual(s.summary, "экзамен и 2 зачёта")
        XCTAssertEqual(s.dates, "11–30 января")
    }

    func testCurrentSemester() {
        XCTAssertEqual(plan.currentSemester(now: now), 1)
        XCTAssertEqual(plan.currentSemester(now: date(2027, 2, 10, 12)), 2)
        XCTAssertEqual(plan.subjects(semester: 1).map(\.name), ["Высшая математика", "Информатика", "История России"])
    }

    func testWithoutPlan() throws {
        XCTAssertNil(ExamSession(lessons: [lesson(18, 1, "Информатика", "лекция")], plan: nil, now: now))
        XCTAssertNil(ExamSession(lessons: [lesson(18, 1, "Информатика", "зачёт", cancelled: true)], plan: nil, now: now))
        let s = try XCTUnwrap(ExamSession(lessons: [lesson(18, 1, "Информатика", "зачёт")], plan: nil, now: now))
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
