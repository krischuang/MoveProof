import Foundation

/// Signs a room off as reviewed.
///
/// ## Rules enforced
/// 1. The room must still exist in the walkthrough.
/// 2. A room already signed off is not signed off twice.
/// 3. **Every required checklist item must have been reviewed.** A room cannot be
///    marked complete while the tenant still has unanswered items in it — that is
///    how gaps in a condition report happen.
/// 4. **No damage may be left undocumented.** Even if every item has an answer, a
///    `damaged` or `notWorking` item with neither a note nor a photo blocks
///    sign-off, because the record would not mean anything later.
///
/// Rule 4 deliberately re-checks what `RecordConditionEvidenceUseCase` already
/// enforces. Evidence can be deleted after the fact, so sign-off verifies the
/// room's current state rather than trusting that it was valid when recorded.
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
