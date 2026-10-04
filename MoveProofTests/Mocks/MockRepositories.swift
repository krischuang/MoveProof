import Foundation
@testable import MoveProof

/// In-memory stand-ins for the repository protocols.
///
/// The repositories are written purely in domain value types, so these mocks are
/// just dictionaries. No Core Data stack, no store file, and a use case test runs in
/// microseconds. That speed is the payoff for putting the protocol boundary here.
///
/// Each mock can also be told to fail, so the error paths get tested too, not only
/// the paths where everything works.

// MARK: - Tenancy

final class MockTenancyRepository: TenancyRepository {

    var tenancies: [UUID: Tenancy] = [:]
    /// When set, every method throws this instead of doing its job.
    var errorToThrow: Error?
    private(set) var savedTenancies: [Tenancy] = []

    init(tenancies: [Tenancy] = []) {
        for tenancy in tenancies {
            self.tenancies[tenancy.id] = tenancy
        }
    }

    func fetchActiveTenancy() throws -> Tenancy? {
        if let errorToThrow { throw errorToThrow }
        return tenancies.values
            .filter { $0.status.isActive }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    func fetchTenancy(id: UUID) throws -> Tenancy? {
        if let errorToThrow { throw errorToThrow }
        return tenancies[id]
    }

    func save(_ tenancy: Tenancy) throws {
        if let errorToThrow { throw errorToThrow }
        tenancies[tenancy.id] = tenancy
        savedTenancies.append(tenancy)
    }

    func delete(tenancyID: UUID) throws {
        if let errorToThrow { throw errorToThrow }
        tenancies[tenancyID] = nil
    }
}

// MARK: - Inspection

final class MockInspectionRepository: InspectionRepository {

    var areas: [UUID: InspectionArea] = [:]
    var conditionItems: [UUID: ConditionItem] = [:]
    var errorToThrow: Error?

    private(set) var savedAreas: [InspectionArea] = []
    private(set) var savedConditionItems: [ConditionItem] = []
    private(set) var createdAreaBatches: [(areas: [InspectionArea], items: [UUID: [ConditionItem]])] = []

    init(areas: [InspectionArea] = [], conditionItems: [ConditionItem] = []) {
        for area in areas { self.areas[area.id] = area }
        for item in conditionItems { self.conditionItems[item.id] = item }
    }

    func fetchAreas(forTenancy tenancyID: UUID) throws -> [InspectionArea] {
        if let errorToThrow { throw errorToThrow }
        return areas.values
            .filter { $0.tenancyID == tenancyID }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    func fetchArea(id: UUID) throws -> InspectionArea? {
        if let errorToThrow { throw errorToThrow }
        return areas[id]
    }

    func fetchConditionItems(inArea areaID: UUID) throws -> [ConditionItem] {
        if let errorToThrow { throw errorToThrow }
        return conditionItems.values
            .filter { $0.inspectionAreaID == areaID }
            .sorted { $0.title < $1.title }
    }

    func fetchConditionItem(id: UUID) throws -> ConditionItem? {
        if let errorToThrow { throw errorToThrow }
        return conditionItems[id]
    }

    /// Mirrors the real predicate: damage, no note, and no evidence attached.
    ///
    /// The evidence side is supplied by whichever `MockEvidenceRepository` the test
    /// wired up, so the two mocks stay consistent with each other.
    var evidenceLookup: ((UUID) -> Int)?

    func fetchConditionItemsMissingSupportingDetail(forTenancy tenancyID: UUID) throws -> [ConditionItem] {
        if let errorToThrow { throw errorToThrow }
        let areaIDs = Set(try fetchAreas(forTenancy: tenancyID).map(\.id))
        return conditionItems.values
            .filter { item in
                areaIDs.contains(item.inspectionAreaID)
                    && item.conditionState.requiresSupportingDetail
                    && item.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && (evidenceLookup?(item.id) ?? 0) == 0
            }
            .sorted { $0.title < $1.title }
    }

    func createAreas(_ areas: [InspectionArea], withItems items: [UUID: [ConditionItem]]) throws {
        if let errorToThrow { throw errorToThrow }
        createdAreaBatches.append((areas, items))
        for area in areas { self.areas[area.id] = area }
        for item in items.values.flatMap({ $0 }) { conditionItems[item.id] = item }
    }

    func save(_ area: InspectionArea) throws {
        if let errorToThrow { throw errorToThrow }
        areas[area.id] = area
        savedAreas.append(area)
    }

    func save(_ conditionItem: ConditionItem) throws {
        if let errorToThrow { throw errorToThrow }
        conditionItems[conditionItem.id] = conditionItem
        savedConditionItems.append(conditionItem)
    }

    func deleteArea(id: UUID) throws {
        if let errorToThrow { throw errorToThrow }
        areas[id] = nil
        for (key, item) in conditionItems where item.inspectionAreaID == id {
            conditionItems[key] = nil
        }
    }
}

// MARK: - Evidence

final class MockEvidenceRepository: EvidenceRepository {

    var evidence: [UUID: EvidenceItem] = [:]
    /// Fails every method.
    var errorToThrow: Error?
    /// Fails only `save`, so a test can let the reads succeed and still exercise the
    /// write-failure path, which is where the file rollback lives.
    var saveErrorToThrow: Error?
    private(set) var savedEvidence: [EvidenceItem] = []
    private(set) var deletedEvidenceIDs: [UUID] = []

    init(evidence: [EvidenceItem] = []) {
        for item in evidence { self.evidence[item.id] = item }
    }

    func fetchEvidence(forTenancy tenancyID: UUID) throws -> [EvidenceItem] {
        if let errorToThrow { throw errorToThrow }
        return evidence.values.filter { $0.tenancyID == tenancyID }
    }

    func fetchEvidence(forConditionItem conditionItemID: UUID) throws -> [EvidenceItem] {
        if let errorToThrow { throw errorToThrow }
        return evidence.values.filter { $0.conditionItemID == conditionItemID }
    }

    func fetchUnassignedEvidence(forTenancy tenancyID: UUID) throws -> [EvidenceItem] {
        if let errorToThrow { throw errorToThrow }
        return evidence.values.filter { $0.tenancyID == tenancyID && $0.conditionItemID == nil }
    }

    func fetchEvidence(id: UUID) throws -> EvidenceItem? {
        if let errorToThrow { throw errorToThrow }
        return evidence[id]
    }

    func fetchEvidence(importedFromInboxItem inboxItemID: UUID) throws -> EvidenceItem? {
        if let errorToThrow { throw errorToThrow }
        return evidence.values.first { $0.importedInboxItemID == inboxItemID }
    }

    func evidenceCount(forConditionItem conditionItemID: UUID) throws -> Int {
        if let errorToThrow { throw errorToThrow }
        return evidence.values.count { $0.conditionItemID == conditionItemID }
    }

    func save(_ item: EvidenceItem) throws {
        if let errorToThrow { throw errorToThrow }
        if let saveErrorToThrow { throw saveErrorToThrow }
        evidence[item.id] = item
        savedEvidence.append(item)
    }

    func delete(evidenceID: UUID) throws {
        if let errorToThrow { throw errorToThrow }
        evidence[evidenceID] = nil
        deletedEvidenceIDs.append(evidenceID)
    }
}

// MARK: - Evidence files

/// Keeps "files" in a dictionary so import rules can be tested without writing
/// anything to disk.
final class MockEvidenceFileStore: EvidenceFileStore {

    private(set) var storedFiles: [String: Data] = [:]
    private(set) var adoptedSourceURLs: [URL] = []
    private(set) var removedFileNames: [String] = []
    var errorToThrow: Error?

    func adopt(fileAt sourceURL: URL, preferredExtension: String) throws -> String {
        if let errorToThrow { throw errorToThrow }
        adoptedSourceURLs.append(sourceURL)
        let name = "\(UUID().uuidString).\(preferredExtension)"
        storedFiles[name] = (try? Data(contentsOf: sourceURL)) ?? Data("stub".utf8)
        return name
    }

    func store(data: Data, preferredExtension: String) throws -> String {
        if let errorToThrow { throw errorToThrow }
        let name = "\(UUID().uuidString).\(preferredExtension)"
        storedFiles[name] = data
        return name
    }

    func url(forStoredFileName storedFileName: String) throws -> URL {
        URL(fileURLWithPath: "/mock/evidence/\(storedFileName)")
    }

    func removeFile(named storedFileName: String) throws {
        removedFileNames.append(storedFileName)
        storedFiles[storedFileName] = nil
    }

    func fileExists(named storedFileName: String) -> Bool {
        storedFiles[storedFileName] != nil
    }
}

// MARK: - Widget snapshot

/// Records what the app would have published to the widget, so a test can assert
/// that a rule triggered a refresh and that only reduced data crossed the boundary.
final class MockSnapshotPublisher: InspectionSnapshotPublishing {

    private(set) var publishedSnapshots: [InspectionSnapshot] = []

    var lastSnapshot: InspectionSnapshot? { publishedSnapshots.last }

    func publish(_ snapshot: InspectionSnapshot) {
        publishedSnapshots.append(snapshot)
    }
}
