import Foundation

/// Removes a room from the walkthrough, either one the tenant added by mistake or a
/// default room the property does not have.
///
/// Evidence survives the room it was filed against. Deleting a room cascades to its
/// checklist items, but the checklist item to evidence relationship is set to
/// nullify, not cascade, so the photos stay in the library and become unfiled. That
/// was a schema choice: a photo of a scratched floor taken on move-in day cannot be
/// taken again.
///
/// The tenant is told how many photos this affected, which is why this is a use case
/// and not a plain repository call. The count has to be taken before the delete,
/// because afterwards the checklist items it counted against are gone. Removing a
/// room that has already gone is not treated as a failure.
///
/// A room that will not delete is a different outcome from one that was already gone.
/// Everything that can fail runs before the delete, so a refusal means nothing changed.
struct RemoveInspectionAreaUseCase {

    let inspectionRepository: InspectionRepository
    let evidenceRepository: EvidenceRepository

    init(inspectionRepository: InspectionRepository, evidenceRepository: EvidenceRepository) {
        self.inspectionRepository = inspectionRepository
        self.evidenceRepository = evidenceRepository
    }

    struct Outcome: Equatable {

        /// Whether a room was actually there to remove.
        let didRemoveRoom: Bool

        /// How many photos and documents are now back in the library unfiled.
        let detachedEvidenceCount: Int

        static let roomAlreadyGone = Outcome(didRemoveRoom: false, detachedEvidenceCount: 0)
    }

    /// - Returns: what the removal left behind, for the screen to surface.
    /// - Throws: `InspectionAreaEditError.couldNotRemoveRoom` when the store cannot
    ///   complete the removal.
    @discardableResult
    func execute(areaID: UUID) throws -> Outcome {

        guard try roomExists(areaID) else {
            return .roomAlreadyGone
        }

        do {
            // Count now, while the checklist items still exist.
            let items = try inspectionRepository.fetchConditionItems(inArea: areaID)
            var detachedEvidenceCount = 0
            for item in items {
                detachedEvidenceCount += try evidenceRepository.evidenceCount(forConditionItem: item.id)
            }

            // The nullify delete rule is what keeps the evidence.
            try inspectionRepository.deleteArea(id: areaID)

            return Outcome(didRemoveRoom: true, detachedEvidenceCount: detachedEvidenceCount)
        } catch {
            AppLog.inspection.error("Could not remove room \(areaID): \(error)")
            throw InspectionAreaEditError.couldNotRemoveRoom
        }
    }

    /// A room that is absent is a normal outcome; a lookup that fails is not, because
    /// then MoveProof does not know whether there was a room to remove.
    private func roomExists(_ areaID: UUID) throws -> Bool {
        do {
            return try inspectionRepository.fetchArea(id: areaID) != nil
        } catch {
            AppLog.inspection.error("Could not look up room \(areaID) before removing it: \(error)")
            throw InspectionAreaEditError.couldNotRemoveRoom
        }
    }
}
