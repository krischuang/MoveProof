import XCTest
@testable import MoveProof

/// Rules covered: address required, one walkthrough at a time, move-in date sanity,
/// deadline ordering, and the shape of the walkthrough that gets seeded.
@MainActor
final class StartTenancyInspectionTests: XCTestCase {

    private var tenancyRepository: MockTenancyRepository!
    private var inspectionRepository: MockInspectionRepository!
    private var useCase: StartTenancyInspectionUseCase!

    private let referenceDate = Date(timeIntervalSince1970: 1_780_000_000) // 2026-06-08

    override func setUp() {
        super.setUp()
        tenancyRepository = MockTenancyRepository()
        inspectionRepository = MockInspectionRepository()
        useCase = StartTenancyInspectionUseCase(
            tenancyRepository: tenancyRepository,
            inspectionRepository: inspectionRepository
        )
    }

    // MARK: - Happy path

    func testStartingATenancyCreatesDefaultInspectionAreasWithChecklists() throws {
        let tenancy = try useCase.execute(
            .init(propertyAddress: "12 Harris Street, Ultimo NSW 2007", moveInDate: referenceDate),
            now: referenceDate
        )

        XCTAssertEqual(tenancy.propertyAddress, "12 Harris Street, Ultimo NSW 2007")
        XCTAssertEqual(tenancy.status, .documenting)

        let areas = try inspectionRepository.fetchAreas(forTenancy: tenancy.id)
        XCTAssertEqual(
            areas.count,
            InspectionArea.defaultAreaNames.count,
            "A new walkthrough should open with the standard rooms, not an empty list"
        )
        XCTAssertEqual(areas.map(\.name), InspectionArea.defaultAreaNames)
        XCTAssertTrue(areas.allSatisfy { $0.inspectionStatus == .notStarted })

        for area in areas {
            let items = try inspectionRepository.fetchConditionItems(inArea: area.id)
            XCTAssertGreaterThanOrEqual(
                items.count,
                ConditionItem.defaultChecklist.count,
                "\(area.name) should be seeded with at least the standard checklist"
            )
            XCTAssertTrue(items.allSatisfy { $0.conditionState == .notReviewed })
        }
    }

    func testTheKitchenIsSeededWithApplianceChecksTheOtherRoomsDoNotGet() throws {
        let tenancy = try useCase.execute(
            .init(propertyAddress: "12 Harris Street", moveInDate: referenceDate),
            now: referenceDate
        )

        let areas = try inspectionRepository.fetchAreas(forTenancy: tenancy.id)
        let kitchen = try XCTUnwrap(areas.first { $0.name == "Kitchen" })
        let livingRoom = try XCTUnwrap(areas.first { $0.name == "Living room" })

        let kitchenTitles = try inspectionRepository.fetchConditionItems(inArea: kitchen.id).map(\.title)
        let livingTitles = try inspectionRepository.fetchConditionItems(inArea: livingRoom.id).map(\.title)

        XCTAssertTrue(kitchenTitles.contains("Oven and cooktop"))
        XCTAssertFalse(livingTitles.contains("Oven and cooktop"))
        XCTAssertTrue(livingTitles.contains("Smoke alarm"), "Living areas should prompt for a smoke alarm check")
    }

    func testTheConditionReportDefaultsToSevenDaysAfterMovingIn() throws {
        let tenancy = try useCase.execute(
            .init(propertyAddress: "12 Harris Street", moveInDate: referenceDate),
            now: referenceDate
        )

        let expected = Calendar.current.date(
            byAdding: .day,
            value: 7,
            to: Calendar.current.startOfDay(for: referenceDate)
        )
        XCTAssertEqual(tenancy.conditionReportDueDate, expected)
        XCTAssertEqual(tenancy.daysUntilConditionReportDue(asOf: referenceDate), 7)
    }

    // MARK: - Error cases

    func testStartingATenancyWithoutAnAddressIsRejected() {
        XCTAssertThrowsError(
            try useCase.execute(.init(propertyAddress: "   ", moveInDate: referenceDate), now: referenceDate)
        ) { error in
            XCTAssertEqual(error as? TenancySetupError, .missingPropertyAddress)
            XCTAssertTrue(
                (error as? TenantFacingError)?.whatToDoNext.contains("tenancy agreement") == true,
                "The tenant should be told where to find the address, not just that it is missing"
            )
        }
        XCTAssertTrue(tenancyRepository.savedTenancies.isEmpty, "Nothing should be written when validation fails")
    }

    func testStartingASecondWalkthroughWhileOneIsActiveIsRejected() throws {
        try useCase.execute(
            .init(propertyAddress: "12 Harris Street", moveInDate: referenceDate),
            now: referenceDate
        )

        XCTAssertThrowsError(
            try useCase.execute(
                .init(propertyAddress: "9 Jones Street", moveInDate: referenceDate),
                now: referenceDate
            )
        ) { error in
            XCTAssertEqual(
                error as? TenancySetupError,
                .inspectionAlreadyStarted(existingAddress: "12 Harris Street"),
                "The refusal should name the property already being documented"
            )
        }
        XCTAssertEqual(tenancyRepository.savedTenancies.count, 1)
    }

    func testAConditionReportDueBeforeMoveInIsRejected() {
        let dueDate = Calendar.current.date(byAdding: .day, value: -1, to: referenceDate)!

        XCTAssertThrowsError(
            try useCase.execute(
                .init(
                    propertyAddress: "12 Harris Street",
                    moveInDate: referenceDate,
                    conditionReportDueDate: dueDate
                ),
                now: referenceDate
            )
        ) { error in
            XCTAssertEqual(error as? TenancySetupError, .conditionReportDueBeforeMoveIn)
        }
    }

    // MARK: - Boundary cases

    func testAMoveInDateExactlyOnTheBackdatingLimitIsAccepted() throws {
        let moveIn = Calendar.current.date(
            byAdding: .day,
            value: -TenancySetupError.maximumBackdatedMoveInDays,
            to: referenceDate
        )!

        let tenancy = try useCase.execute(
            .init(propertyAddress: "12 Harris Street", moveInDate: moveIn),
            now: referenceDate
        )
        XCTAssertEqual(tenancy.moveInDate, moveIn, "The limit itself should still be allowed")
    }

    func testAMoveInDateOneDayBeyondTheBackdatingLimitIsRejected() {
        let moveIn = Calendar.current.date(
            byAdding: .day,
            value: -(TenancySetupError.maximumBackdatedMoveInDays + 1),
            to: referenceDate
        )!

        XCTAssertThrowsError(
            try useCase.execute(
                .init(propertyAddress: "12 Harris Street", moveInDate: moveIn),
                now: referenceDate
            )
        ) { error in
            XCTAssertEqual(
                error as? TenancySetupError,
                .moveInDateTooFarInPast(days: TenancySetupError.maximumBackdatedMoveInDays + 1)
            )
        }
    }

    func testAConditionReportDueOnTheMoveInDayItselfIsAccepted() throws {
        let tenancy = try useCase.execute(
            .init(
                propertyAddress: "12 Harris Street",
                moveInDate: referenceDate,
                conditionReportDueDate: referenceDate
            ),
            now: referenceDate
        )
        XCTAssertEqual(tenancy.daysUntilConditionReportDue(asOf: referenceDate), 0)
    }
}
