import Foundation

/// Files a photo the tenant picked inside MoveProof into app-controlled storage.
///
/// ## Rules enforced
/// 1. There must be a tenancy to file the photo against.
/// 2. The data must be non-empty — an empty pick is refused rather than stored as
///    a zero-byte file the tenant would later find useless.
/// 3. If the tenant is filing it against a checklist item, that item must belong to
///    the tenancy being documented. Evidence cannot be attached across properties.
///
/// This exists separately from `ImportSharedEvidenceUseCase` because the two have
/// genuinely different provenance and different failure modes: one adopts a file
/// handed over by another app through the inbox, this one takes bytes the tenant
/// chose in MoveProof itself.
struct CaptureEvidenceUseCase {

    let tenancyRepository: TenancyRepository
    let inspectionRepository: InspectionRepository
    let evidenceRepository: EvidenceRepository
    let evidenceFileStore: EvidenceFileStore

    init(
        tenancyRepository: TenancyRepository,
        inspectionRepository: InspectionRepository,
        evidenceRepository: EvidenceRepository,
        evidenceFileStore: EvidenceFileStore
    ) {
        self.tenancyRepository = tenancyRepository
        self.inspectionRepository = inspectionRepository
        self.evidenceRepository = evidenceRepository
        self.evidenceFileStore = evidenceFileStore
    }

    struct Request {
        var imageData: Data
        var displayName: String
        var fileExtension: String = "jpg"
        var notes: String = ""
        /// Checklist item to file it against, or `nil` to leave it in the library.
        var conditionItemID: UUID?
    }

    /// - Returns: the evidence that was filed.
    /// - Throws: `SharedEvidenceImportError.noActiveTenancy` when nothing is being
    ///   documented, or `ConditionRecordingError` when the checklist link is invalid.
    @discardableResult
    func execute(_ request: Request, now: Date = Date()) throws -> EvidenceItem {

        // Rule 1
        guard let tenancy = try tenancyRepository.fetchActiveTenancy() else {
            throw SharedEvidenceImportError.noActiveTenancy
        }

        // Rule 2
        guard !request.imageData.isEmpty else {
            throw SharedEvidenceImportError.sharedItemUnavailable(displayName: request.displayName)
        }

        // Rule 3: validate the link before writing any bytes.
        if let conditionItemID = request.conditionItemID {
            guard let item = try inspectionRepository.fetchConditionItem(id: conditionItemID) else {
                throw ConditionRecordingError.conditionItemNotFound
            }
            guard let area = try inspectionRepository.fetchArea(id: item.inspectionAreaID) else {
                throw ConditionRecordingError.inspectionAreaNotFound
            }
            guard area.tenancyID == tenancy.id else {
                throw ConditionRecordingError.evidenceBelongsToAnotherTenancy
            }
        }

        let storedFileName = try evidenceFileStore.store(
            data: request.imageData,
            preferredExtension: request.fileExtension
        )

        let evidence = EvidenceItem(
            kind: .photograph,
            storedFileName: storedFileName,
            displayName: request.displayName,
            capturedAt: now,
            notes: request.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            source: .capturedInApp,
            conditionItemID: request.conditionItemID,
            tenancyID: tenancy.id
        )

        do {
            try evidenceRepository.save(evidence)
        } catch {
            try? evidenceFileStore.removeFile(named: storedFileName)
            throw error
        }

        return evidence
    }

    /// Removes a piece of evidence and the file behind it.
    ///
    /// The metadata row goes first: an orphaned file is invisible to the tenant,
    /// whereas an orphaned row would show as evidence that cannot be opened.
    func removeEvidence(id: UUID) throws {
        guard let evidence = try evidenceRepository.fetchEvidence(id: id) else { return }
        try evidenceRepository.delete(evidenceID: id)
        try? evidenceFileStore.removeFile(named: evidence.storedFileName)
    }
}
