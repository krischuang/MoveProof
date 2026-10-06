import CoreData

/// Core Data implementation of `TenancyRepository`.
///
/// This type is the only place in MoveProof that knows a tenancy is stored as a
/// `TenancyEntity`. Callers hand it `Tenancy` values and get `Tenancy` values back.
struct CoreDataTenancyRepository: TenancyRepository {

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func fetchActiveTenancy() throws -> Tenancy? {
        let request = TenancyEntity.fetchRequest()
        // Domain condition expressed as a predicate: "the tenancy still being
        // documented", not "everything, then filtered in Swift".
        request.predicate = NSPredicate(
            format: "statusRaw IN %@",
            [TenancyStatus.documenting.rawValue, TenancyStatus.reportReady.rawValue]
        )
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = 1

        do {
            return try context.fetch(request).compactMap { ManagedObjectMapping.tenancy(from: $0) }.first
        } catch {
            throw RepositoryError.fetchFailed(underlying: error)
        }
    }

    func fetchTenancy(id: UUID) throws -> Tenancy? {
        try managedTenancy(id: id).flatMap { ManagedObjectMapping.tenancy(from: $0) }
    }

    func save(_ tenancy: Tenancy) throws {
        let entity = try managedTenancy(id: tenancy.id) ?? TenancyEntity(context: context)
        ManagedObjectMapping.apply(tenancy, to: entity)
        try commit()
    }

    func delete(tenancyID: UUID) throws {
        guard let entity = try managedTenancy(id: tenancyID) else {
            throw RepositoryError.tenancyNotFound(tenancyID)
        }
        // Cascade rules remove the rooms, checklist items and evidence metadata.
        context.delete(entity)
        try commit()
    }

    // MARK: - Internals

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
