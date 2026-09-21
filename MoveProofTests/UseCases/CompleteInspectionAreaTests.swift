import XCTest
@testable import MoveProof

/// Rules covered: unreviewed required items block sign-off, undocumented damage
/// blocks sign-off, optional items do not block it, and a room is not signed off twice.
final class CompleteInspectionAreaTests: XCTestCase {

    private var inspectionRepository: MockInspectionRepository!
    private var evidenceRepository: MockEvidenceRepository!
    private var useCase: CompleteInspectionAreaUseCase!

    private let tenancyID = UUID()
    private var area: InspectionArea!

    override func setUp() {
        super.setUp()
        area = InspectionArea(name: "Bathroom", inspectionStatus: .inProgress, displayOrder: 0, tenancyID: tenancyID)
        inspectionRepository = MockInspectionRepository(areas: [area])
        evidenceRepository = MockEvidenceRepository()
        useCase = CompleteInspectionAreaUseCase(
            inspectionRepository: inspectionRepository,
            evidenceRepository: evidenceRepository
        )
    }

    private func addItem(
        _ title: String,
        state: ConditionState,
        notes: String = "",
        required: Bool = true
    ) throws -> ConditionItem {
        let item = ConditionItem(
            title: title,
            category: .fixtures,
            conditionState: state,
            notes: notes,
            reviewedAt: state == .notReviewed ? nil : Date(),
            isRequired: required,
            inspectionAreaID: area.id
        )
        try inspectionRepository.save(item)
        return item
    }

    // MARK: - Happy path

    func testARoomCanBeSignedOffOnceEveryRequiredItemIsReviewed() throws {
        _ = try addItem("Walls and ceiling", state: .undamaged)
        _ = try addItem("Flooring", state: .minorWear)
        _ = try addItem("Toilet, shower and taps", state: .undamaged)

        let completed = try useCase.execute(areaID: area.id)

        XCTAssertEqual(completed.inspectionStatus, .complete)
        let stored = try XCTUnwrap(inspectionRepository.fetchArea(id: area.id))
        XCTAssertEqual(stored.inspectionStatus, .complete)
    }

    func testARoomWithDocumentedDamageCanBeSignedOff() throws {
        _ = try addItem("Walls and ceiling", state: .undamaged)
        _ = try addItem("Exhaust fan and mould", state: .damaged, notes: "Black mould around the vent.")

        let completed = try useCase.execute(areaID: area.id)
        XCTAssertEqual(completed.inspectionStatus, .complete)
    }

    func testDamageBackedByAPhotoRatherThanANoteStillAllowsSignOff() throws {
        _ = try addItem("Walls and ceiling", state: .undamaged)
        let fan = try addItem("Exhaust fan and mould", state: .damaged, notes: "")
        try evidenceRepository.save(
            EvidenceItem(
                kind: .photograph,
                storedFileName: "mould.jpg",
                displayName: "Bathroom vent",
                source: .capturedInApp,
                conditionItemID: fan.id,
                tenancyID: tenancyID
            )
        )

        let completed = try useCase.execute(areaID: area.id)
        XCTAssertEqual(completed.inspectionStatus, .complete)
    }

    // MARK: - Blocked sign-off

    func testARoomCannotBeSignedOffWhileRequiredItemsRemainUnreviewed() throws {
        _ = try addItem("Walls and ceiling", state: .undamaged)
        _ = try addItem("Flooring", state: .notReviewed)
        _ = try addItem("Doors and locks", state: .notReviewed)

        XCTAssertThrowsError(try useCase.execute(areaID: area.id)) { error in
            guard case .uncheckedConditionItemsRemain(let count, let firstTitle)? = error as? InspectionCompletionError else {
                return XCTFail("Expected unchecked items, got \(error)")
            }
            XCTAssertEqual(count, 2)
            XCTAssertTrue(["Flooring", "Doors and locks"].contains(firstTitle))
            XCTAssertTrue(
                (error as? TenantFacingError)?.whatHappened.contains("2 checklist items") == true,
                "The tenant should be told how many are left, not just that something is missing"
            )
        }

        let stored = try XCTUnwrap(inspectionRepository.fetchArea(id: area.id))
        XCTAssertEqual(stored.inspectionStatus, .inProgress, "A blocked sign-off must not change the room")
    }

    func testARoomCannotBeSignedOffWhileDamageHasNoPhotoOrNote() throws {
        _ = try addItem("Walls and ceiling", state: .undamaged)
        // Reviewed, so rule 3 passes — but undocumented, so rule 4 must catch it.
        _ = try addItem("Exhaust fan and mould", state: .damaged, notes: "")

        XCTAssertThrowsError(try useCase.execute(areaID: area.id)) { error in
            XCTAssertEqual(
                error as? InspectionCompletionError,
                .undocumentedDamageRemains(count: 1),
                "Sign-off must re-check documentation, because evidence can be deleted after recording"
            )
        }
    }

    // MARK: - Boundary cases

    func testOptionalItemsDoNotBlockSignOff() throws {
        _ = try addItem("Walls and ceiling", state: .undamaged)
        _ = try addItem("Spare key drawer", state: .notReviewed, required: false)

        let completed = try useCase.execute(areaID: area.id)
        XCTAssertEqual(
            completed.inspectionStatus,
            .complete,
            "Only required checklist items should hold up a room"
        )
    }

    func testAnEmptyRoomCanBeSignedOff() throws {
        let completed = try useCase.execute(areaID: area.id)
        XCTAssertEqual(
            completed.inspectionStatus,
            .complete,
            "A room the tenant has removed every item from has nothing left to check"
        )
    }

    // MARK: - Error cases

    func testSigningOffARoomThatIsAlreadyCompleteIsRejected() throws {
        var complete = area!
        complete.inspectionStatus = .complete
        try inspectionRepository.save(complete)

        XCTAssertThrowsError(try useCase.execute(areaID: area.id)) { error in
            XCTAssertEqual(
                error as? InspectionCompletionError,
                .inspectionAlreadyComplete(areaName: "Bathroom")
            )
        }
    }

    func testSigningOffARoomThatNoLongerExistsIsRejected() {
        XCTAssertThrowsError(try useCase.execute(areaID: UUID())) { error in
            XCTAssertEqual(error as? InspectionCompletionError, .inspectionAreaNotFound)
        }
    }
}
