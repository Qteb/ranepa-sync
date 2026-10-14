import XCTest
@testable import Ranepa

final class ParsingTests: XCTestCase {
    func testKinds() {
        XCTAssertEqual(kindOf(type: "Лекция", subject: "Математика"), "лекция")
        XCTAssertEqual(kindOf(type: "Практическое занятие", subject: "Элективные дисциплины по физической культуре"), "физкультура")
    }
}
