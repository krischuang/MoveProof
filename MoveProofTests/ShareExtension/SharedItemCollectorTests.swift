import UniformTypeIdentifiers
import XCTest
@testable import MoveProof

/// Exercises the Share Extension's actual attachment handling against real
/// `NSItemProvider`s and the real App Group inbox.
///
/// A share extension cannot be launched from a test, but `SharedItemCollector` is
/// where all of its behaviour lives, and `NSItemProvider` is the same class iOS
/// hands it. So this covers the parts that can genuinely go wrong — which
/// attachments are accepted, which type identifier is recorded, and what actually
/// lands in the inbox — without depending on the share sheet.
@MainActor
final class SharedItemCollectorTests: XCTestCase {

    private var inbox: SharedEvidenceInbox!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipIf(
            AppGroup.containerURL == nil,
            "The App Group container is unavailable, so the inbox hand-off cannot be exercised here."
        )
        inbox = SharedEvidenceInbox()
        try drainInbox()
    }

    override func tearDownWithError() throws {
        try? drainInbox()
        try super.tearDownWithError()
    }

    private func drainInbox() throws {
        for item in (try? inbox.pendingItems()) ?? [] {
            try? inbox.remove(item)
        }
    }

    // MARK: - Fixtures

    /// A one-pixel PNG, so image providers carry genuinely decodable bytes.
    private var pngData: Data {
        Data(base64Encoded: """
        iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
        """)!
    }

    private func provider(
        data: Data,
        typeIdentifier: String,
        suggestedName: String?
    ) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = suggestedName
        provider.registerDataRepresentation(
            forTypeIdentifier: typeIdentifier,
            visibility: .all
        ) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    private func extensionItem(_ providers: [NSItemProvider]) -> NSExtensionItem {
        let item = NSExtensionItem()
        item.attachments = providers
        return item
    }

    // MARK: - What the extension accepts

    func testAnImageAttachmentIsOfferedForSaving() {
        let collector = SharedItemCollector(inputItems: [
            extensionItem([provider(data: pngData, typeIdentifier: UTType.png.identifier, suggestedName: "Kitchen floor")])
        ])

        guard case .ready(let candidates) = collector.initialOutcome else {
            return XCTFail("Expected a ready outcome, got \(collector.initialOutcome)")
        }
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.displayName, "Kitchen floor")
        XCTAssertEqual(
            candidates.first?.typeIdentifier,
            UTType.png.identifier,
            "The concrete type should be recorded, not the generic public.image"
        )
    }

    func testAPDFAttachmentIsOfferedForSaving() {
        let collector = SharedItemCollector(inputItems: [
            extensionItem([provider(data: Data("%PDF-1.4".utf8), typeIdentifier: UTType.pdf.identifier, suggestedName: "Condition report.pdf")])
        ])

        guard case .ready(let candidates) = collector.initialOutcome else {
            return XCTFail("Expected a ready outcome, got \(collector.initialOutcome)")
        }
        XCTAssertEqual(candidates.first?.typeIdentifier, UTType.pdf.identifier)
    }

    func testAVideoAttachmentIsNotOfferedAtAll() {
        let collector = SharedItemCollector(inputItems: [
            extensionItem([provider(data: Data("not a real movie".utf8), typeIdentifier: UTType.movie.identifier, suggestedName: "Walkthrough.mov")])
        ])

        XCTAssertEqual(
            collector.initialOutcome,
            .nothingUsable,
            "The extension should tell the tenant up front rather than accepting something MoveProof can't file"
        )
    }

    func testAMixedShareKeepsTheUsableAttachmentsAndDropsTheRest() {
        let collector = SharedItemCollector(inputItems: [
            extensionItem([
                provider(data: pngData, typeIdentifier: UTType.png.identifier, suggestedName: "Photo"),
                provider(data: Data("x".utf8), typeIdentifier: UTType.movie.identifier, suggestedName: "Clip"),
                provider(data: Data("%PDF".utf8), typeIdentifier: UTType.pdf.identifier, suggestedName: "Report.pdf")
            ])
        ])

        guard case .ready(let candidates) = collector.initialOutcome else {
            return XCTFail("Expected a ready outcome, got \(collector.initialOutcome)")
        }
        XCTAssertEqual(candidates.map(\.displayName), ["Photo", "Report.pdf"])
    }

    func testAnAttachmentWithNoNameIsNamedByKindAndDate() {
        // Photos hands attachments over with no suggested name, so this is the common
        // case rather than an edge case.
        let collector = SharedItemCollector(inputItems: [
            extensionItem([provider(data: pngData, typeIdentifier: UTType.png.identifier, suggestedName: nil)])
        ])

        guard case .ready(let candidates) = collector.initialOutcome else {
            return XCTFail("Expected a ready outcome, got \(collector.initialOutcome)")
        }
        let name = try? XCTUnwrap(candidates.first?.displayName)
        XCTAssertEqual(
            name?.hasPrefix("Photo shared "),
            true,
            "An unnamed photo should still be identifiable in the evidence library, got \(name ?? "nil")"
        )
    }

    func testAnUnnamedPDFIsNamedAsADocument() {
        let itemProvider = provider(data: Data("%PDF".utf8), typeIdentifier: UTType.pdf.identifier, suggestedName: nil)
        let name = SharedItemCollector.displayName(
            for: itemProvider,
            typeIdentifier: UTType.pdf.identifier,
            receivedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
        XCTAssertTrue(name.hasPrefix("Document shared "), "got \(name)")
    }

    func testASuppliedNameIsAlwaysPreferredOverTheGeneratedOne() {
        let itemProvider = provider(data: pngData, typeIdentifier: UTType.png.identifier, suggestedName: "Kitchen floor")
        XCTAssertEqual(
            SharedItemCollector.displayName(for: itemProvider, typeIdentifier: UTType.png.identifier),
            "Kitchen floor"
        )
    }

    func testAnEmptyShareSheetInvocationIsReportedRatherThanCrashing() {
        let collector = SharedItemCollector(inputItems: [])
        XCTAssertEqual(collector.initialOutcome, .nothingUsable)
    }

    // MARK: - What the extension writes

    func testSavingWritesTheFileAndItsMetadataIntoTheAppGroupInbox() async throws {
        let collector = SharedItemCollector(inputItems: [
            extensionItem([provider(data: pngData, typeIdentifier: UTType.png.identifier, suggestedName: "Kitchen floor")])
        ])

        let outcome = await collector.save()

        XCTAssertEqual(outcome, .saved(count: 1))

        let pending = try inbox.pendingItems()
        XCTAssertEqual(pending.count, 1, "The main app should find exactly one item waiting")

        let item = try XCTUnwrap(pending.first)
        XCTAssertEqual(item.originalFileName, "Kitchen floor")
        XCTAssertEqual(item.contentTypeIdentifier, UTType.png.identifier)
        XCTAssertGreaterThan(item.byteCount, 0)

        let payload = try inbox.fileURL(for: item)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: payload.path),
            "The metadata record must be backed by a real file"
        )
        XCTAssertEqual(try Data(contentsOf: payload), pngData, "The bytes should arrive unchanged")
    }

    func testSavingMultipleAttachmentsWritesOneInboxItemEach() async throws {
        let collector = SharedItemCollector(inputItems: [
            extensionItem([
                provider(data: pngData, typeIdentifier: UTType.png.identifier, suggestedName: "Photo one"),
                provider(data: pngData, typeIdentifier: UTType.png.identifier, suggestedName: "Photo two")
            ])
        ])

        let outcome = await collector.save()

        XCTAssertEqual(outcome, .saved(count: 2))
        XCTAssertEqual(try inbox.pendingItems().count, 2)
    }

    func testTheExtensionDoesNotDecideWhetherContentIsUsableAsEvidence() async throws {
        // The collector carries anything structurally acceptable. Classifying it as
        // photograph, document or unusable is the main app's job, so a type the
        // extension passes through can still be refused later by the use case.
        let collector = SharedItemCollector(inputItems: [
            extensionItem([provider(data: Data("TIFF".utf8), typeIdentifier: UTType.tiff.identifier, suggestedName: "Scan.tiff")])
        ])

        let outcome = await collector.save()
        XCTAssertEqual(outcome, .saved(count: 1))

        let item = try XCTUnwrap(try inbox.pendingItems().first)
        XCTAssertEqual(
            item.contentTypeIdentifier,
            UTType.tiff.identifier,
            "The extension records the type it was handed and leaves the judgement to the app"
        )
        XCTAssertNotNil(
            EvidenceKind.forContentType(item.contentTypeIdentifier),
            "public.tiff is one the app does accept — the point is that the app decided, not the extension"
        )
    }

    // MARK: - Inbox contract

    func testItemsComeBackOldestFirstSoTheTenantWorksThroughThemInOrder() throws {
        let first = try inbox.store(
            data: pngData, originalFileName: "First", contentTypeIdentifier: "public.png",
            fileExtension: "png", sourceApplication: nil,
            receivedAt: Date(timeIntervalSince1970: 1_000)
        )
        let second = try inbox.store(
            data: pngData, originalFileName: "Second", contentTypeIdentifier: "public.png",
            fileExtension: "png", sourceApplication: nil,
            receivedAt: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(try inbox.pendingItems().map(\.originalFileName), ["First", "Second"])
        XCTAssertEqual(inbox.pendingCount(), 2)

        try inbox.remove(first)
        XCTAssertEqual(try inbox.pendingItems().map(\.id), [second.id])
    }

    func testAMetadataRecordWithNoFileIsSkippedRatherThanBlockingTheInbox() throws {
        let orphan = try inbox.store(
            data: pngData, originalFileName: "Vanished", contentTypeIdentifier: "public.png",
            fileExtension: "png", sourceApplication: nil
        )
        let healthy = try inbox.store(
            data: pngData, originalFileName: "Still here", contentTypeIdentifier: "public.png",
            fileExtension: "png", sourceApplication: nil
        )

        // Delete the payload but leave the sidecar behind.
        try FileManager.default.removeItem(at: try inbox.fileURL(for: orphan))

        XCTAssertEqual(
            try inbox.pendingItems().map(\.originalFileName),
            ["Still here"],
            "One broken hand-off must not stop the tenant seeing the rest"
        )
        _ = healthy
    }
}
