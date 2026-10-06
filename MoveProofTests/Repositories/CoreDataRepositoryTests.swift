import CoreData
import XCTest
@testable import MoveProof

/// Exercises the Core Data repositories against a real (in-memory) store.
///
/// The use case tests above use mocks, which is right for testing rules. But a mock
/// cannot tell you whether `evidence.@count == 0` is a valid predicate, whether the
/// relationship traversal `inspectionArea.tenancy.id` resolves, or whether a delete
/// rule does what the model says. Those only show up against the real stack, so
/// these tests use one, configured in memory, so no tenant data is touched.
@MainActor
final class CoreDataRepositoryTests: XCTestCase {

    private var store: InspectionStore!
    private var tenancyRepository: CoreDataTenancyRepository!
    private var inspectionRepository: CoreDataInspectionRepository!
    private var evidenceRepository: CoreDataEvidenceRepository!

    override func setUp() {
        super.setUp()
        store = InspectionStore(inMemory: true)
        let context = store.viewContext
        tenancyRepository = CoreDataTenancyRepository(context: context)
        inspectionRepository = CoreDataInspectionRepository(context: context)
        evidenceRepository = CoreDataEvidenceRepository(context: context)
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    @discardableResult
    private func makeTenancy(
        address: String = "12 Harris Street, Ultimo NSW 2007",
        status: TenancyStatus = .documenting,
        createdAt: Date = Date()
    ) throws -> Tenancy {
        let tenancy = Tenancy(
            propertyAddress: address,
            moveInDate: Date(),
            conditionReportDueDate: Date().addingTimeInterval(7 * 86_400),
            createdAt: createdAt,
            status: status
        )
        try tenancyRepository.save(tenancy)
        return tenancy
    }

    @discardableResult
    private func makeArea(
        in tenancy: Tenancy,
        name: String,
        order: Int,
        status: AreaInspectionStatus = .notStarted,
        items: [ConditionItem] = []
    ) throws -> InspectionArea {
        let area = InspectionArea(
            name: name,
            inspectionStatus: status,
            displayOrder: order,
            tenancyID: tenancy.id
        )
        let rebound = items.map {
            ConditionItem(
                id: $0.id,
                title: $0.title,
                category: $0.category,
                conditionState: $0.conditionState,
                notes: $0.notes,
                reviewedAt: $0.reviewedAt,
                isRequired: $0.isRequired,
                inspectionAreaID: area.id
            )
        }
        try inspectionRepository.createAreas([area], withItems: [area.id: rebound])
        return area
    }

    private func item(
        _ title: String,
        state: ConditionState = .notReviewed,
        notes: String = ""
    ) -> ConditionItem {
        ConditionItem(
            title: title,
            category: .structure,
            conditionState: state,
            notes: notes,
            inspectionAreaID: UUID() // rebound by makeArea
        )
    }

    // MARK: - Round trip

    func testATenancyAndItsRoomsSurviveARoundTripThroughTheStore() throws {
        let tenancy = try makeTenancy()
        try makeArea(in: tenancy, name: "Kitchen", order: 0, items: [item("Flooring")])

        let loaded = try XCTUnwrap(tenancyRepository.fetchTenancy(id: tenancy.id))
        XCTAssertEqual(loaded.propertyAddress, "12 Harris Street, Ultimo NSW 2007")
        XCTAssertEqual(loaded.status, .documenting)

        let areas = try inspectionRepository.fetchAreas(forTenancy: tenancy.id)
        XCTAssertEqual(areas.map(\.name), ["Kitchen"])
        XCTAssertEqual(areas.first?.tenancyID, tenancy.id, "The relationship should map back to a domain id")

        let items = try inspectionRepository.fetchConditionItems(inArea: try XCTUnwrap(areas.first).id)
        XCTAssertEqual(items.map(\.title), ["Flooring"])
    }

    // MARK: - Predicate: the active tenancy

    func testFetchingTheActiveTenancyIgnoresArchivedOnesAndPrefersTheNewest() throws {
        let older = try makeTenancy(
            address: "Old flat",
            createdAt: Date().addingTimeInterval(-86_400)
        )
        try makeTenancy(address: "Archived flat", status: .archived)
        _ = older

        let newer = try makeTenancy(address: "Current flat", createdAt: Date())

        let active = try XCTUnwrap(tenancyRepository.fetchActiveTenancy())
        XCTAssertEqual(active.id, newer.id)
        XCTAssertEqual(active.propertyAddress, "Current flat")
    }

    func testFetchingTheActiveTenancyReturnsNilWhenEverythingIsArchived() throws {
        try makeTenancy(status: .archived)
        XCTAssertNil(try tenancyRepository.fetchActiveTenancy())
    }

    // MARK: - Predicate: incomplete rooms

    // MARK: - Predicate: undocumented damage

    func testTheUndocumentedDamageQueryFindsOnlyDamageWithNoNoteAndNoEvidence() throws {
        let tenancy = try makeTenancy()

        let kitchen = try makeArea(in: tenancy, name: "Kitchen", order: 0, items: [
            item("Flooring", state: .damaged, notes: ""),                    // undocumented
            item("Walls and ceiling", state: .damaged, notes: "Large dent."), // has a note
            item("Windows", state: .undamaged, notes: "")                     // not damage
        ])
        let bathroom = try makeArea(in: tenancy, name: "Bathroom", order: 1, items: [
            item("Exhaust fan", state: .notWorking, notes: "")                // undocumented
        ])

        // Give one of the undocumented items a photo; it should drop out of the query.
        let fanItem = try XCTUnwrap(
            try inspectionRepository.fetchConditionItems(inArea: bathroom.id)
                .first { $0.title == "Exhaust fan" }
        )
        try evidenceRepository.save(
            EvidenceItem(
                kind: .photograph,
                storedFileName: "fan.jpg",
                displayName: "Exhaust fan",
                source: .capturedInApp,
                conditionItemID: fanItem.id,
                tenancyID: tenancy.id
            )
        )

        let missing = try inspectionRepository
            .fetchConditionItemsMissingSupportingDetail(forTenancy: tenancy.id)

        XCTAssertEqual(
            missing.map(\.title),
            ["Flooring"],
            "Only damage with neither a note nor a single piece of evidence should come back"
        )
        XCTAssertEqual(missing.first?.inspectionAreaID, kitchen.id)
    }

    func testTheUndocumentedDamageQueryIsScopedToOneProperty() throws {
        let mine = try makeTenancy(address: "My place")
        try makeArea(in: mine, name: "Kitchen", order: 0, items: [item("Flooring", state: .damaged)])

        let theirs = try makeTenancy(address: "Their place", status: .archived)
        try makeArea(in: theirs, name: "Kitchen", order: 0, items: [item("Flooring", state: .damaged)])

        let missing = try inspectionRepository
            .fetchConditionItemsMissingSupportingDetail(forTenancy: mine.id)

        XCTAssertEqual(
            missing.count,
            1,
            "The predicate traverses inspectionArea.tenancy, so another property's damage must not appear"
        )
    }

    // MARK: - Predicate: duplicate import detection

    func testEvidenceCanBeFoundByTheInboxItemItWasImportedFrom() throws {
        let tenancy = try makeTenancy()
        let inboxItemID = UUID()

        try evidenceRepository.save(
            EvidenceItem(
                kind: .document,
                storedFileName: "report.pdf",
                displayName: "Signed condition report.pdf",
                source: .sharedFromAnotherApp,
                tenancyID: tenancy.id,
                importedInboxItemID: inboxItemID
            )
        )

        let found = try evidenceRepository.fetchEvidence(importedFromInboxItem: inboxItemID)
        XCTAssertEqual(found?.displayName, "Signed condition report.pdf")
        XCTAssertNil(
            try evidenceRepository.fetchEvidence(importedFromInboxItem: UUID()),
            "An unrelated inbox item must not match"
        )
    }

    func testUnassignedEvidenceQueryReturnsOnlyEvidenceNotYetFiledAgainstAnItem() throws {
        let tenancy = try makeTenancy()
        let kitchen = try makeArea(in: tenancy, name: "Kitchen", order: 0, items: [item("Flooring")])
        let flooring = try XCTUnwrap(inspectionRepository.fetchConditionItems(inArea: kitchen.id).first)

        try evidenceRepository.save(
            EvidenceItem(kind: .photograph, storedFileName: "a.jpg", displayName: "Filed",
                         source: .capturedInApp, conditionItemID: flooring.id, tenancyID: tenancy.id)
        )
        try evidenceRepository.save(
            EvidenceItem(kind: .photograph, storedFileName: "b.jpg", displayName: "Unfiled",
                         source: .capturedInApp, tenancyID: tenancy.id)
        )

        let unassigned = try evidenceRepository.fetchUnassignedEvidence(forTenancy: tenancy.id)
        XCTAssertEqual(unassigned.map(\.displayName), ["Unfiled"])
        XCTAssertEqual(try evidenceRepository.evidenceCount(forConditionItem: flooring.id), 1)
    }

    // MARK: - Delete rules

    func testDeletingATenancyCascadesToItsRoomsChecklistsAndEvidence() throws {
        let tenancy = try makeTenancy()
        let kitchen = try makeArea(in: tenancy, name: "Kitchen", order: 0, items: [item("Flooring")])
        try evidenceRepository.save(
            EvidenceItem(kind: .photograph, storedFileName: "a.jpg", displayName: "Floor",
                         source: .capturedInApp, tenancyID: tenancy.id)
        )

        try tenancyRepository.delete(tenancyID: tenancy.id)

        XCTAssertNil(try tenancyRepository.fetchTenancy(id: tenancy.id))
        XCTAssertTrue(try inspectionRepository.fetchAreas(forTenancy: tenancy.id).isEmpty)
        XCTAssertTrue(try inspectionRepository.fetchConditionItems(inArea: kitchen.id).isEmpty)
        XCTAssertTrue(try evidenceRepository.fetchEvidence(forTenancy: tenancy.id).isEmpty)
    }

    func testDeletingARoomKeepsTheTenantsEvidenceInTheLibrary() throws {
        let tenancy = try makeTenancy()
        let kitchen = try makeArea(in: tenancy, name: "Kitchen", order: 0, items: [item("Flooring")])
        let flooring = try XCTUnwrap(inspectionRepository.fetchConditionItems(inArea: kitchen.id).first)

        try evidenceRepository.save(
            EvidenceItem(kind: .photograph, storedFileName: "scratch.jpg", displayName: "Kitchen floor",
                         source: .capturedInApp, conditionItemID: flooring.id, tenancyID: tenancy.id)
        )

        try inspectionRepository.deleteArea(id: kitchen.id)

        let remaining = try evidenceRepository.fetchEvidence(forTenancy: tenancy.id)
        XCTAssertEqual(
            remaining.count,
            1,
            "The ConditionItem -> evidence nullify rule exists so removing a room never destroys the tenant's photos"
        )
        XCTAssertNil(
            remaining.first?.conditionItemID,
            "The photo should go back to the unfiled library, not point at a deleted item"
        )
    }

    // MARK: - Error surfacing

    func testDeletingATenancyThatIsNotThereReportsItRatherThanFailingSilently() {
        XCTAssertThrowsError(try tenancyRepository.delete(tenancyID: UUID())) { error in
            guard case RepositoryError.tenancyNotFound = error else {
                return XCTFail("Expected tenancyNotFound, got \(error)")
            }
        }
    }

    func testSavingEvidenceAgainstAMissingTenancyIsRejected() {
        let orphan = EvidenceItem(
            kind: .photograph,
            storedFileName: "a.jpg",
            displayName: "Orphan",
            source: .capturedInApp,
            tenancyID: UUID()
        )

        XCTAssertThrowsError(try evidenceRepository.save(orphan)) { error in
            guard case RepositoryError.tenancyNotFound = error else {
                return XCTFail("Expected tenancyNotFound, got \(error)")
            }
        }
    }
}
