import Foundation

/// Drives the dashboard.
///
/// It talks to `ReviewInspectionProgressUseCase` and nothing else — there is no
/// fetch request, no managed object context and no Core Data import in this file
/// or anywhere else in the view layer.
@Observable
final class TenancyDashboardViewModel {

    enum State: Equatable {
        case loading
        /// No property set up yet — the first-run state, not an error.
        case noTenancy
        case ready(ReviewInspectionProgressUseCase.Summary)
    }

    private(set) var state: State = .loading
    var message: TenantMessage?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// Reloads the summary and republishes the widget snapshot as a side effect of
    /// the use case, so the Home Screen tracks the app every time the tenant looks
    /// at the dashboard.
    func load() {
        do {
            let summary = try environment.reviewInspectionProgress.execute()
            state = .ready(summary)
        } catch is InspectionReviewError {
            // Not having started yet is a normal first-run state, so it gets an
            // empty state rather than an error alert.
            environment.reviewInspectionProgress.publishEmptySnapshot()
            state = .noTenancy
        } catch {
            message = TenantMessage(error, whileDoing: "loading your walkthrough")
            state = .noTenancy
        }
    }

    // MARK: - Presentation helpers
    //
    // Kept in the view model so the view stays declarative and the wording can be
    // asserted without rendering anything.

    func deadlineHeadline(for progress: InspectionProgress) -> String {
        guard let days = progress.daysUntilConditionReportDue else {
            return "No due date set"
        }
        switch days {
        case ..<0:
            let overdue = -days
            return overdue == 1 ? "Due date passed yesterday" : "Due date passed \(overdue) days ago"
        case 0:
            return "Condition report due today"
        case 1:
            return "Condition report due tomorrow"
        default:
            return "\(days) days until the condition report is due"
        }
    }

    func deadlineDetail(for progress: InspectionProgress) -> String {
        switch progress.deadlineUrgency {
        case .notSet:
            "Add a due date so MoveProof can remind you how long you have."
        case .comfortable:
            "There's still time to finish the rooms you haven't reviewed."
        case .dueSoon:
            "Finish the remaining rooms so you can return the report on time."
        case .overdue:
            "You can still record what you found — dated evidence is worth keeping either way."
        }
    }

    func attentionHeadline(for progress: InspectionProgress) -> String {
        switch progress.undocumentedDamageCount {
        case 0: "Everything you've recorded has backing"
        case 1: "1 damaged item has no photo or note"
        default: "\(progress.undocumentedDamageCount) damaged items have no photo or note"
        }
    }
}
