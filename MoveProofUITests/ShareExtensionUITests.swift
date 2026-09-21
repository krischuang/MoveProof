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

        // Terminate first so Photos starts on the grid rather than wherever a
        // previous test in the same run left it.
        let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        photos.terminate()
        photos.launch()
        XCTAssertTrue(photos.wait(for: .runningForeground, timeout: 15), "Photos should open")

        dismissAnyOnboarding(in: photos)

        // Make sure we are on the Library grid rather than Collections.
        let libraryTab = photos.buttons["Library"].firstMatch
        if libraryTab.waitForExistence(timeout: 5) {
            libraryTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            settle()
        }

        let firstPhoto = photos.images.matching(NSPredicate(format: "label CONTAINS 'Photo'")).firstMatch
        XCTAssertTrue(
            firstPhoto.waitForExistence(timeout: 20),
            "The simulator library should contain the seeded photo"
        )

        // Photos' grid uses a zoomable layout whose cells do not respond to
        // element-relative taps, so open a photo by tapping the window where a
        // thumbnail sits. Which row that is depends on how the grid is scrolled, so
        // try a few positions rather than depending on one magic coordinate.
        let shareButton = photos.buttons["Share"].firstMatch
        let candidates: [CGVector] = [
            CGVector(dx: 0.16, dy: 0.22),
            CGVector(dx: 0.50, dy: 0.35),
            CGVector(dx: 0.16, dy: 0.45),
            CGVector(dx: 0.83, dy: 0.60)
        ]
        var openedAPhoto = false
        for point in candidates {
            photos.coordinate(withNormalizedOffset: point).tap()
            settle()
            if shareButton.waitForExistence(timeout: 6) {
                openedAPhoto = true
                break
            }
            // Not a photo — go back to the grid and try elsewhere.
            if photos.buttons["Back"].firstMatch.exists {
                photos.buttons["Back"].firstMatch.tap()
                settle()
            }
        }

        attachScreenshot(named: "photos-after-opening-photo")
        XCTAssertTrue(
            openedAPhoto,
            "Opening a photo should reveal Photos' Share button"
        )
        shareButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        settle()

        // MARK: MoveProof must be offered in the share sheet

        // UIActivityViewController is presented inside the host app's process, so the
        // sheet and everything in it is queried through Photos rather than SpringBoard.
        let moveProofActivity = photos.staticTexts["MoveProof"].firstMatch

        // The sheet populates its app row asynchronously, and MoveProof may sit past
        // the end of the first page, so look, scroll, and look again a few times.
        var sheetShowsMoveProof = moveProofActivity.waitForExistence(timeout: 25)
        for _ in 0..<3 where !sheetShowsMoveProof {
            if photos.collectionViews.firstMatch.exists {
                photos.collectionViews.firstMatch.swipeLeft()
            } else {
                photos.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.62))
                    .press(forDuration: 0.05,
                           thenDragTo: photos.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.62)))
            }
            settle()
            sheetShowsMoveProof = moveProofActivity.waitForExistence(timeout: 8)
        }

        attachScreenshot(named: "share-sheet")
        XCTAssertTrue(
            sheetShowsMoveProof,
            "MoveProof should appear in the share sheet for a photo"
        )
        moveProofActivity.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        settle()

        // MARK: The extension runs and saves

        let saveButton = photos.buttons["Save to MoveProof"].firstMatch
        XCTAssertTrue(
            saveButton.waitForExistence(timeout: 20),
            "The MoveProof share extension should present its confirmation"
        )
        attachScreenshot(named: "share-extension-confirmation")
        saveButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(
            photos.staticTexts["Saved to MoveProof"].firstMatch.waitForExistence(timeout: 20),
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
