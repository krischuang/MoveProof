import SwiftUI

/// What the tenant sees in the share sheet.
///
/// Says plainly what will happen: the file goes into MoveProof's inbox, and filing it
/// against a room happens in the app. That stops the hand-off looking like a finished
/// action when it is really only the first half of one.
///
/// The view owns the outcome. `SharedItemCollector` is a value type that looks at the
/// attachments and returns a result, holding no state of its own.
struct ShareConfirmationView: View {

    let collector: SharedItemCollector
    let onFinish: () -> Void
    let onCancel: () -> Void

    @State private var outcome: SharedItemCollector.Outcome = .preparing
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Group {
                switch outcome {
                case .preparing:
                    ProgressView("Checking what you shared")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .ready(let candidates):
                    readyState(candidates)

                case .saved(let count):
                    resultState(
                        symbol: "checkmark.circle.fill",
                        tint: .green,
                        title: count == 1 ? "Saved to MoveProof" : "\(count) items saved to MoveProof",
                        detail: "Open MoveProof and go to Shared items to file this against a room."
                    )

                case .nothingUsable:
                    resultState(
                        symbol: "questionmark.circle",
                        tint: .orange,
                        title: "Nothing MoveProof can store",
                        detail: "MoveProof keeps photos and PDFs as evidence. Take a screenshot or export this as a PDF, then share that instead."
                    )

                case .failed(let reason):
                    resultState(
                        symbol: "exclamationmark.triangle.fill",
                        tint: .orange,
                        title: "Couldn't save that",
                        detail: reason
                    )
                }
            }
            .navigationTitle("Add to MoveProof")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .ready = outcome {
                        Button("Cancel", action: onCancel)
                    }
                }
            }
        }
        .task { outcome = collector.initialOutcome }
    }

    private func readyState(_ candidates: [SharedItemCollector.Candidate]) -> some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(candidates) { candidate in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.displayName).lineLimit(2)
                                Text(candidate.typeIdentifier)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: candidate.typeIdentifier == "com.adobe.pdf" ? "doc.text" : "photo")
                        }
                    }
                } header: {
                    Text(candidates.count == 1 ? "1 item" : "\(candidates.count) items")
                } footer: {
                    Text("MoveProof will hold this in its shared items inbox. You file it against a room and a checklist item inside the app.")
                }
            }

            Button {
                guard !isSaving else { return }
                isSaving = true
                Task {
                    outcome = await collector.save()
                    onFinish()
                }
            } label: {
                Text("Save to MoveProof")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSaving)
            .padding()
        }
    }

    private func resultState(symbol: String, tint: Color, title: String, detail: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done", action: onCancel)
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
