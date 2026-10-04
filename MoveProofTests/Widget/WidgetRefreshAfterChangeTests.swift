import XCTest
@testable import MoveProof

/// Covers the one path every successful domain write uses to reach the Home Screen.
///
/// The widget used to refresh only when the dashboard happened to be opened, so
/// signing a room off left the Home Screen out of date until the tenant went back
/// there. The refresh now hangs off `refreshPublishedSnapshot`, which the app calls
/// from the one place it records a successful save. These tests pin that down
/// without needing the widget extension installed.
final class WidgetRefreshAfterChangeTests: XCTestCase {

    private var tenancyRepository: MockTenancyRepository!
    private var inspectionRepository: MockInspectionRepository!
    private var evidenceRepository: MockEvidenceRepository!
    private var snapshotPublisher: MockSnapshotPublisher!
    private var reviewProgress: ReviewInspectionProgressUseCase!

    private var tenancy: Tenancy!
    private var kitchen: InspectionArea!
    private let referenceDate = Date(timeIntervalSince1970: 1_780_000_000)

    override func setUp() {
        super.setUp()

        tenancy = Tenancy(
            propertyAddress: "12 Harris Street, Ultimo NSW 2007",
            moveInDate: referenceDate,
            conditionReportDueDate: Calendar.current.date(byAdding: .day, value: 3, to: referenceDate)!,
            createdAt: referenceDate
        )
        kitchen = InspectionArea(
            name: "Kitchen",
            inspectionStatus: .inProgress,
            displayOrder: 0,
            tenancyID: tenancy.id
        )

        tenancyRepository = MockTenancyRepository(tenancies: [tenancy])
        inspectionRepository = MockInspectionRepository(areas: [kitchen])
        evidenceRepository = MockEvidenceRepository()
        snapshotPublisher = MockSnapshotPublisher()

        inspectionRepository.evidenceLookup = { [weak self] itemID in
            (try? self?.evidenceRepository.evidenceCount(forConditionItem: itemID)) ?? 0
        }

        reviewProgress = ReviewInspectionProgressUseCase(
            tenancyRepository: tenancyRepository,
            inspectionRepository: inspectionRepository,
            evidenceRepository: evidenceRepository,
            snapshotPublisher: snapshotPublisher
        )
    }

    // MARK: - A change reaches the widget

    func testSigningOffARoomRepublishesTheWidgetSnapshot() throws {
        let item = ConditionItem(
            title: "Flooring",
            category: .structure,
            conditionState: .undamaged,
            reviewedAt: referenceDate,
            inspectionAreaID: kitchen.id
        )
        try inspectionRepository.save(item)

        let signOff = CompleteInspectionAreaUseCase(
            inspectionRepository: inspectionRepository,
            evidenceRepository: evidenceRepository
        )
        try signOff.execute(areaID: kitchen.id)

        // What the app does after a successful write.
        reviewProgress.refreshPublishedSnapshot(now: referenceDate)

        let published = try XCTUnwrap(snapshotPublisher.lastSnapshot)
        XCTAssertEqual(published.areasComplete, 1)
        XCTAssertTrue(published.hasActiveTenancy)
    }

    func testAddingEvidenceRepublishesTheWidgetSnapshotWithTheNewCount() throws {
        try evidenceRepository.save(
            EvidenceItem(
                kind: .photograph,
                storedFileName: "floor.jpg",
                displayName: "Kitchen floor.jpg",
                source: .capturedInApp,
                tenancyID: tenancy.id
            )
        )

        reviewProgress.refreshPublishedSnapshot(now: referenceDate)

        XCTAssertEqual(snapshotPublisher.lastSnapshot?.evidenceCount, 1)
    }

    func testEachSuccessfulChangePublishesAgainRatherThanOnlyTheFirst() {
        reviewProgress.refreshPublishedSnapshot(now: referenceDate)
        reviewProgress.refreshPublishedSnapshot(now: referenceDate)
        reviewProgress.refreshPublishedSnapshot(now: referenceDate)

        XCTAssertEqual(snapshotPublisher.publishedSnapshots.count, 3)
    }

    // MARK: - Graceful degradation

    func testRefreshingWithNoPropertyLeftPublishesTheEmptyStateRatherThanAStaleSummary() {
        tenancyRepository.tenancies = [:]

        reviewProgress.refreshPublishedSnapshot(now: referenceDate)

        XCTAssertEqual(snapshotPublisher.lastSnapshot, .noActiveTenancy)
        XCTAssertEqual(snapshotPublisher.lastSnapshot?.hasActiveTenancy, false)
    }

    /// The save has already worked by the time the refresh runs, so a failure here
    /// must not show up as an error. The widget keeps the snapshot it already has
    /// until the next good write.
    func testAStorageFailureDuringRefreshIsSwallowedRatherThanInterruptingTheTenant() {
        inspectionRepository.errorToThrow = RepositoryError.fetchFailed(underlying: CocoaError(.fileReadUnknown))

        reviewProgress.refreshPublishedSnapshot(now: referenceDate)

        XCTAssertTrue(
            snapshotPublisher.publishedSnapshots.isEmpty,
            "A failed recomputation should leave the previous snapshot in place, not overwrite it"
        )
    }

    // MARK: - Privacy survives the extra refresh path

    func testTheRepublishedSnapshotStillCarriesNoAddressNotesOrPhotos() throws {
        reviewProgress.refreshPublishedSnapshot(now: referenceDate)

        let published = try XCTUnwrap(snapshotPublisher.lastSnapshot)
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(published), encoding: .utf8))

        XCTAssertFalse(encoded.contains("Harris Street"))
        XCTAssertFalse(encoded.contains("Ultimo"))
    }
}
