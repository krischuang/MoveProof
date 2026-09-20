import SwiftUI

/// Screen 3 — the rooms in this property and how far each one has got.
struct InspectionAreaListView: View {

    @Environment(MoveProofModel.self) private var model
    @State private var viewModel: InspectionAreaListViewModel
    @State private var isAddingArea = false
    @State private var newAreaName = ""

    init(environment: AppEnvironment) {
        _viewModel = State(initialValue: InspectionAreaListViewModel(environment: environment))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Rooms")
                .toolbar {
                    if viewModel.tenancy != nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Add room", systemImage: "plus") { isAddingArea = true }
                        }
                    }
                }
                .navigationDestination(for: InspectionArea.self) { area in
                    InspectionAreaDetailView(environment: model.environment, area: area)
                }
        }
        .alert("Add a room", isPresented: $isAddingArea) {
            TextField("Room name", text: $newAreaName)
            Button("Cancel", role: .cancel) { newAreaName = "" }
            Button("Add") {
                if viewModel.addArea(named: newAreaName) {
                    model.dataChanged()
                }
                newAreaName = ""
            }
        } message: {
            Text("MoveProof will add the standard condition checklist to this room.")
        }
        .tenantMessageAlert($viewModel.message)
        .task { viewModel.load() }
        .onChange(of: model.revision) { viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.tenancy == nil {
            ContentUnavailableView(
                "No property yet",
                systemImage: "house.badge.plus",
                description: Text("Add the property you've moved into on the Walkthrough tab, and your rooms will appear here.")
            )
        } else if viewModel.summaries.isEmpty {
            ContentUnavailableView(
                "No rooms yet",
                systemImage: "square.grid.2x2",
                description: Text("Add the rooms you want to document with the button above.")
            )
        } else {
            List {
                Section {
                    ForEach(viewModel.summaries) { summary in
                        NavigationLink(value: summary.area) {
                            areaRow(summary)
                        }
                    }
                    .onDelete { viewModel.deleteAreas(at: $0); model.dataChanged() }
                } footer: {
                    Text("\(viewModel.completeCount) of \(viewModel.summaries.count) rooms reviewed. Removing a room keeps any photos you filed — they move back to your evidence library.")
                }
            }
        }
    }

    private func areaRow(_ summary: InspectionAreaListViewModel.AreaSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: summary.area.inspectionStatus.symbolName)
                .font(.title3)
                .foregroundStyle(summary.area.inspectionStatus == .complete ? .green : .secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.area.name)
                    .font(.body)

                Text(summary.detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if summary.undocumentedDamageCount > 0 {
                    Label(
                        summary.undocumentedDamageCount == 1
                            ? "1 damaged item needs a photo or note"
                            : "\(summary.undocumentedDamageCount) damaged items need a photo or note",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                if summary.area.inspectionStatus != .complete && summary.requiredCount > 0 {
                    ProgressView(value: summary.progressFraction)
                        .tint(.accentColor)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.area.name). \(summary.detailLine). \(summary.area.inspectionStatus.label).")
    }
}
