import CoreData

/// Core Data implementation of `EvidenceRepository`.
///
/// Stores metadata only. The photograph or PDF itself lives in the App Group
/// evidence directory, referenced by `storedFileName`.
struct CoreDataEvidenceRepository: EvidenceRepository {

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func fetchEvidence(forTenancy tenancyID: UUID) throws -> [EvidenceItem] {
        try fetch(
            predicate: NSPredicate(format: "tenancy.id == %@", tenancyID as CVarArg)
        )
    }

    func fetchEvidence(forConditionItem conditionItemID: UUID) throws -> [EvidenceItem] {
        try fetch(
            predicate: NSPredicate(format: "conditionItem.id == %@", conditionItemID as CVarArg)
        )
    }

    /// Evidence filed against the property but not yet pinned to a checklist item —
    /// the "needs filing" pile the evidence library surfaces.
    func fetchUnassignedEvidence(forTenancy tenancyID: UUID) throws -> [EvidenceItem] {
        try fetch(
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "tenancy.id == %@", tenancyID as CVarArg),
                NSPredicate(format: "conditionItem == nil")
            ])
        )
    }

    func fetchEvidence(id: UUID) throws -> EvidenceItem? {
        try managedEvidence(id: id).flatMap(ManagedObjectMapping.evidence(from:))
    }

    /// Makes shared-evidence import idempotent by asking the store whether this
    /// inbox record has already produced an evidence row.
    func fetchEvidence(importedFromInboxItem inboxItemID: UUID) throws -> EvidenceItem? {
        let request = EvidenceItemEntity.fetchRequest()
        request.predicate = NSPredicate(format: "importedInboxItemID == %@", inboxItemID as CVarArg)
        request.fetchLimit = 1
        do {
            return try context.fetch(request).compactMap(ManagedObjectMapping.evidence(from:)).first
        } catch {
            throw RepositoryError.fetchFailed(underlying: error)
        }
    }

    func evidenceCount(forConditionItem conditionItemID: UUID) throws -> Int {
        let request = EvidenceItemEntity.fetchRequest()
        request.predicate = NSPredicate(format: "conditionItem.id == %@", conditionItemID as CVarArg)
        do {
            // `count(for:)` keeps the objects out of memory — the UI only needs the number.
            return try context.count(for: request)
        } catch {
            throw RepositoryError.fetchFailed(underlying: error)
        }
    }

    func save(_ evidence: EvidenceItem) throws {
        let entity: EvidenceItemEntity
        if let existing = try managedEvidence(id: evidence.id) {
            entity = existing
        } else {
            guard let tenancyEntity = try managedTenancy(id: evidence.tenancyID) else {
                throw RepositoryError.tenancyNotFound(evidence.tenancyID)
            }
            entity = EvidenceItemEntity(context: context)
            entity.tenancy = tenancyEntity
        }

        ManagedObjectMapping.apply(evidence, to: entity)

        // Re-resolve the checklist link every save so evidence can be filed,
        // re-filed or unfiled without going through a separate code path.
        if let conditionItemID = evidence.conditionItemID {
            guard let itemEntity = try managedConditionItem(id: conditionItemID) else {
                throw RepositoryError.conditionItemNotFound(conditionItemID)
            }
            entity.conditionItem = itemEntity
        } else {
            entity.conditionItem = nil
        }

        try commit()
    }

    func delete(evidenceID: UUID) throws {
        guard let entity = try managedEvidence(id: evidenceID) else {
            throw RepositoryError.evidenceNotFound(evidenceID)
        }
        context.delete(entity)
        try commit()
    }

    // MARK: - Internals

    private func fetch(predicate: NSPredicate) throws -> [EvidenceItem] {
        let request = EvidenceItemEntity.fetchRequest()
        request.predicate = predicate
        request.sortDescriptors = [NSSortDescriptor(key: "capturedAt", ascending: false)]
        do {
            return try context.fetch(request).compactMap(ManagedObjectMapping.evidence(from:))
        } catch {
            throw RepositoryError.fetchFailed(underlying: error)
        }
    }

    private func managedEvidence(id: UUID) throws -> EvidenceItemEntity? {
        let request = EvidenceItemEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        do {
            return try context.fetch(request).first
        } catch {
            throw RepositoryError.fetchFailed(underlying: error)
        }
    }

    private func managedTenancy(id: UUID) throws -> TenancyEntity? {
        let request = TenancyEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        do {
            return try context.fetch(request).first
        } catch {
            throw RepositoryError.fetchFailed(underlying: error)
        }
    }

    private func managedConditionItem(id: UUID) throws -> ConditionItemEntity? {
        let request = ConditionItemEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        do {
            return try context.fetch(request).first
        } catch {
            throw RepositoryError.fetchFailed(underlying: error)
        }
    }

    private func commit() throws {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw RepositoryError.saveFailed(underlying: error)
        }
    }
}
