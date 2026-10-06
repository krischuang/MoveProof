import XCTest
@testable import MoveProof

/// Rules covered: a tenancy must exist, only photos and PDFs are accepted, missing
/// files are reported instead of swallowed, and importing the same inbox item twice
/// is refused.
///
/// The repositories are mocked, but the inbox is the real `SharedEvidenceInbox`
/// writing into the real App Group container. That is on purpose: the inbox *is*
/// the contract between the Share Extension and the app, and a mocked version would
/// prove nothing about whether the two processes can actually hand files over.
@MainActor
final class ImportSharedEvidenceTests: XCTestCase {

    private var tenancyRepository: MockTenancyRepository!
    private var evidenceRepository: MockEvidenceRepository!
    private var fileStore: MockEvidenceFileStore!
    private var inbox: SharedEvidenceInbox!
    private var useCase: ImportSharedEvidenceUseCase!

    private var tenancy: Tenancy!
    private var writtenItems: [PendingSharedEvidence] = []

    override func setUpWithError() throws {
        try super.setUpWithError()

        try XCTSkipIf(
            AppGroup.containerURL == nil,
            "The App Group container is unavailable, so the Share Extension hand-off cannot be exercised here."
        )

        tenancy = Tenancy(
            propertyAddress: "12 Harris Street, Ultimo NSW 2007",
            moveInDate: Date(),
            conditionReportDueDate: Date().addingTimeInterval(7 * 86_400)
        )
        tenancyRepository = MockTenancyRepository(tenancies: [tenancy])
        evidenceRepository = MockEvidenceRepository()
        fileStore = MockEvidenceFileStore()
        inbox = SharedEvidenceInbox()
        useCase = ImportSharedEvidenceUseCase(
            tenancyRepository: tenancyRepository,
            evidenceRepository: evidenceRepository,
            evidenceFileStore: fileStore,
            inbox: inbox
        )

        try drainInbox()
    }

    override func tearDownWithError() throws {
        try? drainInbox()
        writtenItems = []
        try super.tearDownWithError()
    }

    private func drainInbox() throws {
        for item in (try? inbox.pendingItems()) ?? [] {
            try? inbox.remove(item)
        }
    }

    /// Writes a file into the inbox the same way the Share Extension does.
    @discardableResult
    private func shareFile(
        named name: String,
        contentType: String,
        fileExtension: String,
        bytes: Data = Data("condition report".utf8)
    ) throws -> PendingSharedEvidence {
        let item = try inbox.store(
            data: bytes,
            originalFileName: name,
            contentTypeIdentifier: contentType,
            fileExtension: fileExtension,
            sourceApplication: nil
        )
        writtenItems.append(item)
        return item
    }

    // MARK: - Happy path

    func testASharedPDFIsImportedAsDocumentEvidenceForTheActiveTenancy() throws {
        let shared = try shareFile(
            named: "Signed condition report.pdf",
            contentType: "com.adobe.pdf",
            fileExtension: "pdf"
        )

        let evidence = try useCase.execute(.init(item: shared))

        XCTAssertEqual(evidence.kind, .document)
        XCTAssertEqual(evidence.displayName, "Signed condition report.pdf")
        XCTAssertEqual(evidence.source, .sharedFromAnotherApp)
        XCTAssertEqual(evidence.tenancyID, tenancy.id)
        XCTAssertEqual(
            evidence.importedInboxItemID,
            shared.id,
            "The originating inbox item must be recorded, because that is what makes import idempotent"
        )
        XCTAssertTrue(fileStore.fileExists(named: evidence.storedFileName))
    }

    func testASharedPhotoIsImportedAsPhotographEvidence() throws {
        let shared = try shareFile(
            named: "Kitchen floor.jpg",
            contentType: "public.jpeg",
            fileExtension: "jpg"
        )

        let evidence = try useCase.execute(.init(item: shared))
        XCTAssertEqual(evidence.kind, .photograph)
    }

    func testAnImportedItemIsRemovedFromTheInbox() throws {
        let shared = try shareFile(named: "Kitchen floor.jpg", contentType: "public.jpeg", fileExtension: "jpg")
        XCTAssertEqual(try inbox.pendingItems().count, 1)

        try useCase.execute(.init(item: shared))

        XCTAssertTrue(
            try inbox.pendingItems().isEmpty,
            "The inbox should only be drained once the evidence is committed"
        )
    }

    func testEvidenceCanBeFiledAgainstAChecklistItemDuringImport() throws {
        let shared = try shareFile(named: "Oven.jpg", contentType: "public.jpeg", fileExtension: "jpg")
        let conditionItemID = UUID()

        let evidence = try useCase.execute(.init(item: shared, conditionItemID: conditionItemID))
        XCTAssertEqual(evidence.conditionItemID, conditionItemID)
    }

    // MARK: - Error cases

    func testImportingWithNoActiveTenancyIsRejected() throws {
        tenancyRepository.tenancies = [:]
        let shared = try shareFile(named: "Kitchen floor.jpg", contentType: "public.jpeg", fileExtension: "jpg")

        XCTAssertThrowsError(try useCase.execute(.init(item: shared))) { error in
            XCTAssertEqual(error as? SharedEvidenceImportError, .noActiveTenancy)
            XCTAssertTrue(
                (error as? TenantFacingError)?.whatToDoNext.contains("Set up your property first") == true
            )
        }

        XCTAssertEqual(
            try inbox.pendingItems().count,
            1,
            "A refused import must leave the file in the inbox so the tenant can retry after setting up"
        )
    }

    func testUnsupportedSharedContentIsRejectedWithAnExplanation() throws {
        let shared = try shareFile(
            named: "Walkthrough.mov",
            contentType: "public.movie",
            fileExtension: "mov"
        )

        XCTAssertThrowsError(try useCase.execute(.init(item: shared))) { error in
            XCTAssertEqual(
                error as? SharedEvidenceImportError,
                .unsupportedSharedContent(contentTypeIdentifier: "public.movie")
            )
            let tenantFacing = error as? TenantFacingError
            XCTAssertTrue(
                tenantFacing?.whatHappened.contains("video") == true,
                "The tenant should read 'video', not a Uniform Type Identifier"
            )
            XCTAssertTrue(tenantFacing?.whatToDoNext.contains("screenshot") == true)
        }
    }

    func testTheSameSharedItemCannotBeImportedTwice() throws {
        let shared = try shareFile(named: "Kitchen floor.jpg", contentType: "public.jpeg", fileExtension: "jpg")
        try useCase.execute(.init(item: shared))

        // The tenant taps Import again on a stale row.
        XCTAssertThrowsError(try useCase.execute(.init(item: shared))) { error in
            XCTAssertEqual(
                error as? SharedEvidenceImportError,
                .duplicateEvidence(displayName: "Kitchen floor.jpg")
            )
        }

        XCTAssertEqual(
            evidenceRepository.savedEvidence.count,
            1,
            "Re-importing must not create a second copy of the same evidence"
        )
    }

    func testASharedItemWhoseFileHasVanishedIsReportedNotSilentlySkipped() throws {
        let shared = try shareFile(named: "Kitchen floor.jpg", contentType: "public.jpeg", fileExtension: "jpg")
        // Simulate the payload disappearing while the metadata record survives.
        try FileManager.default.removeItem(at: try inbox.fileURL(for: shared))

        XCTAssertThrowsError(try useCase.execute(.init(item: shared))) { error in
            XCTAssertEqual(
                error as? SharedEvidenceImportError,
                .sharedItemUnavailable(displayName: "Kitchen floor.jpg")
            )
        }
    }

    func testAFailedEvidenceSaveDoesNotLeaveTheFileBehind() throws {
        let shared = try shareFile(named: "Kitchen floor.jpg", contentType: "public.jpeg", fileExtension: "jpg")
        // Only the write fails: the duplicate check still has to succeed, otherwise
        // the use case would give up before it ever adopted a file.
        evidenceRepository.saveErrorToThrow = RepositoryError.saveFailed(
            underlying: NSError(domain: "test", code: 1)
        )

        XCTAssertThrowsError(try useCase.execute(.init(item: shared))) { error in
            XCTAssertEqual(
                error as? SharedEvidenceImportError,
                .couldNotFileSharedItem(displayName: "Kitchen floor.jpg"),
                "A storage fault must reach the tenant as a shared-import failure, not a RepositoryError"
            )
        }

        XCTAssertEqual(
            fileStore.adoptedSourceURLs.count,
            1,
            "The file should have been adopted before the save was attempted"
        )
        XCTAssertEqual(
            fileStore.removedFileNames.count,
            1,
            "A failed save must delete the copied file instead of orphaning it on disk"
        )
        XCTAssertTrue(fileStore.storedFiles.isEmpty, "Nothing should be left in evidence storage")
        XCTAssertEqual(
            try inbox.pendingItems().count,
            1,
            "The inbox item must survive a failed import so the tenant can try again"
        )
    }

    // MARK: - Discarding

    func testDiscardingAnItemRemovesItWithoutFilingEvidence() throws {
        let shared = try shareFile(named: "Kitchen floor.jpg", contentType: "public.jpeg", fileExtension: "jpg")

        try useCase.discard(shared)

        XCTAssertTrue(try inbox.pendingItems().isEmpty)
        XCTAssertTrue(evidenceRepository.savedEvidence.isEmpty)
    }
}
