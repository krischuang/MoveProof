import XCTest
@testable import MoveProof

/// Rules covered for the four edits a tenant can make to the room list: adding,
/// renaming, removing and reopening.
///
/// These four used to be done straight from the view models, so the rules they carry
/// are checked here instead of being implied by the screens.
@MainActor
final class InspectionAreaEditingTests: XCTestCase {

    private var tenancyRepository: MockTenancyRepository!
    private var inspectionRepository: MockInspectionRepository!
    private var evidenceRepository: MockEvidenceRepository!

    private var addArea: AddInspectionAreaUseCase!
    private var renameArea: RenameInspectionAreaUseCase!
    private var removeArea: RemoveInspectionAreaUseCase!
    private var reopenArea: ReopenInspectionAreaUseCase!

    private var tenancy: Tenancy!
    private var kitchen: InspectionArea!

    override func setUp() {
        super.setUp()

        tenancy = Tenancy(
            propertyAddress: "12 Smith Street, Redfern",
            moveInDate: Date(),
            conditionReportDueDate: Date().addingTimeInterval(7 * 86_400)
        )
        kitchen = InspectionArea(name: "Kitchen", displayOrder: 0, tenancyID: tenancy.id)

        tenancyRepository = MockTenancyRepository(tenancies: [tenancy])
        inspectionRepository = MockInspectionRepository(areas: [kitchen])
        evidenceRepository = MockEvidenceRepository()

        addArea = AddInspectionAreaUseCase(
            tenancyRepository: tenancyRepository,
            inspectionRepository: inspectionRepository
        )
        renameArea = RenameInspectionAreaUseCase(inspectionRepository: inspectionRepository)
        removeArea = RemoveInspectionAreaUseCase(
            inspectionRepository: inspectionRepository,
            evidenceRepository: evidenceRepository
        )
        reopenArea = ReopenInspectionAreaUseCase(inspectionRepository: inspectionRepository)
    }

    // MARK: - Adding a room

    func testAddingARoomSeedsItWithTheStandardConditionChecklist() throws {
        let study = try addArea.execute(named: "Study")

        let items = try inspectionRepository.fetchConditionItems(inArea: study.id)
        XCTAssertEqual(items.count, ConditionItem.defaultChecklist.count)
        XCTAssertTrue(items.contains { $0.title == "Walls and ceiling" })
        XCTAssertTrue(items.allSatisfy { $0.conditionState == .notReviewed })
    }

    func testARoomAddedLaterGetsTheSameExtraChecksAsOneSeededAtSetup() throws {
        let bathroom = try addArea.execute(named: "Second bathroom")

        let titles = try inspectionRepository.fetchConditionItems(inArea: bathroom.id).map(\.title)
        XCTAssertTrue(titles.contains("Exhaust fan and mould"))
        XCTAssertTrue(titles.contains("Toilet, shower and taps"))
    }

    func testAddingARoomAppendsItAfterTheRoomsThatAlreadyExist() throws {
        let study = try addArea.execute(named: "Study")
        let garage = try addArea.execute(named: "Garage")

        XCTAssertEqual(study.displayOrder, 1)
        XCTAssertEqual(garage.displayOrder, 2)
        XCTAssertEqual(
            try inspectionRepository.fetchAreas(forTenancy: tenancy.id).map(\.name),
            ["Kitchen", "Study", "Garage"]
        )
    }

    func testAddingARoomTrimsTheNameTheTenantTyped() throws {
        let study = try addArea.execute(named: "  Study  ")

        XCTAssertEqual(study.name, "Study")
    }

    func testAddingARoomWithoutANameIsRejected() {
        XCTAssertThrowsError(try addArea.execute(named: "   ")) { error in
            XCTAssertEqual(error as? InspectionAreaEditError, .roomNameMissing)
        }
    }

    func testAddingASecondRoomWithTheSameNameIsRejectedSoEvidenceStaysUnambiguous() {
        XCTAssertThrowsError(try addArea.execute(named: "Kitchen")) { error in
            XCTAssertEqual(error as? InspectionAreaEditError, .duplicateRoomName(name: "Kitchen"))
        }
    }

    func testDuplicateRoomNamesAreCaughtRegardlessOfCapitalisation() {
        XCTAssertThrowsError(try addArea.execute(named: "kitchen")) { error in
            XCTAssertEqual(error as? InspectionAreaEditError, .duplicateRoomName(name: "kitchen"))
        }
    }

    func testAddingARoomWithNoPropertySetUpIsRejected() {
        tenancyRepository.tenancies = [:]

        XCTAssertThrowsError(try addArea.execute(named: "Study")) { error in
            XCTAssertEqual(error as? InspectionAreaEditError, .noActiveTenancy)
        }
    }

    // MARK: - Renaming a room

    func testRenamingARoomKeepsItsChecklistAndItsPlaceInTheList() throws {
        _ = try addArea.execute(named: "Second bedroom")
        let room = try XCTUnwrap(
            try inspectionRepository.fetchAreas(forTenancy: tenancy.id).first { $0.name == "Second bedroom" }
        )
        let itemsBefore = try inspectionRepository.fetchConditionItems(inArea: room.id).count

        let renamed = try renameArea.execute(
            RenameInspectionAreaUseCase.Request(areaID: room.id, newName: "Study")
        )

        XCTAssertEqual(renamed.name, "Study")
        XCTAssertEqual(renamed.id, room.id)
        XCTAssertEqual(renamed.displayOrder, room.displayOrder)
        XCTAssertEqual(try inspectionRepository.fetchConditionItems(inArea: room.id).count, itemsBefore)
    }

    func testRenamingARoomToABlankNameIsRejected() {
        XCTAssertThrowsError(
            try renameArea.execute(
                RenameInspectionAreaUseCase.Request(areaID: kitchen.id, newName: "  ")
            )
        ) { error in
            XCTAssertEqual(error as? InspectionAreaEditError, .roomNameMissing)
        }
    }

    func testRenamingARoomOntoAnotherRoomsNameIsRejected() throws {
        let study = try addArea.execute(named: "Study")

        XCTAssertThrowsError(
            try renameArea.execute(
                RenameInspectionAreaUseCase.Request(areaID: study.id, newName: "Kitchen")
            )
        ) { error in
            XCTAssertEqual(error as? InspectionAreaEditError, .duplicateRoomName(name: "Kitchen"))
        }
    }

    /// Opening the rename sheet and tapping Save without typing anything should not
    /// count as a clash with itself.
    func testRenamingARoomToTheNameItAlreadyHasChangesNothing() throws {
        let unchanged = try renameArea.execute(
            RenameInspectionAreaUseCase.Request(areaID: kitchen.id, newName: "Kitchen")
        )

        XCTAssertEqual(unchanged.name, "Kitchen")
        XCTAssertTrue(inspectionRepository.savedAreas.isEmpty, "Nothing changed, so nothing should be written")
    }

    func testRenamingARoomThatIsNoLongerInTheWalkthroughIsRejected() {
        XCTAssertThrowsError(
            try renameArea.execute(
                RenameInspectionAreaUseCase.Request(areaID: UUID(), newName: "Study")
            )
        ) { error in
            XCTAssertEqual(error as? InspectionAreaEditError, .inspectionAreaNotFound)
        }
    }

    // MARK: - Removing a room

    func testRemovingARoomTakesItsChecklistWithIt() throws {
        let study = try addArea.execute(named: "Study")

        let outcome = try removeArea.execute(areaID: study.id)

        XCTAssertTrue(outcome.didRemoveRoom)
        XCTAssertNil(try inspectionRepository.fetchArea(id: study.id))
        XCTAssertTrue(try inspectionRepository.fetchConditionItems(inArea: study.id).isEmpty)
    }

    /// The store nullifies the checklist item link instead of cascading to the
    /// evidence, so the photos survive. The tenant still has to be told, because
    /// those photos document nothing until they are filed again.
    func testRemovingARoomReportsHowMuchEvidenceReturnsToTheLibraryUnfiled() throws {
        let study = try addArea.execute(named: "Study")
        let items = try inspectionRepository.fetchConditionItems(inArea: study.id)
        let flooring = try XCTUnwrap(items.first { $0.title == "Flooring" })

        for index in 0..<2 {
            try evidenceRepository.save(
                EvidenceItem(
                    kind: .photograph,
                    storedFileName: "photo-\(index).jpg",
                    displayName: "Study floor \(index)",
                    source: .capturedInApp,
                    conditionItemID: flooring.id,
                    tenancyID: tenancy.id
                )
            )
        }

        let outcome = try removeArea.execute(areaID: study.id)

        XCTAssertTrue(outcome.didRemoveRoom)
        XCTAssertEqual(outcome.detachedEvidenceCount, 2)
    }

    func testRemovingARoomWithNoEvidenceReportsNothingToWorryAbout() throws {
        let study = try addArea.execute(named: "Study")

        let outcome = try removeArea.execute(areaID: study.id)

        XCTAssertEqual(outcome.detachedEvidenceCount, 0)
    }

    func testRemovingARoomThatHasAlreadyGoneIsNotTreatedAsAFailure() throws {
        let outcome = try removeArea.execute(areaID: UUID())

        XCTAssertEqual(outcome, .roomAlreadyGone)
    }

    /// A room that was already gone and a room that will not delete look the same to
    /// the tenant unless the second one is reported, so the storage fault is turned
    /// into a domain refusal instead of being passed through.
    func testRemovingARoomReportsAFriendlyFailureWhenItCannotBeSaved() throws {
        let study = try addArea.execute(named: "Study")
        inspectionRepository.deleteAreaErrorToThrow = RepositoryError.saveFailed(
            underlying: CocoaError(.fileWriteUnknown)
        )

        XCTAssertThrowsError(try removeArea.execute(areaID: study.id)) { error in
            XCTAssertEqual(error as? InspectionAreaEditError, .couldNotRemoveRoom)
        }
        XCTAssertNotNil(
            try? inspectionRepository.fetchArea(id: study.id),
            "The room is still there, which is what the message tells the tenant"
        )
    }

    /// If MoveProof cannot even look the room up it does not know whether there was
    /// one, so it says so rather than reporting a removal that never happened.
    func testARoomThatCannotBeLookedUpIsNotReportedAsAlreadyGone() {
        inspectionRepository.errorToThrow = RepositoryError.fetchFailed(
            underlying: CocoaError(.fileReadUnknown)
        )

        XCTAssertThrowsError(try removeArea.execute(areaID: kitchen.id)) { error in
            XCTAssertEqual(error as? InspectionAreaEditError, .couldNotRemoveRoom)
        }
    }

    /// Whatever went wrong underneath, what reaches the screen is rental vocabulary.
    func testAFailedRoomRemovalIsExplainedInTheTenantsOwnTerms() throws {
        let study = try addArea.execute(named: "Study")
        inspectionRepository.deleteAreaErrorToThrow = RepositoryError.saveFailed(
            underlying: CocoaError(.fileWriteUnknown)
        )

        XCTAssertThrowsError(try removeArea.execute(areaID: study.id)) { error in
            let tenantFacing = error as? TenantFacingError
            XCTAssertNotNil(tenantFacing, "A storage fault must not reach the screen as a RepositoryError")
            XCTAssertTrue(tenantFacing?.whatHappened.contains("room") == true)
            XCTAssertFalse(tenantFacing?.whatToDoNext.isEmpty == true)
        }
    }

    // MARK: - Reopening a room

    func testReopeningCompletedInspectionAreaAllowsFurtherDocumentation() throws {
        var signedOff = kitchen!
        signedOff.inspectionStatus = .complete
        try inspectionRepository.save(signedOff)

        let reopened = try reopenArea.execute(areaID: kitchen.id)

        XCTAssertEqual(reopened.inspectionStatus, .inProgress)
    }

    /// Back to `inProgress`, not `notStarted`. Things have been recorded in this
    /// room, so showing it as untouched would give the wrong count on the dashboard
    /// and the widget.
    func testAReopenedRoomDoesNotLookAsThoughItWasNeverStarted() throws {
        var signedOff = kitchen!
        signedOff.inspectionStatus = .complete
        try inspectionRepository.save(signedOff)

        let reopened = try reopenArea.execute(areaID: kitchen.id)

        XCTAssertNotEqual(reopened.inspectionStatus, .notStarted)
    }

    func testReopeningARoomThatWasNeverSignedOffIsReportedRatherThanSilentlyIgnored() {
        XCTAssertThrowsError(try reopenArea.execute(areaID: kitchen.id)) { error in
            XCTAssertEqual(
                error as? InspectionAreaEditError,
                .roomNotSignedOff(roomName: "Kitchen")
            )
        }
    }

    func testReopeningARoomThatIsNoLongerInTheWalkthroughIsRejected() {
        XCTAssertThrowsError(try reopenArea.execute(areaID: UUID())) { error in
            XCTAssertEqual(error as? InspectionAreaEditError, .inspectionAreaNotFound)
        }
    }
}
