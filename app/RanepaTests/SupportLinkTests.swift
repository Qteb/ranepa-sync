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
