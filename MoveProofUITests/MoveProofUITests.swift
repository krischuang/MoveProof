import XCTest

/// End-to-end smoke test of the walkthrough a tenant performs.
///
/// One long journey instead of several short tests, because the point is to show
/// the screens connect to each other and to the real Core Data stack, something a
/// set of isolated screen tests would not show.
///
/// ## What this covers, and what it does not
///
/// It covers navigation and the two places a domain rule has to reach the screen:
/// refusing undocumented damage, and refusing sign-off while the room is not ready.
/// Those assertions check the exact wording the tenant reads, so a change to a
/// `TenantFacingError` that broke the UI copy would fail here.
///
/// It does **not** drive the note field or the photo picker. Typing into a multiline
/// SwiftUI `TextField(axis: .vertical)` and then reaching a button underneath the
/// keyboard proved unreliable in XCUITest: the field reports a degenerate frame and
/// the button below it never becomes hittable. That is a test harness problem, not
/// app behaviour, and the rules it would have exercised (damage plus a note is
/// accepted; sign-off succeeds once every item is reviewed) are covered
/// deterministically in `RecordConditionEvidenceTests` and
/// `CompleteInspectionAreaTests` against mock repositories.
final class MoveProofWalkthroughUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testTenantCanSetUpAPropertyAndSeeBothInspectionRulesRefuseOnScreen() {
        let app = XCUIApplication()
        app.launchArguments += ["-MoveProofResetStoreForUITesting", "YES"]
        app.launch()

        // MARK: First run offers to set a property up

        let addProperty = app.buttons["Add your property"]
        XCTAssertTrue(addProperty.waitForExistence(timeout: 15), "First run should offer to add a property")
        addProperty.tap()

        // MARK: Creating the tenancy writes through to Core Data

        let addressField = app.textFields["Street address"]
        XCTAssertTrue(addressField.waitForExistence(timeout: 10))
        addressField.tap()
        addressField.typeText("12 Harris Street, Ultimo NSW 2007")

        app.buttons["Start walkthrough"].tap()

        XCTAssertTrue(
            app.staticTexts["12 Harris Street, Ultimo NSW 2007"].waitForExistence(timeout: 15),
            "The dashboard should show the property that was just created"
        )

        // MARK: The walkthrough is seeded with rooms

        app.tabBars.buttons["Rooms"].tap()
        let kitchen = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Kitchen'")).firstMatch
        XCTAssertTrue(
            kitchen.waitForExistence(timeout: 10),
            "StartTenancyInspectionUseCase should have seeded the standard rooms"
        )
        kitchen.tap()

        // MARK: Rule: damage with nothing to back it up is refused, in the tenant's words

        let flooring = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Flooring'")).firstMatch
        XCTAssertTrue(flooring.waitForExistence(timeout: 10))
        flooring.tap()

        app.buttons["Damaged"].firstMatch.tap()

        let recordItem = app.buttons["Record this item"]
        XCTAssertTrue(scrollToElement(recordItem, in: app), "The record button should be reachable")
        recordItem.tap()

        XCTAssertTrue(
            app.staticTexts["This damage needs backing up"].waitForExistence(timeout: 10),
            "Recording damage with no note and no photo must be refused with domain wording"
        )
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS 'Add a photo or write a short note'")
            ).firstMatch.exists,
            "The refusal must tell the tenant what to do next, not just that it failed"
        )

        // MARK: Rule: a room cannot be signed off while items are unreviewed

        app.navigationBars.buttons.firstMatch.tap()   // back to the room
        XCTAssertTrue(
            app.staticTexts["Not started"].firstMatch.waitForExistence(timeout: 10)
                || app.staticTexts["In progress"].firstMatch.exists,
            "The room screen should show its inspection status"
        )

        let signOff = app.buttons["Mark this room reviewed"]
        XCTAssertTrue(
            scrollToElement(signOff, in: app),
            "The room screen should offer to mark the room reviewed"
        )
        signOff.tap()

        XCTAssertTrue(
            app.staticTexts["This room isn't ready yet"].waitForExistence(timeout: 10),
            "Sign-off must be blocked while required checklist items are unreviewed"
        )
    }

    /// Swipes up until `element` is on screen and tappable, or gives up.
    ///
    /// A SwiftUI `List` only builds rows as they come into view, so a control below
    /// the fold does not exist in the hierarchy until it is scrolled to.
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
