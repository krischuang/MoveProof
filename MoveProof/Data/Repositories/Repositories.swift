import Foundation

/// Thrown when storage itself fails. Infrastructure, not domain: nothing in here is a
/// rule a tenant broke, so it is never shown as written.
///
/// A use case translates this into its own error where failing part way through a
/// write leaves the tenant needing to know which half happened. Otherwise it travels
/// to `TenantMessage`, which wraps it in `UnexpectedFailure`, and the technical detail
/// goes to `AppLog`.
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
/// Written entirely in domain value types, with no `NSManagedObject` and no
/// `NSFetchRequest`, so a test can swap in an in-memory mock without Core Data.
protocol TenancyRepository {

    /// The tenancy the tenant is currently documenting.
    ///
    /// Uses a predicate on tenancy status instead of fetching everything and
    /// filtering, since "active" is a condition the store can answer itself.
    func fetchActiveTenancy() throws -> Tenancy?

    func fetchTenancy(id: UUID) throws -> Tenancy?

    /// Inserts a new tenancy or updates the existing one with the same id.
    func save(_ tenancy: Tenancy) throws

    func delete(tenancyID: UUID) throws
}

// MARK: - Inspection

/// Storage of rooms and their condition checklists.
protocol InspectionRepository {

    func fetchAreas(forTenancy tenancyID: UUID) throws -> [InspectionArea]

    func fetchArea(id: UUID) throws -> InspectionArea?

    func fetchConditionItems(inArea areaID: UUID) throws -> [ConditionItem]

    func fetchConditionItem(id: UUID) throws -> ConditionItem?

    /// Condition items across the whole tenancy that record damage or a fault but
    /// carry neither a note nor a single piece of evidence.
    ///
    /// The main query the app is built around. A compound predicate across a
    /// relationship: the state is damaging, the notes are empty, and there is no
    /// evidence attached.
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
    /// The predicate on `importedInboxItemID` is what makes importing idempotent.
    /// The same shared file cannot be filed twice, even if Import is tapped again.
    func fetchEvidence(importedFromInboxItem inboxItemID: UUID) throws -> EvidenceItem?

    /// Count of evidence attached to a condition item, without loading the files.
    func evidenceCount(forConditionItem conditionItemID: UUID) throws -> Int

    func save(_ evidence: EvidenceItem) throws

    func delete(evidenceID: UUID) throws
}

// MARK: - Evidence files

/// App-controlled storage of the evidence binaries.
///
/// Behind a protocol for the same reason as the repositories, so use case tests can
/// run the import rules without writing real files to disk.
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
