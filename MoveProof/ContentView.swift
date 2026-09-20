import SwiftUI

/// Root navigation. Four sections, named for what the tenant is doing rather than
/// for the data behind them.
struct ContentView: View {

    @State private var model: MoveProofModel

    init(environment: AppEnvironment) {
        _model = State(initialValue: MoveProofModel(environment: environment))
    }

    var body: some View {
        @Bindable var model = model

        TabView(selection: $model.selectedSection) {
            Tab("Walkthrough", systemImage: "house", value: MoveProofModel.Section.overview) {
                TenancyDashboardView(environment: model.environment)
            }

            Tab("Rooms", systemImage: "square.grid.2x2", value: MoveProofModel.Section.rooms) {
                InspectionAreaListView(environment: model.environment)
            }

            Tab("Evidence", systemImage: "photo.on.rectangle.angled", value: MoveProofModel.Section.evidence) {
                EvidenceLibraryView(environment: model.environment)
            }

            Tab("Shared", systemImage: "tray", value: MoveProofModel.Section.inbox) {
                SharedEvidenceInboxView(environment: model.environment)
            }
        }
        .environment(model)
        // Coming back from the share sheet is the moment new items appear in the
        // inbox, so refresh every screen when the app returns to the foreground.
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
        ) { _ in
            model.dataChanged()
        }
    }
}
