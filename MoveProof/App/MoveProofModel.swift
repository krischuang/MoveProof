import SwiftUI

/// App-wide state shared by every screen: the object graph, plus a revision counter
/// one screen uses to tell the others their data has changed.
///
/// Kept small on purpose. It holds no domain data of its own, and screens still load
/// what they need through their own view models and use cases. Its job is to hand
/// out the environment and to say "something changed, reload".
@Observable
final class MoveProofModel {

    let environment: AppEnvironment

    /// Incremented whenever a use case writes something. Screens watch this and
    /// reload, so signing off a room updates the dashboard without either screen
    /// knowing about the other.
    private(set) var revision = 0

    /// Which tab is showing, so the dashboard can send the tenant somewhere useful.
    var selectedSection: Section = .overview

    enum Section: Hashable {
        case overview, rooms, evidence, inbox
    }

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// Call this after a save succeeds, not before.
    ///
    /// Screens reload off `revision`, and the widget snapshot is rewritten here so
    /// every change reaches the Home Screen the same way instead of each use case
    /// having to remember `WidgetCenter` itself.
    func dataChanged() {
        revision += 1
        environment.reviewInspectionProgress.refreshPublishedSnapshot()    }
}
