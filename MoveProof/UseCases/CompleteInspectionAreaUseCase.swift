import Foundation

/// Signs a room off as reviewed.
///
/// ## Rules enforced
/// 1. The room must still exist.
/// 2. A room already signed off is not signed off twice.
/// 3. **Every required checklist item must be reviewed.** A room cannot be marked
///    complete while items in it are still unanswered. That is how gaps in a
///    condition report happen.
/// 4. **No damage may be left undocumented.** Even if every item has an answer, a
///    `damaged` or `notWorking` item with no note and no photo blocks sign-off,
///    because that record would mean nothing later.
///
/// Rule 4 checks again what `RecordConditionEvidenceUseCase` already checked. Photos
/// can be deleted afterwards, so sign-off looks at the room as it is now instead of
/// trusting that it was fine when first recorded.
struct CompleteInspectionAreaUseCase {

    let inspectionRepository: InspectionRepository
    let evidenceRepository: EvidenceRepository

    init(inspectionRepository: InspectionRepository, evidenceRepository: EvidenceRepository) {
        self.inspectionRepository = inspectionRepository
        self.evidenceRepository = evidenceRepository
    }

    /// - Returns: the room, now marked complete.
    /// - Throws: `InspectionCompletionError` when a rule is broken.
    @discardableResult
    func execute(areaID: UUID) throws -> InspectionArea {

        // Rule 1
        guard var area = try inspectionRepository.fetchArea(id: areaID) else {
            throw InspectionCompletionError.inspectionAreaNotFound
        }

        // Rule 2
        guard area.inspectionStatus != .complete else {
            throw InspectionCompletionError.inspectionAlreadyComplete(areaName: area.name)
        }

        let items = try inspectionRepository.fetchConditionItems(inArea: areaID)

        // Rule 3
        let unreviewed = items.filter { $0.isRequired && !$0.isReviewed }
        if let first = unreviewed.first {
            throw InspectionCompletionError.uncheckedConditionItemsRemain(
                count: unreviewed.count,
                firstItemTitle: first.title
            )
        }

        // Rule 4
        var undocumentedDamageCount = 0
        for item in items where item.conditionState.requiresSupportingDetail {
            let evidenceCount = try evidenceRepository.evidenceCount(forConditionItem: item.id)
            if !item.isFullyDocumented(evidenceCount: evidenceCount) {
                undocumentedDamageCount += 1
            }
        }
        if undocumentedDamageCount > 0 {
            throw InspectionCompletionError.undocumentedDamageRemains(count: undocumentedDamageCount)
        }

        area.inspectionStatus = .complete
        try inspectionRepository.save(area)
        return area
    }
}
