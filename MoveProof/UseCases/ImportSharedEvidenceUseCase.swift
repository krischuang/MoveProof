import Foundation

/// Brings a file shared from another app into MoveProof's own evidence store. The
/// Share Extension is not trusted with any of these rules.
///
/// ## Rules enforced
/// 1. There must be a tenancy to file the evidence against.
/// 2. The content type must be something the app can use as evidence, so a photo or
///    a PDF. A shared video or web link is refused with an explanation.
/// 3. The shared file must still be there. Items can sit in the inbox for days and
///    the original may have been deleted in the meantime.
/// 4. **Importing is idempotent.** An inbox item that has already been imported is
///    refused instead of filed twice, so tapping Import again cannot create a
///    duplicate.
///
/// The Share Extension runs under tight memory limits, so it should not be repeating
/// any of this. It captures the file and where it came from, and every decision is
/// made here in the main app.
struct ImportSharedEvidenceUseCase {

    let tenancyRepository: TenancyRepository
    let evidenceRepository: EvidenceRepository
    let evidenceFileStore: EvidenceFileStore
    let inbox: SharedEvidenceInbox

    init(
        tenancyRepository: TenancyRepository,
        evidenceRepository: EvidenceRepository,
        evidenceFileStore: EvidenceFileStore,
        inbox: SharedEvidenceInbox = SharedEvidenceInbox()
    ) {
        self.tenancyRepository = tenancyRepository
        self.evidenceRepository = evidenceRepository
        self.evidenceFileStore = evidenceFileStore
        self.inbox = inbox
    }

    struct Request {
        var item: PendingSharedEvidence
        /// Checklist item to file it against, when the tenant has picked one.
        /// Evidence may also be imported unassigned and filed later.
        var conditionItemID: UUID?
        var notes: String = ""
    }

    /// - Returns: the evidence that was filed.
    /// - Throws: `SharedEvidenceImportError` when a rule is broken.
    @discardableResult
    func execute(_ request: Request, now: Date = Date()) throws -> EvidenceItem {

        let item = request.item

        // Rule 1
        guard let tenancy = try tenancyRepository.fetchActiveTenancy() else {
            throw SharedEvidenceImportError.noActiveTenancy
        }

        // Rule 2: the extension just records the UTI it was given. Working out
        // what kind of evidence that is happens here.
        guard let kind = EvidenceKind.forContentType(item.contentTypeIdentifier) else {
            throw SharedEvidenceImportError.unsupportedSharedContent(
                contentTypeIdentifier: item.contentTypeIdentifier
            )
        }

        // Rule 4: check first, so a second tap is cheap and safe.
        if try evidenceRepository.fetchEvidence(importedFromInboxItem: item.id) != nil {
            throw SharedEvidenceImportError.duplicateEvidence(displayName: item.originalFileName)
        }

        // Rule 3
        guard let sourceURL = try? inbox.fileURL(for: item),
              FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw SharedEvidenceImportError.sharedItemUnavailable(displayName: item.originalFileName)
        }

        // Copy the file before writing the database row, so a failed copy cannot
        // leave the store pointing at a file that was never written.
        let storedFileName: String
        do {
            storedFileName = try evidenceFileStore.adopt(
                fileAt: sourceURL,
                preferredExtension: sourceURL.pathExtension
            )
        } catch {
            AppLog.sharedInbox.error("Could not adopt shared file for inbox item \(item.id): \(error)")
            throw SharedEvidenceImportError.sharedItemUnavailable(displayName: item.originalFileName)
        }

        let evidence = EvidenceItem(
            kind: kind,
            storedFileName: storedFileName,
            displayName: item.originalFileName,
            capturedAt: item.receivedAt,
            notes: request.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            source: .sharedFromAnotherApp,
            conditionItemID: request.conditionItemID,
            tenancyID: tenancy.id,
            importedInboxItemID: item.id
        )

        do {
            try evidenceRepository.save(evidence)
        } catch {
            // Delete the copy so a failed save does not leave it orphaned.
            try? evidenceFileStore.removeFile(named: storedFileName)
            throw error
        }

        // Only now is it safe to clear the inbox. The evidence is saved, so the
        // hand-off is finished rather than just attempted.
        do {
            try inbox.remove(item)
        } catch {
            // A file left in the inbox is harmless. Rule 4 stops it importing twice.
            AppLog.sharedInbox.error("Imported inbox item \(item.id) but could not clear the inbox: \(error)")
        }

        return evidence
    }

    /// Removes an inbox item the tenant does not want, without filing it.
    func discard(_ item: PendingSharedEvidence) throws {
        try inbox.remove(item)
    }

    /// Everything waiting to be imported, oldest first.
    func pendingItems() throws -> [PendingSharedEvidence] {
        do {
            return try inbox.pendingItems()
        } catch {
            AppLog.sharedInbox.error("Could not read the shared evidence inbox: \(error)")
            throw SharedEvidenceImportError.inboxUnavailable
        }
    }
}
