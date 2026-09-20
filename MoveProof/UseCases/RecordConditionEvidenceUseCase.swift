import Foundation

/// Records what the tenant found for one checklist item, and enforces MoveProof's
/// central rule about damage.
///
/// ## Rules enforced
/// 1. The checklist item must still exist in the walkthrough.
/// 2. A condition must actually be chosen — `notReviewed` is a starting value,
///    not an answer.
/// 3. **Damage needs backing up.** A condition of `damaged` or `notWorking` is
///    refused unless the tenant has written a note or attached at least one piece
///    of evidence. This is the whole point of the app: a bare "damaged" tick is
///    worthless months later when the tenant has to explain what they saw.
/// 4. Evidence attached to the item must belong to the same tenancy.
///
/// Recording a condition also moves the room from `notStarted` to `inProgress`,
/// so the room list reflects the walkthrough without the tenant managing status
/// by hand.
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

        // Rule 4: check provenance before anything is written.
        for evidence in request.evidenceToAttach where evidence.tenancyID != area.tenancyID {
            throw ConditionRecordingError.evidenceBelongsToAnotherTenancy
        }

        let trimmedNotes = request.notes.trimmingCharacters(in: .whitespacesAndNewlines)

        // Rule 3: damage must carry something the tenant can recognise later.
        // Evidence already filed against this item counts, so re-saving a
        // previously documented item does not suddenly fail.
        if request.conditionState.requiresSupportingDetail {
            let alreadyFiled = try evidenceRepository.evidenceCount(forConditionItem: item.id)
            let totalEvidence = alreadyFiled + request.evidenceToAttach.count
            if trimmedNotes.isEmpty && totalEvidence == 0 {
                throw ConditionRecordingError.damagedConditionNeedsSupportingDetail(itemTitle: item.title)
            }
        }

        // All rules passed — write the evidence first so the checklist item is
        // never left claiming support that was not actually saved.
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

    /// A room that has had something recorded in it is no longer "not started".
    /// Sign-off stays a deliberate act, handled by `CompleteInspectionAreaUseCase`.
    private func advanceAreaStatusIfNeeded(_ area: InspectionArea) throws {
        guard area.inspectionStatus == .notStarted else { return }
        var updated = area
        updated.inspectionStatus = .inProgress
        try inspectionRepository.save(updated)
    }
}
