import XCTest
@testable import MoveProof

/// Rules covered: progress is derived rather than stored, report-ready status
/// follows the evidence, and the widget only ever receives reduced data.
final class ReviewInspectionProgressTests: XCTestCase {

    private var tenancyRepository: MockTenancyRepository!
    private var inspectionRepository: MockInspectionRepository!
    private var evidenceRepository: MockEvidenceRepository!
    private var snapshotPublisher: MockSnapshotPublisher!
    private var useCase: ReviewInspectionProgressUseCase!

    private var tenancy: Tenancy!
    private let referenceDate = Date(timeIntervalSince1970: 1_780_000_000)

    override func setUp() {
        super.setUp()

        tenancy = Tenancy(
            propertyAddress: "12 Harris Street, Ultimo NSW 2007",
            moveInDate: referenceDate,
            conditionReportDueDate: Calendar.current.date(byAdding: .day, value: 3, to: referenceDate)!,
            createdAt: referenceDate
        )

        tenancyRepository = MockTenancyRepository(tenancies: [tenancy])
        inspectionRepository = MockInspectionRepository()
        evidenceRepository = MockEvidenceRepository()
        snapshotPublisher = MockSnapshotPublisher()

        // Keep the "missing supporting detail" mock consistent with the evidence mock.
        inspectionRepository.evidenceLookup = { [weak self] itemID in
            (try? self?.evidenceRepository.evidenceCount(forConditionItem: itemID)) ?? 0
        }

        useCase = ReviewInspectionProgressUseCase(
            tenancyRepository: tenancyRepository,
            inspectionRepository: inspectionRepository,
            evidenceRepository: evidenceRepository,
            snapshotPublisher: snapshotPublisher
        )
    }

    @discardableResult
    private func addRoom(
        _ name: String,
        order: Int,
        status: AreaInspectionStatus,
        items: [(title: String, state: ConditionState, notes: String)]
    ) throws -> InspectionArea {
        let area = InspectionArea(
            name: name,
            inspectionStatus: status,
            displayOrder: order,
            tenancyID: tenancy.id
        )
        try inspectionRepository.save(area)
        for item in items {
            try inspectionRepository.save(
                ConditionItem(
                    title: item.title,
                    category: .structure,
                    conditionState: item.state,
                    notes: item.notes,
                    reviewedAt: item.state == .notReviewed ? nil : referenceDate,
                    inspectionAreaID: area.id
                )
            )
        }
        return area
    }

    // MARK: - Happy path

    func testProgressCountsRoomsAndItemsAcrossTheWholeWalkthrough() throws {
        try addRoom("Kitchen", order: 0, status: .complete, items: [
            ("Flooring", .undamaged, ""),
            ("Walls and ceiling", .minorWear, "")
        ])
        try addRoom("Bathroom", order: 1, status: .inProgress, items: [
            ("Flooring", .undamaged, ""),
            ("Walls and ceiling", .notReviewed, "")
        ])

        let summary = try useCase.execute(now: referenceDate)

        XCTAssertEqual(summary.progress.areasTotal, 2)
        XCTAssertEqual(summary.progress.areasComplete, 1)
        XCTAssertEqual(summary.progress.requiredItemsTotal, 4)
        XCTAssertEqual(summary.progress.requiredItemsReviewed, 3)
        XCTAssertEqual(summary.progress.daysUntilConditionReportDue, 3)
        XCTAssertEqual(summary.progress.deadlineUrgency, .comfortable)
    }

    func testUndocumentedDamageIsSurfacedWithTheRoomItIsIn() throws {
        try addRoom("Kitchen", order: 0, status: .inProgress, items: [
            ("Flooring", .damaged, "")          // no note, no photo
        ])
        try addRoom("Bathroom", order: 1, status: .inProgress, items: [
            ("Flooring", .damaged, "Cracked tile by the door.")  // documented
        ])

        let summary = try useCase.execute(now: referenceDate)

        XCTAssertEqual(summary.progress.undocumentedDamageCount, 1)
        XCTAssertEqual(summary.progress.areasNeedingAttention.map(\.name), ["Kitchen"])
    }

    // MARK: - Derived status

    func testTheTenancyBecomesReportReadyOnlyWhenEveryRoomIsSignedOffAndDamageIsDocumented() throws {
        try addRoom("Kitchen", order: 0, status: .complete, items: [
            ("Flooring", .damaged, "Deep scratch near the oven.")
        ])

        let summary = try useCase.execute(now: referenceDate)

        XCTAssertTrue(summary.progress.isReportReady)
        XCTAssertEqual(summary.tenancy.status, .reportReady)
        XCTAssertEqual(
            tenancyRepository.savedTenancies.last?.status,
            .reportReady,
            "Derived status should be written back, not just reported"
        )
    }

    func testASignedOffRoomWithUndocumentedDamageKeepsTheTenancyInDocumenting() throws {
        // A room signed off earlier, whose supporting photo was later deleted.
        try addRoom("Kitchen", order: 0, status: .complete, items: [
            ("Flooring", .damaged, "")
        ])

        let summary = try useCase.execute(now: referenceDate)

        XCTAssertFalse(
            summary.progress.isReportReady,
            "Deleting the evidence behind a signed-off room must pull the tenancy back to documenting"
        )
        XCTAssertEqual(summary.tenancy.status, .documenting)
    }

    // MARK: - Widget privacy

    func testTheWidgetSnapshotCarriesCountsButNotThePropertyAddress() throws {
        try addRoom("Kitchen", order: 0, status: .complete, items: [("Flooring", .undamaged, "")])
        try addRoom("Bathroom", order: 1, status: .inProgress, items: [("Flooring", .damaged, "")])

        try useCase.execute(now: referenceDate)

        let snapshot = try XCTUnwrap(snapshotPublisher.lastSnapshot)
        XCTAssertEqual(snapshot.areasTotal, 2)
        XCTAssertEqual(snapshot.areasComplete, 1)
        XCTAssertEqual(snapshot.areasNeedingAttention, 1)
        XCTAssertEqual(snapshot.daysUntilConditionReportDue, 3)
        XCTAssertTrue(snapshot.hasActiveTenancy)

        // The snapshot type has no field that could carry an address, a note or a
        // file name. Encoding it and searching the bytes proves nothing leaked.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(decoding: try encoder.encode(snapshot), as: UTF8.self)
        XCTAssertFalse(json.contains("Harris"), "The property address must never reach shared widget storage")
        XCTAssertFalse(json.contains("Kitchen"), "Room names must never reach shared widget storage")
    }

    func testReviewingProgressRepublishesTheSnapshotSoTheWidgetFollowsTheApp() throws {
        try addRoom("Kitchen", order: 0, status: .inProgress, items: [("Flooring", .notReviewed, "")])

        try useCase.execute(now: referenceDate)
        try useCase.execute(now: referenceDate)

        XCTAssertEqual(
            snapshotPublisher.publishedSnapshots.count,
            2,
            "Every progress review should refresh the widget, which is how the Home Screen keeps up"
        )
    }

    // MARK: - Error case

    func testReviewingProgressWithNoActiveTenancyIsRejected() {
        tenancyRepository.tenancies = [:]

        XCTAssertThrowsError(try useCase.execute(now: referenceDate)) { error in
            XCTAssertEqual(error as? InspectionReviewError, .noActiveTenancy)
        }
    }

    func testPublishingAnEmptySnapshotClearsTheWidget() {
        useCase.publishEmptySnapshot()

        XCTAssertEqual(snapshotPublisher.lastSnapshot, .noActiveTenancy)
        XCTAssertEqual(snapshotPublisher.lastSnapshot?.hasActiveTenancy, false)
    }

    // MARK: - Deadline boundaries

    func testTheDeadlineBecomesUrgentTwoDaysOutAndOverdueAfterItPasses() throws {
        try addRoom("Kitchen", order: 0, status: .inProgress, items: [("Flooring", .notReviewed, "")])

        let twoDaysBefore = Calendar.current.date(byAdding: .day, value: -2, to: tenancy.conditionReportDueDate)!
        XCTAssertEqual(try useCase.execute(now: twoDaysBefore).progress.deadlineUrgency, .dueSoon)

        let dayAfter = Calendar.current.date(byAdding: .day, value: 1, to: tenancy.conditionReportDueDate)!
        let overdue = try useCase.execute(now: dayAfter).progress
        XCTAssertEqual(overdue.deadlineUrgency, .overdue)
        XCTAssertEqual(overdue.daysUntilConditionReportDue, -1)
    }
}
