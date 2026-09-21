import XCTest

/// Drives the real iOS share sheet to prove the MoveProof Share Extension is
/// registered, runs, writes into the App Group inbox and dismisses itself.
///
/// This test crosses process boundaries — Photos, the share sheet, the extension,
/// then MoveProof — which is the only way to show the hand-off genuinely works
/// rather than that the code compiles.
final class ShareExtensionUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
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

        // Open the first photo in the library.
        let firstPhoto = photos.images.matching(NSPredicate(format: "label CONTAINS 'Photo'")).firstMatch
        if firstPhoto.waitForExistence(timeout: 10) {
            firstPhoto.tap()
        } else {
            let anyCell = photos.cells.firstMatch
            XCTAssertTrue(anyCell.waitForExistence(timeout: 10), "The simulator library should contain the seeded photo")
            anyCell.tap()
        }

        let shareButton = photos.buttons["Share"].firstMatch
        XCTAssertTrue(shareButton.waitForExistence(timeout: 10), "Photos should offer a Share button")
        shareButton.tap()

        // MARK: MoveProof must be offered in the share sheet

        let moveProofActivity = photos.staticTexts["MoveProof"].firstMatch
        let appeared = moveProofActivity.waitForExistence(timeout: 15)
        if !appeared {
            // The app row may be past the end of the first page of the sheet.
            photos.collectionViews.firstMatch.swipeLeft()
        }
        XCTAssertTrue(
            moveProofActivity.waitForExistence(timeout: 10),
            "MoveProof should appear in the share sheet for a photo"
        )
        moveProofActivity.tap()

        // MARK: The extension runs and saves

        let saveButton = photos.buttons["Save to MoveProof"]
        XCTAssertTrue(
            saveButton.waitForExistence(timeout: 15),
            "The MoveProof share extension should present its confirmation"
        )
        saveButton.tap()

        XCTAssertTrue(
            photos.staticTexts["Saved to MoveProof"].waitForExistence(timeout: 15),
            "The extension should confirm the file was written to the shared inbox"
        )

        // The extension dismisses itself; Photos should be back in front.
        XCTAssertTrue(
            saveButton.waitForNonExistence(timeout: 20),
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
