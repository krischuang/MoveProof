import XCTest
@testable import MoveProof

/// Rules covered: the field checks match the ones `StartTenancyInspectionUseCase`
/// applies, the backdating typo check is skipped for a tenancy already under way,
/// and editing the details never changes the tenancy id or detaches its evidence.
@MainActor
final class UpdateTenancyDetailsTests: XCTestCase {

    private var tenancyRepository: MockTenancyRepository!
    private var useCase: UpdateTenancyDetailsUseCase!

    private var tenancy: Tenancy!
    private let moveIn = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        tenancy = Tenancy(
            propertyAddress: "12 Smith Street, Redfern",
            moveInDate: moveIn,
            conditionReportDueDate: moveIn.addingTimeInterval(7 * 86_400),
            createdAt: moveIn,
            status: .documenting
        )
        tenancyRepository = MockTenancyRepository(tenancies: [tenancy])
        useCase = UpdateTenancyDetailsUseCase(tenancyRepository: tenancyRepository)
    }

    private func request(
        tenancyID: UUID? = nil,
        address: String = "12A Smith Street, Redfern",
        moveInDate: Date? = nil,
        dueDate: Date? = nil
    ) -> UpdateTenancyDetailsUseCase.Request {
        UpdateTenancyDetailsUseCase.Request(
            tenancyID: tenancyID ?? tenancy.id,
            details: TenancyDetails(
                propertyAddress: address,
                moveInDate: moveInDate ?? moveIn,
                conditionReportDueDate: dueDate
            )
        )
    }

    // MARK: - Happy path

    func testCorrectingTheAddressKeepsTheWalkthroughTheTenantHasAlreadyBuilt() throws {
        let updated = try useCase.execute(request(), now: moveIn)

        XCTAssertEqual(updated.propertyAddress, "12A Smith Street, Redfern")
        XCTAssertEqual(updated.id, tenancy.id, "The tenancy identity must survive so evidence stays attached")
        XCTAssertEqual(updated.createdAt, tenancy.createdAt)
        XCTAssertEqual(updated.status, tenancy.status)
        XCTAssertEqual(tenancyRepository.savedTenancies.count, 1)
    }

    func testTheAddressIsTrimmedSoStrayWhitespaceIsNotStored() throws {
        let updated = try useCase.execute(request(address: "  5 Park Road, Newtown \n"), now: moveIn)

        XCTAssertEqual(updated.propertyAddress, "5 Park Road, Newtown")
    }

    func testLeavingTheDueDateOnTheDefaultFollowsTheMoveInDateTheTenantCorrectedTo() throws {
        let correctedMoveIn = moveIn.addingTimeInterval(3 * 86_400)

        let updated = try useCase.execute(
            request(moveInDate: correctedMoveIn, dueDate: nil),
            now: moveIn
        )

        XCTAssertEqual(
            updated.conditionReportDueDate,
            Tenancy.defaultConditionReportDueDate(movingIn: correctedMoveIn)
        )
    }

    // MARK: - Domain rules

    func testUpdatingTenancyRejectsAnEmptyAddress() {
        XCTAssertThrowsError(try useCase.execute(request(address: "   "), now: moveIn)) { error in
            XCTAssertEqual(error as? TenancySetupError, .missingPropertyAddress)
        }
        XCTAssertTrue(tenancyRepository.savedTenancies.isEmpty)
    }

    func testUpdatingTenancyRejectsDueDateBeforeMoveInDate() {
        let dayBeforeMoveIn = moveIn.addingTimeInterval(-86_400)

        XCTAssertThrowsError(try useCase.execute(request(dueDate: dayBeforeMoveIn), now: moveIn)) { error in
            XCTAssertEqual(error as? TenancySetupError, .conditionReportDueBeforeMoveIn)
        }
        XCTAssertTrue(tenancyRepository.savedTenancies.isEmpty)
    }

    func testADueDateOnTheMoveInDayItselfIsAccepted() throws {
        let updated = try useCase.execute(request(dueDate: moveIn), now: moveIn)

        XCTAssertEqual(updated.conditionReportDueDate, moveIn)
    }

    /// The typo check belongs to setup. A tenancy being documented may have begun
    /// months ago, and blocking an address fix because of that would be a bug, not
    /// a rule.
    func testALongRunningTenancyCanStillHaveItsDetailsCorrected() throws {
        let sixMonthsLater = moveIn.addingTimeInterval(180 * 86_400)

        let updated = try useCase.execute(request(), now: sixMonthsLater)

        XCTAssertEqual(updated.propertyAddress, "12A Smith Street, Redfern")
    }

    func testCorrectingATenancyThatIsNoLongerTheActiveOneIsRejected() {
        XCTAssertThrowsError(try useCase.execute(request(tenancyID: UUID()), now: moveIn)) { error in
            XCTAssertEqual(error as? TenancySetupError, .tenancyNoLongerBeingDocumented)
        }
    }

    func testCorrectingDetailsWithNoPropertySetUpIsRejected() {
        tenancyRepository.tenancies = [:]

        XCTAssertThrowsError(try useCase.execute(request(), now: moveIn)) { error in
            XCTAssertEqual(error as? TenancySetupError, .tenancyNoLongerBeingDocumented)
        }
    }

    // MARK: - One implementation of the rules

    /// The setup screen and the edit screen have to apply the same rule, which only
    /// stays true while both go through `TenancyDetailsRules`.
    func testStartingAndCorrectingShareTheSameDueDateRule() {
        let badDetails = TenancyDetails(
            propertyAddress: "12 Smith Street",
            moveInDate: moveIn,
            conditionReportDueDate: moveIn.addingTimeInterval(-86_400)
        )

        for check in [TenancyDetailsRules.BackdatingCheck.enforced, .skipped] {
            XCTAssertThrowsError(
                try TenancyDetailsRules.validate(badDetails, backdatingCheck: check, now: moveIn)
            ) { error in
                XCTAssertEqual(error as? TenancySetupError, .conditionReportDueBeforeMoveIn)
            }
        }
    }

    func testTheBackdatingGuardAppliesOnlyWhenStartingOut() throws {
        let longAgo = Date(timeIntervalSince1970: 1_600_000_000)
        let details = TenancyDetails(propertyAddress: "12 Smith Street", moveInDate: longAgo)
        let now = longAgo.addingTimeInterval(Double(TenancySetupError.maximumBackdatedMoveInDays + 30) * 86_400)

        XCTAssertThrowsError(
            try TenancyDetailsRules.validate(details, backdatingCheck: .enforced, now: now)
        )
        XCTAssertNoThrow(
            try TenancyDetailsRules.validate(details, backdatingCheck: .skipped, now: now)
        )
    }
}
