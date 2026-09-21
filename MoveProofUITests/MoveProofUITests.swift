import XCTest

/// End-to-end smoke test of the walkthrough a tenant actually performs.
///
/// This is deliberately one long journey rather than several short tests: the
/// point is to prove the screens connect to each other and to the real Core Data
/// stack, which is exactly what a set of isolated screen tests would not show.
/// The business rules themselves are covered by the unit tests, which run against
/// mock repositories.
final class MoveProofWalkthroughUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testTenantCanSetUpAPropertyRecordDamageAndSignOffARoom() {
        let app = XCUIApplication()
        app.launchArguments += ["-MoveProofResetStoreForUITesting", "YES"]
        app.launch()

        // MARK: First run

        let addProperty = app.buttons["Add your property"]
        XCTAssertTrue(addProperty.waitForExistence(timeout: 10), "First run should offer to add a property")
        addProperty.tap()

        // MARK: Set up the property

        let addressField = app.textFields["Street address"]
        XCTAssertTrue(addressField.waitForExistence(timeout: 5))
        addressField.tap()
        addressField.typeText("12 Harris Street, Ultimo NSW 2007")

        app.buttons["Start walkthrough"].tap()

        // The dashboard should now show the property and its seeded rooms.
        XCTAssertTrue(
            app.staticTexts["12 Harris Street, Ultimo NSW 2007"].waitForExistence(timeout: 10),
            "The dashboard should show the property that was just created"
        )

        // MARK: Open a room

        app.tabBars.buttons["Rooms"].tap()
        let kitchen = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Kitchen'")).firstMatch
        XCTAssertTrue(kitchen.waitForExistence(timeout: 5), "The standard walkthrough should include a kitchen")
        kitchen.tap()

        // MARK: Recording damage without supporting detail is refused

        let flooring = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Flooring'")).firstMatch
        XCTAssertTrue(flooring.waitForExistence(timeout: 5))
        flooring.tap()

        app.buttons["Damaged"].firstMatch.tap()
        XCTAssertTrue(
            scrollToElement(app.buttons["Record this item"], in: app),
            "The record button should be reachable"
        )
        app.buttons["Record this item"].tap()

        XCTAssertTrue(
            app.staticTexts["This damage needs backing up"].waitForExistence(timeout: 5),
            "Recording damage with no note and no photo must be refused with domain wording"
        )

        // MARK: Adding a note satisfies the rule

        let noteField = app.textViews.firstMatch.exists
            ? app.textViews.firstMatch
            : app.textFields["Describe the damage — where it is and how bad it looks"]
        XCTAssertTrue(noteField.waitForExistence(timeout: 5))
        // Tap, then wait for the field to actually take focus before typing. Waiting on
        // `app.keyboards` instead would be wrong: when the simulator has a hardware
        // keyboard attached there is no software keyboard to wait for, and typing
        // still works.
        noteField.tap()
        waitForKeyboardFocus(on: noteField)
        noteField.typeText("Deep scratch across the vinyl near the oven.")

        dismissKeyboard(in: app)
        XCTAssertTrue(
            scrollToElement(app.buttons["Record this item"], in: app),
            "The record button should be reachable after entering a note"
        )
        app.buttons["Record this item"].tap()

        // Back on the room screen, the item should now read as damaged.
        XCTAssertTrue(
            app.staticTexts["Kitchen"].waitForExistence(timeout: 5),
            "Recording an item should return to the room"
        )

        // MARK: Signing off while items remain unreviewed is refused

        // The sign-off button sits below the checklist, and a SwiftUI List only
        // builds rows as they come into view, so scroll it into existence first.
        let signOff = app.buttons["Mark this room reviewed"]
        XCTAssertTrue(
            scrollToElement(signOff, in: app),
            "The room screen should offer to mark the room reviewed"
        )
        signOff.tap()

        XCTAssertTrue(
            app.staticTexts["This room isn't ready yet"].waitForExistence(timeout: 5),
            "Sign-off must be blocked while required checklist items are unreviewed"
        )
    }

    /// Waits until the field reports keyboard focus, retapping once if it did not take.
    ///
    /// SwiftUI's `TextField` returns from `tap()` before focus is established, and
    /// typing into an unfocused field fails outright.
    private func waitForKeyboardFocus(on element: XCUIElement, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        var retried = false
        while Date() < deadline {
            if element.value(forKey: "hasKeyboardFocus") as? Bool == true { return }
            if !retried, Date() > deadline.addingTimeInterval(-timeout / 2) {
                element.tap()
                retried = true
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    /// Puts the keyboard away so it cannot cover the control we are about to tap.
    private func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.element.exists else { return }
        if app.buttons["Return"].exists {
            app.buttons["Return"].tap()
        } else {
            app.navigationBars.firstMatch.tap()
        }
        _ = app.keyboards.element.waitForNonExistence(timeout: 3)
    }

    /// Swipes up until `element` exists and is on screen, or gives up.
    private func scrollToElement(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maximumSwipes: Int = 8
    ) -> Bool {
        for _ in 0..<maximumSwipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }
}
