import Foundation

/// Saves a photo the tenant picked inside MoveProof into the app's own storage.
///
/// ## Rules enforced
/// 1. There must be a tenancy to file the photo against. A photo with no property
///    attached is no use in a bond dispute later.
/// 2. The image must contain some bytes. An empty pick is refused, because a
///    zero-byte file looks like evidence in the library but opens to nothing.
/// 3. If the photo is being filed against a checklist item, that item must still
///    exist and must belong to the current tenancy. Photos cannot be attached
///    across properties.
/// 4. The file is written first, then the database row. If the row fails to save,
///    the file is deleted again so the library never lists a photo it cannot open.
///
/// Kept separate from `ImportSharedEvidenceUseCase` because the two fail in
/// different ways. That one adopts a file another app left in the App Group inbox;
/// this one takes bytes the tenant chose inside MoveProof.
///
/// All failures come out as `EvidenceCaptureError`. Storage problems are the app's
/// fault, not the tenant's, so they are caught here and logged, and no
/// `RepositoryError` or `CocoaError` reaches the screen.
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

    /// - Returns: the evidence that was saved.
    /// - Throws: `EvidenceCaptureError` for any failure, rule or otherwise.
    @discardableResult
    func execute(_ request: Request, now: Date = Date()) throws -> EvidenceItem {

        // Rule 1
        guard let tenancy = try activeTenancy() else {
            throw EvidenceCaptureError.noActiveTenancy
        }

        // Rule 2
        guard !request.imageData.isEmpty else {
            throw EvidenceCaptureError.emptyPhoto(displayName: request.displayName)
        }

        // Rule 3: check the link before writing any bytes, so a bad pick costs
        // nothing on disk.
        if let conditionItemID = request.conditionItemID {
            try checkConditionItem(conditionItemID, belongsTo: tenancy)
        }

        // Rule 4
        let storedFileName: String
        do {
            storedFileName = try evidenceFileStore.store(
                data: request.imageData,
                preferredExtension: request.fileExtension
            )
        } catch {
            AppLog.evidence.error("Could not store captured photo: \(error)")
            throw EvidenceCaptureError.couldNotStorePhoto(displayName: request.displayName)
        }

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
            // Delete the file again so a failed save does not leave it orphaned.
            try? evidenceFileStore.removeFile(named: storedFileName)
            AppLog.evidence.error("Could not record captured photo, rolled the file back: \(error)")
            throw EvidenceCaptureError.couldNotStorePhoto(displayName: request.displayName)
        }

        return evidence
    }

    // MARK: - Rule helpers

    private func activeTenancy() throws -> Tenancy? {
        do {
            return try tenancyRepository.fetchActiveTenancy()
        } catch {
            AppLog.evidence.error("Could not read the active tenancy while capturing evidence: \(error)")
            throw EvidenceCaptureError.noActiveTenancy
        }
    }

    /// Rule 3: the checklist item has to exist and belong to the current tenancy.
    private func checkConditionItem(_ conditionItemID: UUID, belongsTo tenancy: Tenancy) throws {
        let item: ConditionItem?
        let area: InspectionArea?
        do {
            item = try inspectionRepository.fetchConditionItem(id: conditionItemID)
            area = try item.flatMap { try inspectionRepository.fetchArea(id: $0.inspectionAreaID) }
        } catch {
            AppLog.evidence.error("Could not check the checklist item while capturing evidence: \(error)")
            throw EvidenceCaptureError.conditionItemNoLongerInWalkthrough
        }

        guard item != nil, let area else {
            throw EvidenceCaptureError.conditionItemNoLongerInWalkthrough
        }
        guard area.tenancyID == tenancy.id else {
            throw EvidenceCaptureError.evidenceBelongsToAnotherProperty
        }
    }
}
