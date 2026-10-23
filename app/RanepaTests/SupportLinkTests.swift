import XCTest
@testable import Ranepa

final class SupportLinkTests: XCTestCase {
    func testFormat() {
        XCTAssertEqual(
            SupportLink.startParameter(app: "2.2.0-30", os: "ios", osVersion: "27.0.1", model: "iphone-17-pro-max"),
            "app-2-2-0-30_ios-27-0-1_iphone-17-pro-max"
        )
    }

    func testKnownAndUnknownModels() {
        XCTAssertEqual(SupportLink.models["iPhone18,2"], "iphone-17-pro-max")
        XCTAssertEqual(SupportLink.slug("iPhone19,1"), "iphone19-1")
    }

    /// Собирает ссылку целиком, на реальном устройстве — из настоящих данных.
    /// Тесты идут в симуляторе, поэтому модель должна прийти с пометкой simulator.
    func testFullLink() throws {
        let url = SupportLink.url.absoluteString
        XCTAssertTrue(url.hasPrefix("https://t.me/ranepa_sync_robot?start=app-"))
        let start = try XCTUnwrap(url.components(separatedBy: "start=").last)
        XCTAssertNotNil(start.range(of: "^[a-z0-9_-]{1,64}$", options: .regularExpression))
        if ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] != nil {
            XCTAssertTrue(start.hasSuffix("-simulator"), start)
        }
    }

    /// Telegram отбрасывает start длиннее 64 символов и с недопустимыми знаками.
    func testOnlyModelIsShortened() {
        let start = SupportLink.startParameter(
            app: "12.34.56-789", os: "ipados", osVersion: "27.10.11",
            model: "ipad-pro-12-9-6-simulator-with-a-very-long-name"
        )
        XCTAssertLessThanOrEqual(start.count, SupportLink.maxLength)
        XCTAssertTrue(start.hasPrefix("app-12-34-56-789_ipados-27-10-11_ipad-pro"))
        XCTAssertFalse(start.hasSuffix("-"))
        XCTAssertNil(start.range(of: "[^a-z0-9_-]", options: .regularExpression))
    }
}
