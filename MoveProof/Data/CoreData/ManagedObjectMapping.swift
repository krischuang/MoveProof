import CoreData

/// Translates between Core Data managed objects and the domain value types.
///
/// Keeping the mapping in one place is what lets the domain stay free of Core Data:
/// enums are stored as their raw strings here and nowhere else, and an unrecognised
/// raw value falls back to a safe default instead of crashing mid-walkthrough.
enum ManagedObjectMapping {

    // MARK: - Tenancy

    static func tenancy(from entity: TenancyEntity) -> Tenancy? {
        guard let id = entity.id else { return nil }
        return Tenancy(
            id: id,
            propertyAddress: entity.propertyAddress ?? "",
            moveInDate: entity.moveInDate ?? Date(),
            conditionReportDueDate: entity.conditionReportDueDate ?? Date(),
            createdAt: entity.createdAt ?? Date(),
            status: TenancyStatus(rawValue: entity.statusRaw ?? "") ?? .documenting
        )
    }

    static func apply(_ tenancy: Tenancy, to entity: TenancyEntity) {
        entity.id = tenancy.id
        entity.propertyAddress = tenancy.propertyAddress
        entity.moveInDate = tenancy.moveInDate
        entity.conditionReportDueDate = tenancy.conditionReportDueDate
        entity.createdAt = tenancy.createdAt
        entity.statusRaw = tenancy.status.rawValue
    }

    // MARK: - Inspection area

    static func inspectionArea(from entity: InspectionAreaEntity) -> InspectionArea? {
        guard let id = entity.id, let tenancyID = entity.tenancy?.id else { return nil }
        return InspectionArea(
            id: id,
            name: entity.name ?? "",
            inspectionStatus: AreaInspectionStatus(rawValue: entity.inspectionStatusRaw ?? "") ?? .notStarted,
            displayOrder: Int(entity.displayOrder),
            tenancyID: tenancyID
        )
    }

    static func apply(_ area: InspectionArea, to entity: InspectionAreaEntity) {
        entity.id = area.id
        entity.name = area.name
        entity.inspectionStatusRaw = area.inspectionStatus.rawValue
        entity.displayOrder = Int16(clamping: area.displayOrder)
    }

    // MARK: - Condition item

    static func conditionItem(from entity: ConditionItemEntity) -> ConditionItem? {
        guard let id = entity.id, let areaID = entity.inspectionArea?.id else { return nil }
        return ConditionItem(
            id: id,
            title: entity.title ?? "",
            category: ConditionItemCategory(rawValue: entity.categoryRaw ?? "") ?? .structure,
            conditionState: ConditionState(rawValue: entity.conditionStateRaw ?? "") ?? .notReviewed,
            notes: entity.notes ?? "",
            reviewedAt: entity.reviewedAt,
            isRequired: entity.isRequired,
            inspectionAreaID: areaID
        )
    }

    static func apply(_ item: ConditionItem, to entity: ConditionItemEntity) {
        entity.id = item.id
        entity.title = item.title
        entity.categoryRaw = item.category.rawValue
        entity.conditionStateRaw = item.conditionState.rawValue
        entity.notes = item.notes
        entity.reviewedAt = item.reviewedAt
        entity.isRequired = item.isRequired
    }

    // MARK: - Evidence

    static func evidence(from entity: EvidenceItemEntity) -> EvidenceItem? {
        guard let id = entity.id, let tenancyID = entity.tenancy?.id else { return nil }
        return EvidenceItem(
            id: id,
            kind: EvidenceKind(rawValue: entity.kindRaw ?? "") ?? .document,
            storedFileName: entity.storedFileName ?? "",
            displayName: entity.displayName ?? "",
            capturedAt: entity.capturedAt ?? Date(),
            notes: entity.notes ?? "",
            source: EvidenceSource(rawValue: entity.sourceRaw ?? "") ?? .capturedInApp,
            conditionItemID: entity.conditionItem?.id,
            tenancyID: tenancyID,
            importedInboxItemID: entity.importedInboxItemID
        )
    }

    static func apply(_ evidence: EvidenceItem, to entity: EvidenceItemEntity) {
        entity.id = evidence.id
        entity.kindRaw = evidence.kind.rawValue
        entity.storedFileName = evidence.storedFileName
        entity.displayName = evidence.displayName
        entity.capturedAt = evidence.capturedAt
        entity.notes = evidence.notes
        entity.sourceRaw = evidence.source.rawValue
        entity.importedInboxItemID = evidence.importedInboxItemID
    }
}
