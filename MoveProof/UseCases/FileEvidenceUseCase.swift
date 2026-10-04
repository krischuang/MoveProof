import Foundation

/// Files a photo or document the tenant already has against a checklist item, and
/// records what it shows.
///
/// Where the evidence belongs and what it shows are treated as one operation. A
/// photo pinned to "Kitchen - Flooring" with the note "scratch under the fridge" is
/// what makes that damage documented, so the request carries both and they are
/// applied in a single write. Two separate one-line use cases would mean the same
/// rule in two places.
///
/// A checklist item the evidence is filed against has to belong to the same
/// property, otherwise one property's damage could end up used as proof about
/// another. Notes are trimmed here so the "is this damage documented?" checks
/// elsewhere never see whitespace that looks like a note but says nothing.
///
/// Passing `conditionItemID: nil` is allowed and puts the evidence back in the
/// library for the tenant to file later.
struct FileEvidenceUseCase {

    let inspectionRepository: InspectionRepository
    let evidenceRepository: EvidenceRepository

    init(inspectionRepository: InspectionRepository, evidenceRepository: EvidenceRepository) {
        self.inspectionRepository = inspectionRepository
        self.evidenceRepository = evidenceRepository
    }

    struct Request {
        var evidenceID: UUID
        /// Checklist item to file it against, or `nil` to return it to the library.
        var conditionItemID: UUID?
        var notes: String
    }

    /// - Returns: the evidence as it now stands.
    /// - Throws: `EvidenceFilingError` when a rule is broken.
    @discardableResult
    func execute(_ request: Request) throws -> EvidenceItem {

        guard var evidence = try evidenceRepository.fetchEvidence(id: request.evidenceID) else {
            throw EvidenceFilingError.evidenceNoLongerInLibrary
        }

        // Checked before writing anything.
        if let conditionItemID = request.conditionItemID {
            guard let item = try inspectionRepository.fetchConditionItem(id: conditionItemID),
                  let area = try inspectionRepository.fetchArea(id: item.inspectionAreaID) else {
                throw EvidenceFilingError.conditionItemNoLongerInWalkthrough
            }
            guard area.tenancyID == evidence.tenancyID else {
                throw EvidenceFilingError.conditionItemBelongsToAnotherProperty
            }
        }

        evidence.conditionItemID = request.conditionItemID
        evidence.notes = request.notes.trimmingCharacters(in: .whitespacesAndNewlines)

        try evidenceRepository.save(evidence)
        return evidence
    }
}
