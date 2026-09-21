import XCTest

/// Drives the real iOS share sheet to prove the MoveProof Share Extension is
/// registered, runs, writes into the App Group inbox and dismisses itself.
///
/// This test crosses process boundaries — Photos, the share sheet, the extension,
/// then MoveProof — which is the only way to show the hand-off genuinely works
/// rather than that the code compiles.
final class ShareExtensionUITests: XCTestCase {

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = false
    }

    /// Gives the system a beat to finish an animation. Cross-process transitions do
    /// not always raise an event the framework can wait on.
    private func settle() {
        Thread.sleep(forTimeInterval: 1.5)
    }

    /// Photos shows a one-time intro on a fresh simulator that blocks the grid.
    private func dismissAnyOnboarding(in app: XCUIApplication) {
        for label in ["Continue", "Get Started", "Not Now", "Later"] {
            let button = app.buttons[label].firstMatch
            if button.waitForExistence(timeout: 2) {
                button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                settle()
            }
        }
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSharingAPhotoFromPhotosPutsItInTheMoveProofInbox() throws {
        // MARK: Set up a property so the inbox has somewhere to file evidence

        let moveProof = XCUIApplication()
        moveProof.launchArguments += ["-MoveProofResetStoreForUITesting", "YES"]
        moveProof.launch()

        let addProperty = moveProof.buttons["Add your property"]
        XCTAssertTrue(addProperty.waitForExistence(timeout: 10))
        addProperty.tap()

        let addressField = moveProof.textFields["Street address"]
        XCTAssertTrue(addressField.waitForExistence(timeout: 5))
        addressField.tap()
        addressField.typeText("12 Harris Street, Ultimo NSW 2007")
        moveProof.buttons["Start walkthrough"].tap()
        XCTAssertTrue(moveProof.staticTexts["12 Harris Street, Ultimo NSW 2007"].waitForExistence(timeout: 10))

        // MARK: Share a photo from Photos into MoveProof

        let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        photos.launch()
        XCTAssertTrue(photos.wait(for: .runningForeground, timeout: 15), "Photos should open")

        dismissAnyOnboarding(in: photos)

        // Open the first photo in the library. Photos reports grid items as present
        // but not hittable on a fresh simulator, so tap by coordinate instead of
        // relying on the element's own hit-testing.
        let firstPhoto = photos.images.matching(NSPredicate(format: "label CONTAINS 'Photo'")).firstMatch
        XCTAssertTrue(
            firstPhoto.waitForExistence(timeout: 20),
            "The simulator library should contain the seeded photo"
        )
        firstPhoto.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        settle()

        let shareButton = photos.buttons["Share"].firstMatch
        XCTAssertTrue(shareButton.waitForExistence(timeout: 15), "Photos should offer a Share button")
        shareButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        settle()

        // MARK: MoveProof must be offered in the share sheet

        // The share sheet is presented by SpringBoard, not by Photos, so query it there.
        let moveProofActivity = springboard.staticTexts["MoveProof"].firstMatch
        if !moveProofActivity.waitForExistence(timeout: 20) {
            // The app row may be past the end of the first page of the activity list.
            springboard.collectionViews.firstMatch.swipeLeft()
            settle()
        }
        XCTAssertTrue(
            moveProofActivity.waitForExistence(timeout: 15),
            "MoveProof should appear in the share sheet for a photo"
        )
        moveProofActivity.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        settle()

        // MARK: The extension runs and saves

        let saveButton = springboard.buttons["Save to MoveProof"].firstMatch
        XCTAssertTrue(
            saveButton.waitForExistence(timeout: 20),
            "The MoveProof share extension should present its confirmation"
        )
        attachScreenshot(named: "share-extension-confirmation")
        saveButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(
            springboard.staticTexts["Saved to MoveProof"].firstMatch.waitForExistence(timeout: 20),
            "The extension should confirm the file was written to the shared inbox"
        )
        attachScreenshot(named: "share-extension-saved")

        // The extension dismisses itself after completing the request.
        XCTAssertTrue(
            saveButton.waitForNonExistence(timeout: 30),
            "The share extension must dismiss itself after completing the request"
        )

        // MARK: The main app sees the item in its inbox

        // Relaunch without the reset flag so the tenancy created above survives.
        let moveProofAgain = XCUIApplication()
        moveProofAgain.launchArguments = []
        moveProofAgain.launch()

        moveProofAgain.tabBars.buttons["Shared"].tap()

        XCTAssertTrue(
            moveProofAgain.buttons["Add to evidence"].firstMatch.waitForExistence(timeout: 15),
            "The shared photo should be waiting in MoveProof's shared items inbox"
        )

        // MARK: Importing files it as evidence

        moveProofAgain.buttons["Add to evidence"].firstMatch.tap()
        XCTAssertTrue(
            moveProofAgain.staticTexts["Filed"].waitForExistence(timeout: 10),
            "Importing should confirm the evidence was filed"
        )
        moveProofAgain.buttons["OK"].tap()

        moveProofAgain.tabBars.buttons["Evidence"].tap()
        XCTAssertTrue(
            moveProofAgain.staticTexts["Not filed against a room yet"].firstMatch.waitForExistence(timeout: 10),
            "The imported photo should now be in the evidence library"
        )
    }
}
