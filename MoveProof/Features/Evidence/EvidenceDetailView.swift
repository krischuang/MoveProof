import QuickLook
import SwiftUI

/// Screen 7: one piece of evidence: what it shows, where it came from, and which
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
