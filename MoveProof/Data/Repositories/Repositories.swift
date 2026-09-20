import Foundation

/// Thrown when persistence itself fails. Use cases let this propagate; the
/// presentation layer wraps it in `UnexpectedFailure` so the tenant sees a humane
/// message while the technical detail goes to the log.
enum RepositoryError: Error {
    case tenancyNotFound(UUID)
    case inspectionAreaNotFound(UUID)
    case conditionItemNotFound(UUID)
    case evidenceNotFound(UUID)
    case saveFailed(underlying: Error)
    case fetchFailed(underlying: Error)
}

// MARK: - Tenancy

/// Storage of the property being documented.
///
/// Expressed entirely in domain value types — no `NSManagedObject`, no
/// `NSFetchRequest` — so a test can substitute an in-memory mock without Core Data.
protocol TenancyRepository {

    /// The tenancy the tenant is currently documenting.
    ///
    /// Backed by a predicate on tenancy status rather than a fetch-everything-and-filter,
    /// because "active" is a domain condition the store can answer directly.
    func fetchActiveTenancy() throws -> Tenancy?

    /// Every tenancy, newest first, for the archive.
    func fetchAllTenancies() throws -> [Tenancy]

    func fetchTenancy(id: UUID) throws -> Tenancy?

    /// Inserts a new tenancy or updates the existing one with the same id.
    func save(_ tenancy: Tenancy) throws

    func delete(tenancyID: UUID) throws
}

// MARK: - Inspection

/// Storage of rooms and their condition checklists.
protocol InspectionRepository {

    func fetchAreas(forTenancy tenancyID: UUID) throws -> [InspectionArea]

    /// Rooms still needing work — a predicate query on inspection status, used by
    /// the dashboard's "needs attention" list and by the progress summary.
    func fetchIncompleteInspectionAreas(forTenancy tenancyID: UUID) throws -> [InspectionArea]

    func fetchArea(id: UUID) throws -> InspectionArea?

    func fetchConditionItems(inArea areaID: UUID) throws -> [ConditionItem]

    func fetchConditionItem(id: UUID) throws -> ConditionItem?

    /// Condition items across the whole tenancy that record damage or a fault but
    /// carry neither a note nor a single piece of evidence.
    ///
    /// This is the query MoveProof exists for, and it is a compound Core Data
    /// predicate spanning a relationship: state is damaging, notes are empty, and
    /// the evidence relationship is empty.
    func fetchConditionItemsMissingSupportingDetail(forTenancy tenancyID: UUID) throws -> [ConditionItem]

    /// Creates rooms and their seeded checklists in one write.
    func createAreas(_ areas: [InspectionArea], withItems items: [UUID: [ConditionItem]]) throws

    func save(_ area: InspectionArea) throws

    func save(_ conditionItem: ConditionItem) throws

    func deleteArea(id: UUID) throws
}

// MARK: - Evidence

/// Storage of evidence metadata. The files themselves are handled by `EvidenceFileStore`.
protocol EvidenceRepository {

    func fetchEvidence(forTenancy tenancyID: UUID) throws -> [EvidenceItem]

    func fetchEvidence(forConditionItem conditionItemID: UUID) throws -> [EvidenceItem]

    /// Evidence filed against the tenancy but not yet attached to a room checklist item.
    func fetchUnassignedEvidence(forTenancy tenancyID: UUID) throws -> [EvidenceItem]

    func fetchEvidence(id: UUID) throws -> EvidenceItem?

    /// Looks up evidence that was imported from a given Share Extension inbox record.
    ///
    /// A predicate on `importedInboxItemID` is what makes importing idempotent: the
    /// same shared file cannot be filed twice, even if the tenant taps Import again.
    func fetchEvidence(importedFromInboxItem inboxItemID: UUID) throws -> EvidenceItem?

    /// Count of evidence attached to a condition item, without loading the files.
    func evidenceCount(forConditionItem conditionItemID: UUID) throws -> Int

    func save(_ evidence: EvidenceItem) throws

    func delete(evidenceID: UUID) throws
}

// MARK: - Evidence files

/// App-controlled storage of the evidence binaries.
///
/// Kept behind a protocol for the same reason as the repositories: use case tests
/// must be able to run the import rules without writing real files to disk.
protocol EvidenceFileStore {

    /// Moves a file from elsewhere (such as the Share Extension inbox) into
    /// MoveProof's own evidence directory.
    ///
    /// - Returns: the stored file name, relative to the evidence directory.
    func adopt(fileAt sourceURL: URL, preferredExtension: String) throws -> String

    /// Writes raw bytes as a new evidence file.
    func store(data: Data, preferredExtension: String) throws -> String

    /// Absolute URL for a stored file, for display.
    func url(forStoredFileName storedFileName: String) throws -> URL

    func removeFile(named storedFileName: String) throws

    func fileExists(named storedFileName: String) -> Bool
}
