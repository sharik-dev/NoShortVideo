import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "YES"]
        setupSnapshot(app)
        // Force portrait before launch
        XCUIDevice.shared.orientation = .portrait
        app.launch()
    }

    func testCaptureScreenshots() throws {
        // 01 — Home screen (BrowserHomeView appears first as fullScreenCover)
        let homeTitle = app.staticTexts["What do you want to watch?"]
        XCTAssertTrue(homeTitle.waitForExistence(timeout: 8))
        // Dismiss keyboard if it appeared automatically
        if app.keyboards.firstMatch.exists {
            app.typeText("\n")
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1.0)
        snapshot("01_Home")

        // Dismiss home — the close button frame is reported off-screen in fullScreenCover
        // during snapshot, so we tap by normalized screen coordinate (top-right corner)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.08)).tap()

        // 02 — YouTube Player with bottom toolbar visible
        Thread.sleep(forTimeInterval: 2.5)
        snapshot("02_Player")

        // Open Settings — try known SwiftUI SF Symbol labels then coordinate fallback
        // "gearshape" SF Symbol accessibility label in English is "Gear Shape"
        let settingsButton = app.buttons["Gear Shape"]
        if settingsButton.waitForExistence(timeout: 4) {
            settingsButton.tap()
        } else {
            // Fallback: 7th button of 8 in the horizontal toolbar (≈82% from left, near bottom)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.95)).tap()
        }

        // 03 — Settings sheet (wait for sheet animation + any Form text)
        Thread.sleep(forTimeInterval: 3.0)
        snapshot("03_Settings")
    }
}
