import Foundation

/// Deletes a photo or document the tenant no longer wants, and the file behind it.
///
/// The database row is deleted before the file. A leftover file is invisible to the
/// tenant, whereas a leftover row would show in the library as evidence that will not
/// open. Discarding something that has already gone is not treated as a failure.
///
/// Deleting the only photo backing a damaged checklist item turns that damage back
/// into a bare tick, which is the problem the app is built to prevent, so the outcome
/// reports it and the screen can warn the tenant. It warns instead of refusing: the
/// evidence belongs to them and they may have a good reason.
/// `CompleteInspectionAreaUseCase` re-checks the room at sign-off anyway.
///
/// The one thing that is a failure is the row refusing to go, since the tenant asked
/// for it and it is still there. That comes out as
/// `EvidenceFilingError.couldNotDiscardEvidence` rather than as a `RepositoryError`,
/// so the message says the evidence is still in the library instead of saying nothing
/// useful at all.
struct DiscardEvidenceUseCase {

    let inspectionRepository: InspectionRepository
    let evidenceRepository: EvidenceRepository
    let evidenceFileStore: EvidenceFileStore

    init(
        inspectionRepository: InspectionRepository,
        evidenceRepository: EvidenceRepository,
        evidenceFileStore: EvidenceFileStore
    ) {
        self.inspectionRepository = inspectionRepository
        self.evidenceRepository = evidenceRepository
        self.evidenceFileStore = evidenceFileStore
    }

    struct Outcome: Equatable {

        /// Title of the checklist item now left with damage recorded and nothing
        /// to show for it, or `nil` if nothing was affected.
        let leftDamageUndocumented: String?

        static let nothingToReport = Outcome(leftDamageUndocumented: nil)
    }

    /// - Returns: what the discard left behind, for the screen to surface.
    /// - Throws: `EvidenceFilingError.couldNotDiscardEvidence` when the record itself
    ///   cannot be removed.
    @discardableResult
    func execute(evidenceID: UUID) throws -> Outcome {

        let evidence: EvidenceItem?
        do {
            evidence = try evidenceRepository.fetchEvidence(id: evidenceID)
        } catch {
            AppLog.evidence.error("Could not look up evidence \(evidenceID) before discarding it: \(error)")
            throw EvidenceFilingError.couldNotDiscardEvidence
        }

        // Already gone is what the tenant wanted, so it is an outcome, not a failure.
        guard let evidence else { return .nothingToReport }

        do {
            try evidenceRepository.delete(evidenceID: evidenceID)
        } catch {
            AppLog.evidence.error("Could not discard evidence \(evidenceID): \(error)")
            throw EvidenceFilingError.couldNotDiscardEvidence
        }

        // A file that will not delete is not worth failing over. The record is
        // already gone, which is what the tenant asked for.
        do {
            try evidenceFileStore.removeFile(named: evidence.storedFileName)
        } catch {
            AppLog.evidence.error("Discarded evidence \(evidenceID) but could not remove its file: \(error)")
        }

        return Outcome(leftDamageUndocumented: undocumentedItemTitle(after: evidence))
    }

    /// The checklist item this was backing up, if losing it leaves that item's
    /// damage with no note and no other photo.
    ///
    /// Does not throw: by this point the discard has already happened, so a failed
    /// lookup means the warning cannot be worked out, not that the operation failed.
    /// Sign-off re-checks the room anyway, so the gap is still caught there.
    private func undocumentedItemTitle(after evidence: EvidenceItem) -> String? {
        guard let conditionItemID = evidence.conditionItemID else { return nil }
        do {
            guard let item = try inspectionRepository.fetchConditionItem(id: conditionItemID),
                  item.conditionState.requiresSupportingDetail else { return nil }

            let remaining = try evidenceRepository.evidenceCount(forConditionItem: conditionItemID)
            return item.isFullyDocumented(evidenceCount: remaining) ? nil : item.title
        } catch {
            AppLog.evidence.error("Discarded evidence \(evidence.id) but could not re-check its checklist item: \(error)")
            return nil
        }
    }
}
