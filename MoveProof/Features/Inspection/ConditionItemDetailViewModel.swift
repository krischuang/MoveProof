import Foundation

/// Drives recording one checklist item: the condition found, the note, and the
/// photos that back it up.
@Observable
final class ConditionItemDetailViewModel {

    private(set) var conditionItem: ConditionItem
    let areaName: String

    var selectedState: ConditionState
    var notes: String
    private(set) var evidence: [EvidenceItem] = []

    var message: TenantMessage?
    /// Shown inline above the Save button when a rule blocks the record.
    var inlineMessage: TenantMessage?
    private(set) var didSave = false

    private let environment: AppEnvironment

    init(environment: AppEnvironment, conditionItem: ConditionItem, areaName: String) {
        self.environment = environment
        self.conditionItem = conditionItem
        self.areaName = areaName
        self.selectedState = conditionItem.conditionState == .notReviewed
            ? .undamaged
            : conditionItem.conditionState
        self.notes = conditionItem.notes
    }

    /// Whether the currently selected condition will require backing up.
    var requiresSupportingDetail: Bool {
        selectedState.requiresSupportingDetail
    }

    /// Whether what the tenant has entered right now satisfies the damage rule.
    /// Drives the prompt shown *before* they hit Save, so the rule reads as
    /// guidance rather than a rejection.
    var hasSupportingDetail: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !evidence.isEmpty
    }

    var supportingDetailPrompt: String? {
        guard requiresSupportingDetail, !hasSupportingDetail else { return nil }
        return "Add a photo or write a short note describing what you found, so you can identify this again at the end of the tenancy."
    }

    var notesPlaceholder: String {
        requiresSupportingDetail
            ? "Describe the damage — where it is and how bad it looks"
            : "Anything worth remembering about this item"
    }

    func load() {
        do {
            if let refreshed = try environment.inspectionRepository.fetchConditionItem(id: conditionItem.id) {
                conditionItem = refreshed
                if refreshed.conditionState != .notReviewed {
                    selectedState = refreshed.conditionState
                }
                notes = refreshed.notes
            }
            evidence = try environment.evidenceRepository.fetchEvidence(forConditionItem: conditionItem.id)
        } catch {
            message = TenantMessage(error, whileDoing: "loading this checklist item")
        }
    }

    /// Records the condition. Rule enforcement lives in the use case, so this
    /// method has no copy of the damage rule — it only routes the outcome.
    /// - Returns: `true` when the record was saved.
    @discardableResult
    func save() -> Bool {
        inlineMessage = nil
        let request = RecordConditionEvidenceUseCase.Request(
            conditionItemID: conditionItem.id,
            conditionState: selectedState,
            notes: notes
        )
        do {
            conditionItem = try environment.recordConditionEvidence.execute(request)
            didSave = true
            return true
        } catch {
            inlineMessage = TenantMessage(error, whileDoing: "recording this item")
            return false
        }
    }

    /// Files a photo the tenant picked against this item.
    func attachPhoto(data: Data, displayName: String) {
        let request = CaptureEvidenceUseCase.Request(
            imageData: data,
            displayName: displayName,
            conditionItemID: conditionItem.id
        )
        do {
            try environment.captureEvidence.execute(request)
            load()
            inlineMessage = nil
        } catch {
            message = TenantMessage(error, whileDoing: "adding that photo")
        }
    }

    func removeEvidence(_ item: EvidenceItem) {
        do {
            try environment.captureEvidence.removeEvidence(id: item.id)
            load()
        } catch {
            message = TenantMessage(error, whileDoing: "removing that photo")
        }
    }

    func imageURL(for item: EvidenceItem) -> URL? {
        try? environment.evidenceFileStore.url(forStoredFileName: item.storedFileName)
    }
}
