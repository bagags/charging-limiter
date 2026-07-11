import XCTest

final class ChargingLimiterUITests: XCTestCase {
    func testMenuBarApplicationLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.state == .runningForeground || app.state == .runningBackground,
            "The menu-bar application should remain running after launch."
        )
    }
}
