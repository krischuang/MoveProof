import SwiftUI

/// Screen 4: one room's condition checklist, and the sign-off that closes it.
struct InspectionAreaDetailView: View {

    @Environment(MoveProofModel.self) private var model
    @State private var viewModel: InspectionAreaDetailViewModel
    @State private var isRenaming = false
    @State private var draftName = ""

    init(environment: AppEnvironment, area: InspectionArea) {
        _viewModel = State(initialValue: InspectionAreaDetailViewModel(environment: environment, area: area))
    }

    var body: some View {
        List {
            summarySection

            ForEach(viewModel.groupedRows, id: \.category) { group in
                Section(group.category.label) {
                    ForEach(group.rows) { row in
                        NavigationLink {
                            ConditionItemDetailView(
                                environment: model.environment,
                                conditionItem: row.item,
                                areaName: viewModel.area.name
                            )
                        } label: {
                            itemRow(row)
                        }
                    }
                }
            }

            signOffSection
        }
        .navigationTitle(viewModel.area.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Rename room", systemImage: "pencil") {
                    draftName = viewModel.area.name
                    isRenaming = true
                }
            }
        }
        .alert("Rename room", isPresented: $isRenaming) {
            TextField("Room name", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if viewModel.rename(to: draftName) {
                    model.dataChanged()
                }
            }
        }
        .tenantMessageAlert($viewModel.message)
        .task { viewModel.load() }
        .onChange(of: model.revision) { viewModel.load() }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(viewModel.area.inspectionStatus.label, systemImage: viewModel.area.inspectionStatus.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(viewModel.isComplete ? .green : .primary)

                Text("\(viewModel.reviewedCount) of \(viewModel.requiredCount) checklist items recorded")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if viewModel.undocumentedDamageCount > 0 {
                    Label(
                        viewModel.undocumentedDamageCount == 1
                            ? "1 damaged item still needs a photo or note"
                            : "\(viewModel.undocumentedDamageCount) damaged items still need a photo or note",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }
    }

    private var signOffSection: some View {
        Section {
            if let blocked = viewModel.signOffBlockedMessage {
                TenantMessageBanner(message: blocked)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if viewModel.isComplete {
                Button {
                    if viewModel.reopen() {
                        model.dataChanged()
                    }
                } label: {
                    Label("Reopen this room", systemImage: "arrow.uturn.backward")
                }
            } else {
                Button {
                    if viewModel.signOff() {
                        model.dataChanged()
                    }
                } label: {
                    Label("Mark this room reviewed", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canAttemptSignOff)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        } footer: {
            Text(viewModel.isComplete
                 ? "Reopen the room if you need to change something you recorded."
                 : "MoveProof checks that every item has been recorded, and that anything damaged has a photo or a note, before signing the room off.")
        }
    }

    private func itemRow(_ row: InspectionAreaDetailViewModel.ItemRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.item.conditionState.symbolName)
                .foregroundStyle(stateColour(row.item.conditionState))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.item.title)
                Text(row.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if row.item.conditionState.requiresSupportingDetail && !row.isFullyDocumented {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Needs a photo or note")
            }
        }
        .padding(.vertical, 2)
    }

    private func stateColour(_ state: ConditionState) -> Color {
        switch state {
        case .notReviewed: .secondary
        case .undamaged: .green
        case .minorWear: .yellow
        case .damaged: .orange
        case .notWorking: .red
        }
    }
}
