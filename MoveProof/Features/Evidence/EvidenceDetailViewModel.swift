import Foundation

/// Drives the evidence detail screen: where one photo or document belongs, and what
/// it shows.
///
/// Both Save buttons go through `FileEvidenceUseCase`, which owns the checks and the
/// note trimming. This file only reads, to build the picker, and shows the result. It
/// performs no write of its own.
@Observable
final class EvidenceDetailViewModel {

    struct FilingOption: Identifiable, Equatable {
        let id: UUID
        let label: String
    }

    private(set) var evidence: EvidenceItem
    private(set) var filingOptions: [FilingOption] = []
    private(set) var fileURL: URL?
    private(set) var fileIsMissing = false

    var selectedConditionItemID: UUID?
    var notes: String
    var message: TenantMessage?

    private let environment: AppEnvironment

    init(environment: AppEnvironment, evidence: EvidenceItem) {
        self.environment = environment
        self.evidence = evidence
        self.selectedConditionItemID = evidence.conditionItemID
        self.notes = evidence.notes
    }

    var filingHasChanged: Bool { selectedConditionItemID != evidence.conditionItemID }
    var noteHasChanged: Bool { notes != evidence.notes }

    func load() {
        do {
            if let refreshed = try environment.evidenceRepository.fetchEvidence(id: evidence.id) {
                evidence = refreshed
                selectedConditionItemID = refreshed.conditionItemID
                notes = refreshed.notes
            }

            fileURL = try? environment.evidenceFileStore.url(forStoredFileName: evidence.storedFileName)
            fileIsMissing = !environment.evidenceFileStore.fileExists(named: evidence.storedFileName)

            let areas = try environment.inspectionRepository.fetchAreas(forTenancy: evidence.tenancyID)
            filingOptions = try areas.flatMap { area in
                try environment.inspectionRepository.fetchConditionItems(inArea: area.id).map {
                    FilingOption(id: $0.id, label: "\(area.name) · \($0.title)")
                }
            }
        } catch {
            message = TenantMessage(error, whileDoing: "loading this evidence")
        }
    }

    @discardableResult
    func saveFiling() -> Bool {
        applyCurrentFiling(whileDoing: "filing this evidence")
    }

    @discardableResult
    func saveNote() -> Bool {
        applyCurrentFiling(whileDoing: "saving your note")
    }

    /// Sends both fields, where the evidence belongs and what it shows, to the use
    /// case.
    ///
    /// These are one operation, so the request always carries both fields as they
    /// currently are on screen. The two buttons stay separate because each is enabled
    /// by its own change, but neither needs its own use case.
    private func applyCurrentFiling(whileDoing: String) -> Bool {
        let request = FileEvidenceUseCase.Request(
            evidenceID: evidence.id,
            conditionItemID: selectedConditionItemID,
            notes: notes
        )
        do {
            evidence = try environment.fileEvidence.execute(request)
            notes = evidence.notes
            selectedConditionItemID = evidence.conditionItemID
            return true
        } catch {
            message = TenantMessage(error, whileDoing: whileDoing)
            return false
        }
    }
}
