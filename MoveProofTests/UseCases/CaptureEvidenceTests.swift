import XCTest
@testable import MoveProof

/// Rules covered: a photo needs a property to belong to, an empty pick is refused
/// before anything is written, the checklist link is checked before any bytes reach
/// disk, photos cannot cross between properties, and a failed write leaves nothing
/// behind.
@MainActor
final class CaptureEvidenceTests: XCTestCase {

    private var tenancyRepository: MockTenancyRepository!
    private var inspectionRepository: MockInspectionRepository!
    private var evidenceRepository: MockEvidenceRepository!
    private var fileStore: MockEvidenceFileStore!
    private var useCase: CaptureEvidenceUseCase!

    private var tenancy: Tenancy!
    private var area: InspectionArea!
    private var conditionItem: ConditionItem!

    private let photoBytes = Data("a photograph of a scratched floorboard".utf8)

    override func setUp() {
        super.setUp()

        tenancy = Tenancy(
            propertyAddress: "12 Smith Street, Redfern",
            moveInDate: Date(),
            conditionReportDueDate: Date().addingTimeInterval(7 * 86_400)
        )
        area = InspectionArea(name: "Kitchen", displayOrder: 0, tenancyID: tenancy.id)
        conditionItem = ConditionItem(title: "Flooring", category: .structure, inspectionAreaID: area.id)

        tenancyRepository = MockTenancyRepository(tenancies: [tenancy])
        inspectionRepository = MockInspectionRepository(areas: [area], conditionItems: [conditionItem])
        evidenceRepository = MockEvidenceRepository()
        fileStore = MockEvidenceFileStore()

        useCase = CaptureEvidenceUseCase(
            tenancyRepository: tenancyRepository,
            inspectionRepository: inspectionRepository,
            evidenceRepository: evidenceRepository,
            evidenceFileStore: fileStore
        )
    }

    private func request(
        data: Data? = nil,
        name: String = "Kitchen floor.jpg",
        notes: String = "",
        conditionItemID: UUID? = nil
    ) -> CaptureEvidenceUseCase.Request {
        CaptureEvidenceUseCase.Request(
            imageData: data ?? photoBytes,
            displayName: name,
            notes: notes,
            conditionItemID: conditionItemID
        )
    }

    // MARK: - Happy path

    func testCapturingEvidenceStoresPhotoAgainstSelectedCondition() throws {
        let captured = try useCase.execute(request(conditionItemID: conditionItem.id))

        XCTAssertEqual(captured.conditionItemID, conditionItem.id)
        XCTAssertEqual(captured.tenancyID, tenancy.id)
        XCTAssertEqual(captured.kind, .photograph)
        XCTAssertEqual(captured.source, .capturedInApp)
        XCTAssertEqual(evidenceRepository.savedEvidence.count, 1)
        XCTAssertEqual(fileStore.storedFiles[captured.storedFileName], photoBytes)
    }

    func testCapturingEvidenceWithoutAChecklistItemLeavesItInTheLibraryToFileLater() throws {
        let captured = try useCase.execute(request())

        XCTAssertNil(captured.conditionItemID)
        XCTAssertEqual(captured.tenancyID, tenancy.id)
        XCTAssertEqual(
            try evidenceRepository.fetchUnassignedEvidence(forTenancy: tenancy.id).count,
            1
        )
    }

    func testTheTenantsNoteIsTrimmedSoWhitespaceNeverCountsAsADescription() throws {
        let captured = try useCase.execute(request(notes: "   scratch near the oven  \n"))

        XCTAssertEqual(captured.notes, "scratch near the oven")
    }

    func testTheCaptureTimeIsRecordedSoEvidenceCanBeDatedLater() throws {
        let captureMoment = Date(timeIntervalSince1970: 1_700_000_000)

        let captured = try useCase.execute(request(), now: captureMoment)

        XCTAssertEqual(captured.capturedAt, captureMoment)
    }

    // MARK: - Domain rules

    func testCapturingEvidenceWithNoPropertySetUpIsRejected() {
        tenancyRepository.tenancies = [:]

        XCTAssertThrowsError(try useCase.execute(request())) { error in
            XCTAssertEqual(error as? EvidenceCaptureError, .noActiveTenancy)
        }
        XCTAssertTrue(fileStore.storedFiles.isEmpty, "Nothing should be written without a property")
    }

    func testAnEmptyPhotoIsRefusedRatherThanStoredAsAnUnusableFile() {
        XCTAssertThrowsError(try useCase.execute(request(data: Data()))) { error in
            XCTAssertEqual(
                error as? EvidenceCaptureError,
                .emptyPhoto(displayName: "Kitchen floor.jpg")
            )
        }
        XCTAssertTrue(fileStore.storedFiles.isEmpty)
        XCTAssertTrue(evidenceRepository.savedEvidence.isEmpty)
    }

    func testFilingAPhotoAgainstAChecklistItemThatHasBeenRemovedIsRejected() {
        XCTAssertThrowsError(try useCase.execute(request(conditionItemID: UUID()))) { error in
            XCTAssertEqual(error as? EvidenceCaptureError, .conditionItemNoLongerInWalkthrough)
        }
        XCTAssertTrue(fileStore.storedFiles.isEmpty, "The link is checked before any bytes are written")
    }

    func testFilingAPhotoAgainstAnotherPropertysChecklistItemIsRejected() throws {
        let otherArea = InspectionArea(name: "Garage", displayOrder: 0, tenancyID: UUID())
        let otherItem = ConditionItem(title: "Door", category: .fixtures, inspectionAreaID: otherArea.id)
        try inspectionRepository.save(otherArea)
        try inspectionRepository.save(otherItem)

        XCTAssertThrowsError(try useCase.execute(request(conditionItemID: otherItem.id))) { error in
            XCTAssertEqual(error as? EvidenceCaptureError, .evidenceBelongsToAnotherProperty)
        }
        XCTAssertTrue(fileStore.storedFiles.isEmpty)
    }

    // MARK: - Boundary

    func testASinglyByteImageIsAcceptedBecauseOnlyAnEmptyPickIsRefused() throws {
        let captured = try useCase.execute(request(data: Data([0x1])))

        XCTAssertEqual(fileStore.storedFiles[captured.storedFileName]?.count, 1)
    }

    // MARK: - Storage failures are turned into tenant wording

    func testAFailureToStoreThePhotoIsReportedInTenantLanguageNotAsAFileSystemError() {
        fileStore.errorToThrow = CocoaError(.fileWriteOutOfSpace)

        XCTAssertThrowsError(try useCase.execute(request())) { error in
            XCTAssertEqual(
                error as? EvidenceCaptureError,
                .couldNotStorePhoto(displayName: "Kitchen floor.jpg")
            )
        }
    }

    func testAFailedRecordRemovesTheFileSoNoEvidenceIsListedThatCannotBeOpened() {
        evidenceRepository.saveErrorToThrow = RepositoryError.saveFailed(underlying: CocoaError(.fileWriteUnknown))

        XCTAssertThrowsError(try useCase.execute(request())) { error in
            XCTAssertEqual(
                error as? EvidenceCaptureError,
                .couldNotStorePhoto(displayName: "Kitchen floor.jpg")
            )
        }
        XCTAssertEqual(fileStore.removedFileNames.count, 1, "The leftover file should be deleted again")
        XCTAssertTrue(fileStore.storedFiles.isEmpty)
    }

    func testARepositoryFailureReadingTheTenancyDoesNotLeakToTheTenant() {
        tenancyRepository.errorToThrow = RepositoryError.fetchFailed(underlying: CocoaError(.fileReadUnknown))

        XCTAssertThrowsError(try useCase.execute(request())) { error in
            XCTAssertTrue(
                error is EvidenceCaptureError,
                "Storage errors should be converted here, but got \(error)"
            )
        }
    }

    // MARK: - Error wording

    /// Capture used to reuse `SharedEvidenceImportError`, which told the tenant their
    /// own camera roll photo "may have been removed since it was shared". This checks
    /// the capture errors do not drift back into share sheet language.
    func testCaptureErrorsDoNotUseShareSheetWording() {
        let errors: [EvidenceCaptureError] = [
            .noActiveTenancy,
            .emptyPhoto(displayName: "photo.jpg"),
            .conditionItemNoLongerInWalkthrough,
            .evidenceBelongsToAnotherProperty,
            .couldNotStorePhoto(displayName: "photo.jpg")
        ]

        for error in errors {
            XCTAssertFalse(
                error.whatHappened.lowercased().contains("shared"),
                "Capture wording should not borrow the share sheet wording: \(error.whatHappened)"
            )
        }
    }
}
