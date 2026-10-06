import XCTest
@testable import MoveProof

/// Rules covered for what a tenant does with evidence once it is in MoveProof:
/// filing it against a checklist item, writing what it shows, and discarding it.
@MainActor
final class EvidenceFilingTests: XCTestCase {

    private var inspectionRepository: MockInspectionRepository!
    private var evidenceRepository: MockEvidenceRepository!
    private var fileStore: MockEvidenceFileStore!

    private var fileEvidence: FileEvidenceUseCase!
    private var discardEvidence: DiscardEvidenceUseCase!

    private let tenancyID = UUID()
    private var area: InspectionArea!
    private var flooring: ConditionItem!
    private var evidence: EvidenceItem!

    override func setUp() {
        super.setUp()

        area = InspectionArea(name: "Kitchen", displayOrder: 0, tenancyID: tenancyID)
        flooring = ConditionItem(title: "Flooring", category: .structure, inspectionAreaID: area.id)
        evidence = EvidenceItem(
            kind: .photograph,
            storedFileName: "kitchen-floor.jpg",
            displayName: "Kitchen floor.jpg",
            source: .capturedInApp,
            tenancyID: tenancyID
        )

        inspectionRepository = MockInspectionRepository(areas: [area], conditionItems: [flooring])
        evidenceRepository = MockEvidenceRepository(evidence: [evidence])
        fileStore = MockEvidenceFileStore()

        fileEvidence = FileEvidenceUseCase(
            inspectionRepository: inspectionRepository,
            evidenceRepository: evidenceRepository
        )
        discardEvidence = DiscardEvidenceUseCase(
            inspectionRepository: inspectionRepository,
            evidenceRepository: evidenceRepository,
            evidenceFileStore: fileStore
        )
    }

    private func filingRequest(
        evidenceID: UUID? = nil,
        conditionItemID: UUID?,
        notes: String = ""
    ) -> FileEvidenceUseCase.Request {
        FileEvidenceUseCase.Request(
            evidenceID: evidenceID ?? evidence.id,
            conditionItemID: conditionItemID,
            notes: notes
        )
    }

    // MARK: - Filing evidence

    func testFilingEvidenceAgainstAChecklistItemMakesThatDamageDocumented() throws {
        let filed = try fileEvidence.execute(
            filingRequest(conditionItemID: flooring.id, notes: "scratch under the fridge")
        )

        XCTAssertEqual(filed.conditionItemID, flooring.id)
        XCTAssertEqual(filed.notes, "scratch under the fridge")
        XCTAssertEqual(try evidenceRepository.evidenceCount(forConditionItem: flooring.id), 1)
    }

    /// Where the evidence belongs and what it shows are one operation, so a single
    /// call applies both instead of two separate writes.
    func testFilingAndTheNoteAreAppliedTogetherInOneWrite() throws {
        try fileEvidence.execute(
            filingRequest(conditionItemID: flooring.id, notes: "scratch under the fridge")
        )

        XCTAssertEqual(evidenceRepository.savedEvidence.count, 1)
    }

    func testTheNoteIsTrimmedSoWhitespaceNeverCountsAsADescriptionOfDamage() throws {
        let filed = try fileEvidence.execute(
            filingRequest(conditionItemID: flooring.id, notes: "   \n  ")
        )

        XCTAssertTrue(filed.notes.isEmpty)
    }

    func testEvidenceCanBeReturnedToTheLibraryToFileSomewhereElseLater() throws {
        try fileEvidence.execute(filingRequest(conditionItemID: flooring.id))

        let unfiled = try fileEvidence.execute(filingRequest(conditionItemID: nil))

        XCTAssertNil(unfiled.conditionItemID)
        XCTAssertEqual(try evidenceRepository.fetchUnassignedEvidence(forTenancy: tenancyID).count, 1)
    }

    func testFilingEvidenceThatIsNoLongerInTheLibraryIsRejected() {
        XCTAssertThrowsError(
            try fileEvidence.execute(filingRequest(evidenceID: UUID(), conditionItemID: flooring.id))
        ) { error in
            XCTAssertEqual(error as? EvidenceFilingError, .evidenceNoLongerInLibrary)
        }
    }

    func testFilingEvidenceAgainstARemovedChecklistItemIsRejected() {
        XCTAssertThrowsError(
            try fileEvidence.execute(filingRequest(conditionItemID: UUID()))
        ) { error in
            XCTAssertEqual(error as? EvidenceFilingError, .conditionItemNoLongerInWalkthrough)
        }
        XCTAssertTrue(evidenceRepository.savedEvidence.isEmpty, "Rules are checked before the write")
    }

    func testEvidenceCannotBeMovedOntoAnotherPropertysChecklistItem() throws {
        let otherArea = InspectionArea(name: "Garage", displayOrder: 0, tenancyID: UUID())
        let otherItem = ConditionItem(title: "Door", category: .fixtures, inspectionAreaID: otherArea.id)
        try inspectionRepository.save(otherArea)
        try inspectionRepository.save(otherItem)

        XCTAssertThrowsError(
            try fileEvidence.execute(filingRequest(conditionItemID: otherItem.id))
        ) { error in
            XCTAssertEqual(error as? EvidenceFilingError, .conditionItemBelongsToAnotherProperty)
        }
    }

    // MARK: - Discarding evidence

    func testDiscardingEvidenceRemovesBothTheRecordAndTheFileBehindIt() throws {
        _ = try fileStore.store(data: Data("bytes".utf8), preferredExtension: "jpg")
        let evidenceWithFile = EvidenceItem(
            kind: .photograph,
            storedFileName: "kitchen-floor.jpg",
            displayName: "Kitchen floor.jpg",
            source: .capturedInApp,
            tenancyID: tenancyID
        )
        try evidenceRepository.save(evidenceWithFile)

        try discardEvidence.execute(evidenceID: evidenceWithFile.id)

        XCTAssertNil(try evidenceRepository.fetchEvidence(id: evidenceWithFile.id))
        XCTAssertEqual(fileStore.removedFileNames, ["kitchen-floor.jpg"])
    }

    func testDiscardingEvidenceThatIsAlreadyGoneIsNotTreatedAsAFailure() throws {
        let outcome = try discardEvidence.execute(evidenceID: UUID())

        XCTAssertEqual(outcome, .nothingToReport)
        XCTAssertTrue(evidenceRepository.deletedEvidenceIDs.isEmpty)
    }

    /// The gap the app is built to prevent: damage recorded with nothing left to
    /// show for it. Discarding is still allowed, but the tenant is warned.
    func testDiscardingTheLastPhotoBackingDamageIsReportedToTheTenant() throws {
        var damaged = flooring!
        damaged.conditionState = .damaged
        damaged.reviewedAt = Date()
        try inspectionRepository.save(damaged)

        var filed = evidence!
        filed.conditionItemID = damaged.id
        try evidenceRepository.save(filed)

        let outcome = try discardEvidence.execute(evidenceID: filed.id)

        XCTAssertEqual(outcome.leftDamageUndocumented, "Flooring")
    }

    func testDiscardingOneOfSeveralPhotosLeavesTheDamageStillDocumented() throws {
        var damaged = flooring!
        damaged.conditionState = .damaged
        damaged.reviewedAt = Date()
        try inspectionRepository.save(damaged)

        var first = evidence!
        first.conditionItemID = damaged.id
        try evidenceRepository.save(first)

        let second = EvidenceItem(
            kind: .photograph,
            storedFileName: "kitchen-floor-2.jpg",
            displayName: "Kitchen floor 2.jpg",
            source: .capturedInApp,
            conditionItemID: damaged.id,
            tenancyID: tenancyID
        )
        try evidenceRepository.save(second)

        let outcome = try discardEvidence.execute(evidenceID: first.id)

        XCTAssertNil(outcome.leftDamageUndocumented)
    }

    /// A written note counts as backing up on its own, so losing the photo does not
    /// leave the item undocumented.
    func testDiscardingAPhotoFromADamagedItemThatAlsoHasANoteIsNotReported() throws {
        var damaged = flooring!
        damaged.conditionState = .damaged
        damaged.notes = "deep scratch under the fridge"
        damaged.reviewedAt = Date()
        try inspectionRepository.save(damaged)

        var filed = evidence!
        filed.conditionItemID = damaged.id
        try evidenceRepository.save(filed)

        let outcome = try discardEvidence.execute(evidenceID: filed.id)

        XCTAssertNil(outcome.leftDamageUndocumented)
    }

    /// Discarding something that has already gone is a normal outcome; a record that
    /// refuses to go is not, because the tenant asked for it and it is still there.
    func testDiscardingEvidenceReportsAFriendlyFailureWhenItCannotBeRemoved() {
        evidenceRepository.deleteErrorToThrow = RepositoryError.saveFailed(
            underlying: CocoaError(.fileWriteUnknown)
        )

        XCTAssertThrowsError(try discardEvidence.execute(evidenceID: evidence.id)) { error in
            XCTAssertEqual(error as? EvidenceFilingError, .couldNotDiscardEvidence)
        }
        XCTAssertNotNil(
            try? evidenceRepository.fetchEvidence(id: evidence.id),
            "The evidence is still in the library, which is what the message says"
        )
    }

    func testAFailedDiscardIsExplainedInTheTenantsOwnTerms() {
        evidenceRepository.deleteErrorToThrow = RepositoryError.saveFailed(
            underlying: CocoaError(.fileWriteUnknown)
        )

        XCTAssertThrowsError(try discardEvidence.execute(evidenceID: evidence.id)) { error in
            let tenantFacing = error as? TenantFacingError
            XCTAssertNotNil(tenantFacing, "A storage fault must not reach the screen as a RepositoryError")
            XCTAssertTrue(tenantFacing?.whatHappened.contains("evidence library") == true)
            XCTAssertFalse(tenantFacing?.whatToDoNext.isEmpty == true)
        }
    }

    /// The file is gone, which is what the tenant asked for, so a lookup that fails
    /// afterwards costs the warning rather than turning a success into a failure.
    func testADiscardThatSucceedsIsNotReportedAsAFailureWhenTheWarningCannotBeWorkedOut() throws {
        var damaged = flooring!
        damaged.conditionState = .damaged
        damaged.reviewedAt = Date()
        try inspectionRepository.save(damaged)

        var filed = evidence!
        filed.conditionItemID = damaged.id
        try evidenceRepository.save(filed)

        inspectionRepository.errorToThrow = RepositoryError.fetchFailed(
            underlying: CocoaError(.fileReadUnknown)
        )

        let outcome = try discardEvidence.execute(evidenceID: filed.id)

        XCTAssertNil(outcome.leftDamageUndocumented)
        XCTAssertNil(try evidenceRepository.fetchEvidence(id: filed.id), "The discard still happened")
    }

    func testDiscardingAPhotoFromAnUndamagedItemReportsNothing() throws {
        var undamaged = flooring!
        undamaged.conditionState = .undamaged
        undamaged.reviewedAt = Date()
        try inspectionRepository.save(undamaged)

        var filed = evidence!
        filed.conditionItemID = undamaged.id
        try evidenceRepository.save(filed)

        let outcome = try discardEvidence.execute(evidenceID: filed.id)

        XCTAssertNil(outcome.leftDamageUndocumented)
    }
}
