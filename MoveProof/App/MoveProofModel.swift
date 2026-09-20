import SwiftUI

/// App-wide state shared by every screen: the object graph, and a revision counter
/// that lets one screen tell the others their data has moved on.
///
/// Deliberately small. It holds no domain data of its own — screens still load what
/// they need through their own view models and use cases. Its only job is to hand
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

    /// Call after any successful write.
    func dataChanged() {
        revision += 1
    }
}
