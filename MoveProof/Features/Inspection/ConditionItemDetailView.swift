import PhotosUI
import SwiftUI

/// Screen 5 — record what the tenant found for one checklist item, and attach the
/// photos that back it up.
struct ConditionItemDetailView: View {

    @Environment(MoveProofModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ConditionItemDetailViewModel
    @State private var photoSelection: PhotosPickerItem?
    @State private var isAddingPhoto = false

    init(environment: AppEnvironment, conditionItem: ConditionItem, areaName: String) {
        _viewModel = State(initialValue: ConditionItemDetailViewModel(
            environment: environment,
            conditionItem: conditionItem,
            areaName: areaName
        ))
    }

    var body: some View {
        Form {
            conditionSection
            notesSection
            evidenceSection
            saveSection
        }
        .navigationTitle(viewModel.conditionItem.title)
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(
            isPresented: $isAddingPhoto,
            selection: $photoSelection,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: photoSelection) { _, newValue in
            guard let newValue else { return }
            Task { await attach(newValue) }
        }
        .tenantMessageAlert($viewModel.message)
        .task { viewModel.load() }
    }

    // MARK: - Sections

    private var conditionSection: some View {
        Section {
            Picker("What did you find?", selection: Binding(
                get: { viewModel.selectedState },
                set: { viewModel.selectedState = $0 }
            )) {
                ForEach(ConditionState.selectableStates, id: \.self) { state in
                    Label(state.label, systemImage: state.symbolName).tag(state)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Condition in the \(viewModel.areaName.lowercased())")
        } footer: {
            if let prompt = viewModel.supportingDetailPrompt {
                Label(prompt, systemImage: "info.circle")
                    .foregroundStyle(.orange)
            } else if viewModel.requiresSupportingDetail {
                Label("This record has supporting detail.", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else {
                Text("Pick the condition that matches what you can see right now.")
            }
        }
    }

    private var notesSection: some View {
        Section("Your note") {
            TextField(
                viewModel.notesPlaceholder,
                text: Binding(get: { viewModel.notes }, set: { viewModel.notes = $0 }),
                axis: .vertical
            )
            .lineLimit(3...8)
            // Stable handle for the UI test; the placeholder text is domain copy and
            // should be free to change without breaking a test.
            .accessibilityIdentifier("conditionNotesField")
        }
    }

    private var evidenceSection: some View {
        Section {
            if viewModel.evidence.isEmpty {
                Text("No photos or documents filed against this item yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.evidence) { item in
                    HStack(spacing: 12) {
                        EvidenceThumbnail(url: viewModel.imageURL(for: item), kind: item.kind)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.displayName).lineLimit(1)
                            Text("\(item.source.label) · \(item.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) {
                            viewModel.removeEvidence(item)
                            model.dataChanged()
                        }
                    }
                }
            }

            Button {
                isAddingPhoto = true
            } label: {
                Label("Add a photo", systemImage: "camera")
            }
        } header: {
            Text("Supporting evidence")
        } footer: {
            Text("Photos are stored inside MoveProof. You can also share photos or PDFs to MoveProof from another app and file them here later.")
        }
    }

    private var saveSection: some View {
        Section {
            if let inlineMessage = viewModel.inlineMessage {
                TenantMessageBanner(message: inlineMessage)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Button {
                if viewModel.save() {
                    model.dataChanged()
                    dismiss()
                }
            } label: {
                Label("Record this item", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func attach(_ selection: PhotosPickerItem) async {
        defer { photoSelection = nil }
        do {
            guard let data = try await selection.loadTransferable(type: Data.self) else {
                viewModel.message = TenantMessage(
                    title: "Couldn't read that photo",
                    whatHappened: "MoveProof couldn't read the photo you picked.",
                    whatToDoNext: "Try picking it again, or take a fresh photo of what you want to record."
                )
                return
            }
            let name = "Photo \(Date().formatted(date: .abbreviated, time: .shortened))"
            viewModel.attachPhoto(data: data, displayName: name)
            model.dataChanged()
        } catch {
            viewModel.message = TenantMessage(error, whileDoing: "adding that photo")
        }
    }
}
