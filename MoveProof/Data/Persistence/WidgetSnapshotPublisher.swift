import Foundation
import OSLog
import WidgetKit

/// Publishes the privacy-reduced inspection summary to the App Group and asks
/// WidgetKit to refresh.
///
/// Behind a protocol so use case tests can assert that a rule *caused* a widget
/// refresh without a widget extension being installed.
protocol InspectionSnapshotPublishing {

    /// Writes the snapshot to shared storage and reloads the widget timelines.
    func publish(_ snapshot: InspectionSnapshot)
}

/// Live implementation: writes `Widget/snapshot.json` into the App Group, then
/// calls `WidgetCenter` so the Home Screen catches up with the app.
struct WidgetSnapshotPublisher: InspectionSnapshotPublishing {

    /// Must match the widget's `kind` string.
    static let widgetKind = "MoveProofInspectionWidget"

    private let store = InspectionSnapshotStore()

    init() {}

    func publish(_ snapshot: InspectionSnapshot) {
        do {
            try store.write(snapshot)
        } catch {
            // A failed snapshot write must never interrupt the tenant's walkthrough.
            // The widget simply keeps showing the previous summary until the next write.
            AppLog.persistence.error("Could not publish widget snapshot: \(error)")
            return
        }
        WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
    }
}
