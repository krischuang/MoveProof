import SwiftUI
import XCTest
@testable import MoveProof

/// Covers the widget's half of the App Group contract, and renders both supported
/// families so a layout that would come out blank on the Home Screen fails here
/// instead.
///
/// The widget extension and the app are separate processes, so nothing here can run
/// the widget for real. What it can do is exercise the same store the widget reads,
/// and render the same views the widget renders, which is where layout mistakes
/// actually live.
@MainActor
final class WidgetSnapshotTests: XCTestCase {

    private var store: InspectionSnapshotStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipIf(
            AppGroup.containerURL == nil,
            "The App Group container is unavailable, so widget shared storage cannot be exercised here."
        )
        store = InspectionSnapshotStore()
    }

    // MARK: - Shared storage

    func testASnapshotWrittenByTheAppIsReadableByTheWidget() throws {
        let published = InspectionSnapshot(
            areasTotal: 8,
            areasComplete: 5,
            areasNeedingAttention: 2,
            evidenceCount: 14,
            pendingInboxCount: 1,
            daysUntilConditionReportDue: 3,
            generatedAt: Date(timeIntervalSince1970: 1_780_000_000),
            hasActiveTenancy: true
        )

        try store.write(published)

        // A fresh store instance, standing in for the widget process.
        let readBack = try XCTUnwrap(InspectionSnapshotStore().read())
        XCTAssertEqual(readBack, published, "The widget must see what the app wrote")
    }

    func testTheSnapshotLivesInItsOwnDirectoryAwayFromEvidenceAndTheInbox() throws {
        try store.write(.noActiveTenancy)

        let widgetDirectory = try AppGroup.directoryURL(.widget)
        let snapshotPath = widgetDirectory.appendingPathComponent("snapshot.json")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: snapshotPath.path),
            "The widget snapshot should sit under Widget/, not mixed in with shared files"
        )

        let inboxDirectory = try AppGroup.directoryURL(.sharedEvidenceInbox)
        let evidenceDirectory = try AppGroup.directoryURL(.evidence)
        XCTAssertNotEqual(widgetDirectory, inboxDirectory)
        XCTAssertNotEqual(widgetDirectory, evidenceDirectory)
    }

    // MARK: - Reduction

    func testProgressReducesToASnapshotThatDropsEverythingIdentifying() {
        let area = InspectionArea(name: "Main bedroom", displayOrder: 0, tenancyID: UUID())
        let progress = InspectionProgress(
            areasTotal: 8,
            areasComplete: 5,
            requiredItemsTotal: 48,
            requiredItemsReviewed: 30,
            undocumentedDamageCount: 2,
            areasNeedingAttention: [area],
            evidenceCount: 14,
            pendingSharedEvidenceCount: 1,
            daysUntilConditionReportDue: 3
        )

        let snapshot = progress.snapshot(generatedAt: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(snapshot.areasNeedingAttention, 1, "Rooms reduce to a count, never to their names")
        XCTAssertEqual(snapshot.areasTotal, 8)
        XCTAssertEqual(snapshot.evidenceCount, 14)
        XCTAssertEqual(snapshot.completionFraction, 5.0 / 8.0, accuracy: 0.0001)
    }

    func testCompletionFractionIsSafeBeforeAnyRoomsExist() {
        XCTAssertEqual(InspectionSnapshot.noActiveTenancy.completionFraction, 0)
    }

    // MARK: - Rendering both families

    @MainActor
    func testTheSmallFamilyRendersTheProgressAndDeadline() throws {
        let image = try render(
            SmallInspectionView(snapshot: .sample),
            size: CGSize(width: 170, height: 170)
        )
        XCTAssertEqual(image.size.width, 170, accuracy: 1)
        XCTAssertFalse(isBlank(image), "systemSmall must draw something, not come out empty")
    }

    @MainActor
    func testTheMediumFamilyRendersTheProgressAndDeadline() throws {
        let image = try render(
            MediumInspectionView(snapshot: .sample),
            size: CGSize(width: 364, height: 170)
        )
        XCTAssertEqual(image.size.width, 364, accuracy: 1)
        XCTAssertFalse(isBlank(image), "systemMedium must draw something, not come out empty")
    }

    @MainActor
    func testBothFamiliesRenderTheFirstRunStateWithoutATenancy() throws {
        let small = try render(NoTenancyView(), size: CGSize(width: 170, height: 170))
        let medium = try render(NoTenancyView(), size: CGSize(width: 364, height: 170))
        XCTAssertFalse(isBlank(small))
        XCTAssertFalse(isBlank(medium))
    }

    @MainActor
    func testBothFamiliesSurviveAnOverdueTenancyWithLargeCounts() throws {
        // Long strings and three-digit counts are where a widget layout usually
        // breaks, so render the worst realistic case, not just the tidy one.
        let stressed = InspectionSnapshot(
            areasTotal: 24,
            areasComplete: 23,
            areasNeedingAttention: 12,
            evidenceCount: 480,
            pendingInboxCount: 99,
            daysUntilConditionReportDue: -45,
            generatedAt: Date(timeIntervalSince1970: 0),
            hasActiveTenancy: true
        )

        XCTAssertFalse(try isBlank(render(SmallInspectionView(snapshot: stressed), size: CGSize(width: 170, height: 170))))
        XCTAssertFalse(try isBlank(render(MediumInspectionView(snapshot: stressed), size: CGSize(width: 364, height: 170))))
    }

    // MARK: - Deadline wording

    func testDeadlineWordingReadsNaturallyAtEachBoundary() {
        func style(_ days: Int?) -> DeadlineStyle {
            DeadlineStyle(snapshot: InspectionSnapshot(
                areasTotal: 8, areasComplete: 1, areasNeedingAttention: 0,
                evidenceCount: 0, pendingInboxCount: 0,
                daysUntilConditionReportDue: days,
                generatedAt: Date(timeIntervalSince1970: 0), hasActiveTenancy: true
            ))
        }

        XCTAssertEqual(style(5).shortText, "5 days left")
        XCTAssertEqual(style(1).shortText, "1 day left")
        XCTAssertEqual(style(0).shortText, "Due today")
        XCTAssertEqual(style(-1).shortText, "Report overdue")
        XCTAssertEqual(style(nil).shortText, "No due date")

        XCTAssertEqual(style(1).longText, "Condition report due tomorrow")
        XCTAssertEqual(style(0).longText, "Condition report due today")
    }

    // MARK: - Helpers

    @MainActor
    private func render(_ view: some View, size: CGSize) throws -> UIImage {
        let renderer = ImageRenderer(
            content: view
                .frame(width: size.width, height: size.height)
                .background(.white)
        )
        renderer.scale = 2
        return try XCTUnwrap(renderer.uiImage, "The view failed to render at \(size)")
    }

    /// True when every sampled pixel is the background colour, which is what a
    /// silently broken widget layout looks like.
    private func isBlank(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return true }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return true }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Any pixel that is not near-white means content was drawn.
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = pixels[index], g = pixels[index + 1], b = pixels[index + 2]
            if r < 230 || g < 230 || b < 230 { return false }
        }
        return true
    }
}
