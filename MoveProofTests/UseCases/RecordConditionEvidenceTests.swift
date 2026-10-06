import XCTest
@testable import MoveProof

/// Rules covered: the damage-needs-backing-up rule and its boundaries, condition
/// must be chosen, cross-property evidence is refused, and recording advances the
/// room's status.
@MainActor
final class RecordConditionEvidenceTests: XCTestCase {

    private var inspectionRepository: MockInspectionRepository!
    private var evidenceRepository: MockEvidenceRepository!
    private var useCase: RecordConditionEvidenceUseCase!

    private let tenancyID = UUID()
    private var area: InspectionArea!
    private var flooring: ConditionItem!

    private let referenceDate = Date(timeIntervalSince1970: 1_780_000_000)

    override func setUp() {
        super.setUp()
        area = InspectionArea(name: "Kitchen", displayOrder: 0, tenancyID: tenancyID)
        flooring = ConditionItem(title: "Flooring", category: .structure, inspectionAreaID: area.id)

        inspectionRepository = MockInspectionRepository(areas: [area], conditionItems: [flooring])
        evidenceRepository = MockEvidenceRepository()
        useCase = RecordConditionEvidenceUseCase(
            inspectionRepository: inspectionRepository,
            evidenceRepository: evidenceRepository
        )
    }

    // MARK: - Happy path

    func testAnUndamagedItemCanBeRecordedWithoutAPhotoOrNote() throws {
        let recorded = try useCase.execute(
            .init(conditionItemID: flooring.id, conditionState: .undamaged, notes: ""),
            now: referenceDate
        )

        XCTAssertEqual(recorded.conditionState, .undamaged)
        XCTAssertEqual(recorded.reviewedAt, referenceDate)
        XCTAssertTrue(recorded.isReviewed)
    }

    func testDamageRecordedWithANoteIsAccepted() throws {
        let recorded = try useCase.execute(
            .init(
                conditionItemID: flooring.id,
                conditionState: .damaged,
                notes: "Deep scratch across the vinyl near the oven."
            ),
            now: referenceDate
        )

        XCTAssertEqual(recorded.conditionState, .damaged)
        XCTAssertEqual(recorded.notes, "Deep scratch across the vinyl near the oven.")
        XCTAssertTrue(recorded.isFullyDocumented(evidenceCount: 0))
    }

    func testDamageRecordedWithAPhotoButNoNoteIsAccepted() throws {
        let photo = EvidenceItem(
            kind: .photograph,
            storedFileName: "scratch.jpg",
            displayName: "Kitchen floor",
            source: .capturedInApp,
            tenancyID: tenancyID
        )

        let recorded = try useCase.execute(
            .init(
                conditionItemID: flooring.id,
                conditionState: .damaged,
                notes: "",
                evidenceToAttach: [photo]
            ),
            now: referenceDate
        )

        XCTAssertEqual(recorded.conditionState, .damaged)
        XCTAssertEqual(
            evidenceRepository.savedEvidence.first?.conditionItemID,
            flooring.id,
            "Attached evidence should be filed against the item it backs up"
        )
    }

    func testRecordingAnItemMovesTheRoomFromNotStartedToInProgress() throws {
        XCTAssertEqual(area.inspectionStatus, .notStarted)

        try useCase.execute(
            .init(conditionItemID: flooring.id, conditionState: .undamaged, notes: ""),
            now: referenceDate
        )

        let updated = try XCTUnwrap(inspectionRepository.fetchArea(id: area.id))
        XCTAssertEqual(updated.inspectionStatus, .inProgress)
    }

    // MARK: - The central rule

    func testDamagedConditionWithNeitherNoteNorPhotoIsRejected() {
        XCTAssertThrowsError(
            try useCase.execute(
                .init(conditionItemID: flooring.id, conditionState: .damaged, notes: ""),
                now: referenceDate
            )
        ) { error in
            XCTAssertEqual(
                error as? ConditionRecordingError,
                .damagedConditionNeedsSupportingDetail(itemTitle: "Flooring")
            )
            let tenantFacing = error as? TenantFacingError
            XCTAssertTrue(
                tenantFacing?.whatToDoNext.contains("photo or write a short note") == true,
                "The message should say what will unblock this, in the tenant's words"
            )
        }

        XCTAssertTrue(
            inspectionRepository.savedConditionItems.isEmpty,
            "A refused record must not be written, even partially"
        )
    }

    func testNotWorkingWithNeitherNoteNorPhotoIsAlsoRejected() {
        XCTAssertThrowsError(
            try useCase.execute(
                .init(conditionItemID: flooring.id, conditionState: .notWorking, notes: "   "),
                now: referenceDate
            )
        ) { error in
            XCTAssertEqual(
                error as? ConditionRecordingError,
                .damagedConditionNeedsSupportingDetail(itemTitle: "Flooring"),
                "Whitespace is not a note"
            )
        }
    }

    func testMinorWearDoesNotRequireSupportingDetail() throws {
        let recorded = try useCase.execute(
            .init(conditionItemID: flooring.id, conditionState: .minorWear, notes: ""),
            now: referenceDate
        )
        XCTAssertEqual(
            recorded.conditionState,
            .minorWear,
            "Only damage and faults need backing up; ordinary wear should not slow the tenant down"
        )
    }

    func testEvidenceAlreadyFiledAgainstTheItemSatisfiesTheRuleOnResave() throws {
        // Evidence attached during an earlier recording.
        try evidenceRepository.save(
            EvidenceItem(
                kind: .photograph,
                storedFileName: "scratch.jpg",
                displayName: "Kitchen floor",
                source: .capturedInApp,
                conditionItemID: flooring.id,
                tenancyID: tenancyID
            )
        )

        let recorded = try useCase.execute(
            .init(conditionItemID: flooring.id, conditionState: .damaged, notes: ""),
            now: referenceDate
        )

        XCTAssertEqual(
            recorded.conditionState,
            .damaged,
            "Re-saving an item that already has a photo must not fail the rule a second time"
        )
    }

    // MARK: - Other error cases

    func testRecordingAgainstAMissingChecklistItemIsRejected() {
        XCTAssertThrowsError(
            try useCase.execute(
                .init(conditionItemID: UUID(), conditionState: .undamaged, notes: ""),
                now: referenceDate
            )
        ) { error in
            XCTAssertEqual(error as? ConditionRecordingError, .conditionItemNotFound)
        }
    }

    func testNotChoosingAConditionIsRejected() {
        XCTAssertThrowsError(
            try useCase.execute(
                .init(conditionItemID: flooring.id, conditionState: .notReviewed, notes: "Looks fine"),
                now: referenceDate
            )
        ) { error in
            XCTAssertEqual(error as? ConditionRecordingError, .conditionStateNotChosen)
        }
    }

    func testEvidenceFromAnotherPropertyCannotBeAttached() {
        let otherProperty = EvidenceItem(
            kind: .photograph,
            storedFileName: "elsewhere.jpg",
            displayName: "Old flat",
            source: .capturedInApp,
            tenancyID: UUID()
        )

        XCTAssertThrowsError(
            try useCase.execute(
                .init(
                    conditionItemID: flooring.id,
                    conditionState: .damaged,
                    notes: "",
                    evidenceToAttach: [otherProperty]
                ),
                now: referenceDate
            )
        ) { error in
            XCTAssertEqual(error as? ConditionRecordingError, .evidenceBelongsToAnotherTenancy)
        }

        XCTAssertTrue(
            evidenceRepository.savedEvidence.isEmpty,
            "Provenance must be checked before anything is written"
        )
    }
}
