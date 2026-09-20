import QuickLook
import SwiftUI

/// Screen 7 — one piece of evidence: what it shows, where it came from, and which
/// checklist item it backs up.
struct EvidenceDetailView: View {

    @Environment(MoveProofModel.self) private var model
    @State private var viewModel: EvidenceDetailViewModel
    @State private var quickLookURL: URL?

    init(environment: AppEnvironment, evidence: EvidenceItem) {
        _viewModel = State(initialValue: EvidenceDetailViewModel(environment: environment, evidence: evidence))
    }

    var body: some View {
        Form {
            previewSection
            filingSection
            noteSection
            provenanceSection
        }
        .navigationTitle(viewModel.evidence.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($quickLookURL)
        .tenantMessageAlert($viewModel.message)
        .task { viewModel.load() }
    }

    private var previewSection: some View {
        Section {
            Button {
                quickLookURL = viewModel.fileURL
            } label: {
                HStack {
                    Spacer()
                    EvidenceThumbnail(url: viewModel.fileURL, kind: viewModel.evidence.kind, size: 180)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.fileURL == nil)

            if viewModel.fileIsMissing {
                Label(
                    "The file behind this record is no longer on this device. The details below are still recorded.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            } else {
                Text("Tap to view full size.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var filingSection: some View {
        Section {
            Picker("Filed against", selection: Binding(
                get: { viewModel.selectedConditionItemID },
                set: { viewModel.selectedConditionItemID = $0 }
            )) {
                Text("Not filed yet").tag(UUID?.none)
                ForEach(viewModel.filingOptions) { option in
                    Text(option.label).tag(UUID?.some(option.id))
                }
            }

            Button("Save filing") {
                if viewModel.saveFiling() {
                    model.dataChanged()
                }
            }
            .disabled(!viewModel.filingHasChanged)
        } header: {
            Text("Where this belongs")
        } footer: {
            Text("Attaching evidence to a checklist item is what lets MoveProof treat damage in that room as documented.")
        }
    }

    private var noteSection: some View {
        Section {
            TextField(
                "What does this show?",
                text: Binding(get: { viewModel.notes }, set: { viewModel.notes = $0 }),
                axis: .vertical
            )
            .lineLimit(2...6)

            Button("Save note") {
                if viewModel.saveNote() {
                    model.dataChanged()
                }
            }
            .disabled(!viewModel.noteHasChanged)
        } header: {
            Text("Your note")
        }
    }

    private var provenanceSection: some View {
        Section("Where this came from") {
            LabeledContent("Type", value: viewModel.evidence.kind.label)
            LabeledContent("Source", value: viewModel.evidence.source.label)
            LabeledContent(
                "Recorded",
                value: viewModel.evidence.capturedAt.formatted(date: .long, time: .shortened)
            )
        }
    }
}

/// Drives the evidence detail screen.
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
        var updated = evidence
        updated.conditionItemID = selectedConditionItemID
        do {
            try environment.evidenceRepository.save(updated)
            evidence = updated
            return true
        } catch {
            message = TenantMessage(error, whileDoing: "filing this evidence")
            return false
        }
    }

    @discardableResult
    func saveNote() -> Bool {
        var updated = evidence
        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try environment.evidenceRepository.save(updated)
            evidence = updated
            notes = updated.notes
            return true
        } catch {
            message = TenantMessage(error, whileDoing: "saving your note")
            return false
        }
    }
}
