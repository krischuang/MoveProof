import Foundation

/// Records what the tenant found for one checklist item. This is where the main
/// rule about damage is enforced.
///
/// ## Rules enforced
/// 1. The checklist item must still exist.
/// 2. A condition must be chosen. `notReviewed` is the starting value, not an answer.
/// 3. **Damage needs backing up.** A condition of `damaged` or `notWorking` is
///    refused unless there is a note or at least one photo. This is the main point
///    of the app. A bare "damaged" tick is no use months later when the tenant has
///    to explain what they saw.
/// 4. Any evidence attached must belong to the same tenancy.
///
/// Recording a condition also moves the room from `notStarted` to `inProgress`, so
/// the room list stays up to date without the tenant setting the status by hand.
struct RecordConditionEvidenceUseCase {

    let inspectionRepository: InspectionRepository
    let evidenceRepository: EvidenceRepository

    init(inspectionRepository: InspectionRepository, evidenceRepository: EvidenceRepository) {
        self.inspectionRepository = inspectionRepository
        self.evidenceRepository = evidenceRepository
    }

    struct Request {
        var conditionItemID: UUID
        var conditionState: ConditionState
        var notes: String
        /// Evidence the tenant is attaching as part of this recording. Already-filed
        /// evidence counts towards rule 3 as well.
        var evidenceToAttach: [EvidenceItem] = []
    }

    /// - Returns: the updated checklist item.
    /// - Throws: `ConditionRecordingError` when a rule is broken.
    @discardableResult
    func execute(_ request: Request, now: Date = Date()) throws -> ConditionItem {

        // Rule 1
        guard var item = try inspectionRepository.fetchConditionItem(id: request.conditionItemID) else {
            throw ConditionRecordingError.conditionItemNotFound
        }
        guard let area = try inspectionRepository.fetchArea(id: item.inspectionAreaID) else {
            throw ConditionRecordingError.inspectionAreaNotFound
        }

        // Rule 2
        guard request.conditionState != .notReviewed else {
            throw ConditionRecordingError.conditionStateNotChosen
        }

        // Rule 4: check where the evidence came from before writing anything.
        for evidence in request.evidenceToAttach where evidence.tenancyID != area.tenancyID {
            throw ConditionRecordingError.evidenceBelongsToAnotherTenancy
        }

        let trimmedNotes = request.notes.trimmingCharacters(in: .whitespacesAndNewlines)

        // Rule 3: damage needs something the tenant can recognise later. Photos
        // already filed against this item count, so re-saving an item that was
        // documented earlier does not suddenly fail.
        if request.conditionState.requiresSupportingDetail {
            let alreadyFiled = try evidenceRepository.evidenceCount(forConditionItem: item.id)
            let totalEvidence = alreadyFiled + request.evidenceToAttach.count
            if trimmedNotes.isEmpty && totalEvidence == 0 {
                throw ConditionRecordingError.damagedConditionNeedsSupportingDetail(itemTitle: item.title)
            }
        }

        // Rules passed. Save the evidence first so the checklist item is never
        // left claiming backup that did not actually save.
        for var evidence in request.evidenceToAttach {
            evidence.conditionItemID = item.id
            try evidenceRepository.save(evidence)
        }

        item.conditionState = request.conditionState
        item.notes = trimmedNotes
        item.reviewedAt = now
        try inspectionRepository.save(item)

        try advanceAreaStatusIfNeeded(area)

        return item
    }

    /// A room with something recorded in it is no longer "not started". Signing it
    /// off is a separate action, handled by `CompleteInspectionAreaUseCase`.
    private func advanceAreaStatusIfNeeded(_ area: InspectionArea) throws {
        guard area.inspectionStatus == .notStarted else { return }
        var updated = area
        updated.inspectionStatus = .inProgress
        try inspectionRepository.save(updated)
    }
}
