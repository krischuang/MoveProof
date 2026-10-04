import CoreData

/// Core Data implementation of `InspectionRepository`.
struct CoreDataInspectionRepository: InspectionRepository {

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Areas

    func fetchAreas(forTenancy tenancyID: UUID) throws -> [InspectionArea] {
        let request = InspectionAreaEntity.fetchRequest()
        request.predicate = NSPredicate(format: "tenancy.id == %@", tenancyID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "displayOrder", ascending: true)]
        do {
            return try context.fetch(request).compactMap(ManagedObjectMapping.inspectionArea(from:))
        } catch {
            throw RepositoryError.fetchFailed(underlying: error)
        }
    }

    func fetchArea(id: UUID) throws -> InspectionArea? {
        try managedArea(id: id).flatMap(ManagedObjectMapping.inspectionArea(from:))
    }

    // MARK: - Condition items

    func fetchConditionItems(inArea areaID: UUID) throws -> [ConditionItem] {
        let request = ConditionItemEntity.fetchRequest()
        request.predicate = NSPredicate(format: "inspectionArea.id == %@", areaID as CVarArg)
        request.sortDescriptors = [
            NSSortDescriptor(key: "categoryRaw", ascending: true),
            NSSortDescriptor(key: "title", ascending: true)
        ]
        do {
            return try context.fetch(request).compactMap(ManagedObjectMapping.conditionItem(from:))
        } catch {
            throw RepositoryError.fetchFailed(underlying: error)
        }
    }

    func fetchConditionItem(id: UUID) throws -> ConditionItem? {
        try managedConditionItem(id: id).flatMap(ManagedObjectMapping.conditionItem(from:))
    }

    /// The query the app is built around: damage recorded with nothing to back it up.
    ///
    /// Three conditions in one compound predicate, crossing two relationships
    /// (`inspectionArea.tenancy`) and counting a third (`evidence.@count`), so the
    /// store returns only the rows that matter instead of the app loading every
    /// checklist item and filtering in memory.
    func fetchConditionItemsMissingSupportingDetail(forTenancy tenancyID: UUID) throws -> [ConditionItem] {
        let request = ConditionItemEntity.fetchRequest()
        let damagingStates = [ConditionState.damaged.rawValue, ConditionState.notWorking.rawValue]

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "inspectionArea.tenancy.id == %@", tenancyID as CVarArg),
            NSPredicate(format: "conditionStateRaw IN %@", damagingStates),
            NSPredicate(format: "notes == %@", ""),
            NSPredicate(format: "evidence.@count == 0")
        ])
        request.sortDescriptors = [
            NSSortDescriptor(key: "inspectionArea.displayOrder", ascending: true),
            NSSortDescriptor(key: "title", ascending: true)
        ]

        do {
            return try context.fetch(request).compactMap(ManagedObjectMapping.conditionItem(from:))
        } catch {
            throw RepositoryError.fetchFailed(underlying: error)
        }
    }

    // MARK: - Writing

    func createAreas(_ areas: [InspectionArea], withItems items: [UUID: [ConditionItem]]) throws {
        for area in areas {
            guard let tenancyEntity = try managedTenancy(id: area.tenancyID) else {
                throw RepositoryError.tenancyNotFound(area.tenancyID)
            }
            let areaEntity = InspectionAreaEntity(context: context)
            ManagedObjectMapping.apply(area, to: areaEntity)
            areaEntity.tenancy = tenancyEntity

            for item in items[area.id] ?? [] {
                let itemEntity = ConditionItemEntity(context: context)
                ManagedObjectMapping.apply(item, to: itemEntity)
                itemEntity.inspectionArea = areaEntity
            }
        }
        try commit()
    }

    func save(_ area: InspectionArea) throws {
        let entity: InspectionAreaEntity
        if let existing = try managedArea(id: area.id) {
            entity = existing
        } else {
            guard let tenancyEntity = try managedTenancy(id: area.tenancyID) else {
                throw RepositoryError.tenancyNotFound(area.tenancyID)
            }
            entity = InspectionAreaEntity(context: context)
            entity.tenancy = tenancyEntity
        }
        ManagedObjectMapping.apply(area, to: entity)
        try commit()
    }

    func save(_ conditionItem: ConditionItem) throws {
        let entity: ConditionItemEntity
        if let existing = try managedConditionItem(id: conditionItem.id) {
            entity = existing
        } else {
            guard let areaEntity = try managedArea(id: conditionItem.inspectionAreaID) else {
                throw RepositoryError.inspectionAreaNotFound(conditionItem.inspectionAreaID)
            }
            entity = ConditionItemEntity(context: context)
            entity.inspectionArea = areaEntity
        }
        ManagedObjectMapping.apply(conditionItem, to: entity)
        try commit()
    }

    func deleteArea(id: UUID) throws {
        guard let entity = try managedArea(id: id) else {
            throw RepositoryError.inspectionAreaNotFound(id)
        }
        // Cascade removes the room's checklist; the Nullify rule on ConditionItem →
        // evidence keeps the photos in the library instead of deleting them.
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

    private func managedArea(id: UUID) throws -> InspectionAreaEntity? {
        let request = InspectionAreaEntity.fetchRequest()
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
