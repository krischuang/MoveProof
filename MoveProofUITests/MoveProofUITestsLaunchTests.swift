import XCTest

/// Confirms the app reaches a rendered first screen under each UI configuration the
/// scheme runs, and attaches the screenshot as evidence.
///
/// It asserts nothing about the walkthrough. `MoveProofWalkthroughUITests` covers that.
/// The value here is catching a launch that crashes or hangs before any UI appears,
/// which no unit test can see.
final class MoveProofUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.tabBars.firstMatch.waitForExistence(timeout: 15),
            "The app should reach its root navigation on launch"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
