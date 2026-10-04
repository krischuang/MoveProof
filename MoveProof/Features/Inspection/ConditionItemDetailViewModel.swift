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

    /// Whether what is entered right now meets the damage rule. Drives the prompt
    /// shown *before* they hit Save, so the rule reads as a hint, not a rejection.
    var hasSupportingDetail: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !evidence.isEmpty
    }

    var supportingDetailPrompt: String? {
        guard requiresSupportingDetail, !hasSupportingDetail else { return nil }
        return "Add a photo or write a short note describing what you found, so you can identify this again at the end of the tenancy."
    }

    var notesPlaceholder: String {
        requiresSupportingDetail
            ? "Describe the damage: where it is and how bad it looks"
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

    /// Records the condition. The rules live in the use case, so there is no copy of
    /// the damage rule here. This only shows the result.
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
    /// - Returns: `true` when the photo was filed.
    @discardableResult
    func attachPhoto(data: Data, displayName: String) -> Bool {
        let request = CaptureEvidenceUseCase.Request(
            imageData: data,
            displayName: displayName,
            conditionItemID: conditionItem.id
        )
        do {
            try environment.captureEvidence.execute(request)
            load()
            inlineMessage = nil
            return true
        } catch {
            message = TenantMessage(error, whileDoing: "adding that photo")
            return false
        }
    }

    /// - Returns: `true` when the photo was discarded.
    @discardableResult
    func removeEvidence(_ item: EvidenceItem) -> Bool {
        do {
            try environment.discardEvidence.execute(evidenceID: item.id)
            load()
            // The screen already shows the "needs backing up" prompt from
            // `supportingDetailPrompt`, so losing the last photo is visible here
            // without a second message on top.
            return true
        } catch {
            message = TenantMessage(error, whileDoing: "removing that photo")
            return false
        }
    }

    func imageURL(for item: EvidenceItem) -> URL? {
        try? environment.evidenceFileStore.url(forStoredFileName: item.storedFileName)
    }
}
