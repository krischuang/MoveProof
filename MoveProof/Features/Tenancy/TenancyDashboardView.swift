import SwiftUI

/// Screen 1 — the tenant's overview of one property's documentation.
///
/// Answers, in order: how long have I got, how far have I got, and what still
/// needs my attention.
struct TenancyDashboardView: View {

    @Environment(MoveProofModel.self) private var model
    @State private var viewModel: TenancyDashboardViewModel
    @State private var isShowingSetup = false

    init(environment: AppEnvironment) {
        _viewModel = State(initialValue: TenancyDashboardViewModel(environment: environment))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Walkthrough")
                .toolbar {
                    if case .ready = viewModel.state {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Property details", systemImage: "house") {
                                isShowingSetup = true
                            }
                        }
                    }
                }
        }
        .sheet(isPresented: $isShowingSetup) {
            TenancySetupView(environment: model.environment)
        }
        .tenantMessageAlert($viewModel.message)
        .task { viewModel.load() }
        .onChange(of: model.revision) { viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Opening your evidence")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .noTenancy:
            firstRunState

        case .ready(let summary):
            summaryList(summary)
        }
    }

    // MARK: - First run

    private var firstRunState: some View {
        ContentUnavailableView {
            Label("No property yet", systemImage: "house.badge.plus")
        } description: {
            Text("Add the property you've moved into. MoveProof will set up a room-by-room walkthrough so your photos and notes stay tied to the place they came from.")
        } actions: {
            Button("Add your property") { isShowingSetup = true }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Ready

    private func summaryList(_ summary: ReviewInspectionProgressUseCase.Summary) -> some View {
        List {
            Section {
                propertyHeader(summary.tenancy)
            }

            Section("Condition report") {
                deadlineRow(summary.progress)
            }

            Section("Progress") {
                progressRow(summary.progress)
                LabeledContent("Rooms reviewed", value: "\(summary.progress.areasComplete) of \(summary.progress.areasTotal)")
                LabeledContent(
                    "Checklist items recorded",
                    value: "\(summary.progress.requiredItemsReviewed) of \(summary.progress.requiredItemsTotal)"
                )
                LabeledContent("Evidence filed", value: "\(summary.progress.evidenceCount)")
            }

            attentionSection(summary.progress)

            if summary.progress.pendingSharedEvidenceCount > 0 {
                Section("Shared with MoveProof") {
                    Button {
                        model.selectedSection = .inbox
                    } label: {
                        Label(
                            summary.progress.pendingSharedEvidenceCount == 1
                                ? "1 item is waiting to be filed"
                                : "\(summary.progress.pendingSharedEvidenceCount) items are waiting to be filed",
                            systemImage: "tray.full"
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { viewModel.load() }
    }

    private func propertyHeader(_ tenancy: Tenancy) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tenancy.propertyAddress)
                .font(.headline)
            Text("Moved in \(tenancy.moveInDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(tenancy.status.label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.tint.opacity(0.15), in: Capsule())
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func deadlineRow(_ progress: InspectionProgress) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(viewModel.deadlineHeadline(for: progress))
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: deadlineSymbol(progress.deadlineUrgency))
                    .foregroundStyle(deadlineColour(progress.deadlineUrgency))
            }
            Text(viewModel.deadlineDetail(for: progress))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func progressRow(_ progress: InspectionProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: progress.areaCompletionFraction) {
                Text(progress.isReportReady ? "Every room reviewed" : "Rooms reviewed")
                    .font(.subheadline)
            }
            .tint(progress.isReportReady ? .green : .accentColor)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(progress.areasComplete) of \(progress.areasTotal) rooms reviewed")
    }

    @ViewBuilder
    private func attentionSection(_ progress: InspectionProgress) -> some View {
        Section("Needs your attention") {
            if progress.areasNeedingAttention.isEmpty && progress.areasComplete == progress.areasTotal {
                Label("Nothing outstanding", systemImage: "checkmark.seal")
                    .foregroundStyle(.green)
            } else {
                Label {
                    Text(viewModel.attentionHeadline(for: progress))
                } icon: {
                    Image(systemName: progress.undocumentedDamageCount == 0 ? "checkmark.circle" : "exclamationmark.triangle.fill")
                        .foregroundStyle(progress.undocumentedDamageCount == 0 ? .green : .orange)
                }

                ForEach(progress.areasNeedingAttention) { area in
                    Button {
                        model.selectedSection = .rooms
                    } label: {
                        LabeledContent(area.name) {
                            Text("Open").font(.footnote)
                        }
                    }
                }

                if progress.areasComplete < progress.areasTotal {
                    Button {
                        model.selectedSection = .rooms
                    } label: {
                        Label(
                            "\(progress.areasTotal - progress.areasComplete) rooms still to review",
                            systemImage: "list.bullet.rectangle"
                        )
                    }
                }
            }
        }
    }

    private func deadlineSymbol(_ urgency: InspectionProgress.DeadlineUrgency) -> String {
        switch urgency {
        case .notSet: "calendar.badge.question"
        case .comfortable: "calendar"
        case .dueSoon: "clock.badge.exclamationmark"
        case .overdue: "calendar.badge.exclamationmark"
        }
    }

    private func deadlineColour(_ urgency: InspectionProgress.DeadlineUrgency) -> Color {
        switch urgency {
        case .notSet: .secondary
        case .comfortable: .accentColor
        case .dueSoon: .orange
        case .overdue: .red
        }
    }
}
