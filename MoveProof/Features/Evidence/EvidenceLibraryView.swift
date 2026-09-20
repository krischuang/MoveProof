import SwiftUI

/// Screen 6 — every piece of evidence filed against this property.
struct EvidenceLibraryView: View {

    @Environment(MoveProofModel.self) private var model
    @State private var viewModel: EvidenceLibraryViewModel

    init(environment: AppEnvironment) {
        _viewModel = State(initialValue: EvidenceLibraryViewModel(environment: environment))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Evidence")
                .navigationDestination(for: EvidenceItem.self) { item in
                    EvidenceDetailView(environment: model.environment, evidence: item)
                }
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
                description: Text("Add the property you've moved into on the Walkthrough tab before filing evidence.")
            )
        } else {
            VStack(spacing: 0) {
                Picker("Show", selection: Binding(
                    get: { viewModel.filter },
                    set: { viewModel.filter = $0 }
                )) {
                    ForEach(EvidenceLibraryViewModel.Filter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                if viewModel.rows.isEmpty {
                    ContentUnavailableView(
                        "Nothing here yet",
                        systemImage: "tray",
                        description: Text(viewModel.emptyStateMessage)
                    )
                } else {
                    List {
                        Section {
                            ForEach(viewModel.rows) { row in
                                NavigationLink(value: row.evidence) {
                                    evidenceRow(row)
                                }
                                .swipeActions {
                                    Button("Remove", role: .destructive) {
                                        viewModel.remove(row)
                                        model.dataChanged()
                                    }
                                }
                            }
                        } footer: {
                            if viewModel.unfiledCount > 0 {
                                Text(viewModel.unfiledCount == 1
                                     ? "1 item isn't attached to a room yet. Open it to file it against a checklist item."
                                     : "\(viewModel.unfiledCount) items aren't attached to a room yet. Open one to file it against a checklist item.")
                            }
                        }
                    }
                }
            }
        }
    }

    private func evidenceRow(_ row: EvidenceLibraryViewModel.EvidenceRow) -> some View {
        HStack(spacing: 12) {
            EvidenceThumbnail(url: viewModel.url(for: row), kind: row.evidence.kind)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.evidence.displayName)
                    .lineLimit(1)

                if let placement = row.placement {
                    Label(placement, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Label("Not filed against a room yet", systemImage: "questionmark.folder")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text(row.evidence.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
