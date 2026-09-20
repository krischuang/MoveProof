import SwiftUI

/// Screen 8 — files handed over by the Share Extension, waiting to be filed as
/// evidence or discarded.
struct SharedEvidenceInboxView: View {

    @Environment(MoveProofModel.self) private var model
    @State private var viewModel: SharedEvidenceInboxViewModel

    init(environment: AppEnvironment) {
        _viewModel = State(initialValue: SharedEvidenceInboxViewModel(environment: environment))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Shared items")
        }
        .tenantMessageAlert($viewModel.message)
        .alert(
            "Filed",
            isPresented: Binding(
                get: { viewModel.confirmation != nil },
                set: { if !$0 { viewModel.confirmation = nil } }
            ),
            presenting: viewModel.confirmation
        ) { _ in
            Button("OK", role: .cancel) { viewModel.confirmation = nil }
        } message: { text in
            Text(text)
        }
        .task { viewModel.load() }
        .onChange(of: model.revision) { viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.rows.isEmpty {
            ContentUnavailableView(
                "Nothing waiting",
                systemImage: "tray",
                description: Text(viewModel.emptyStateDescription)
            )
        } else {
            List {
                Section {
                    ForEach(viewModel.rows) { row in
                        inboxRow(row)
                    }
                } footer: {
                    Text("MoveProof checks the file type and makes sure the same item can't be filed twice before adding it to your evidence.")
                }
            }
            .refreshable { viewModel.load() }
        }
    }

    private func inboxRow(_ row: SharedEvidenceInboxViewModel.InboxRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.item.originalFileName)
                    .font(.body)
                    .lineLimit(2)
                Text(row.sourceLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(row.sizeLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if viewModel.hasTenancy && !viewModel.filingOptions.isEmpty {
                Picker("File against", selection: Binding(
                    get: { viewModel.selectedFilings[row.id] },
                    set: { viewModel.selectedFilings[row.id] = $0 }
                )) {
                    Text("Decide later").tag(UUID?.none)
                    ForEach(viewModel.filingOptions) { option in
                        Text(option.label).tag(UUID?.some(option.id))
                    }
                }
                .font(.footnote)
            }

            HStack(spacing: 12) {
                Button {
                    if viewModel.importItem(row) {
                        model.dataChanged()
                    }
                } label: {
                    Label("Add to evidence", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(role: .destructive) {
                    viewModel.discard(row)
                    model.dataChanged()
                } label: {
                    Label("Discard", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }
}
