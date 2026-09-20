import SwiftUI

@main
struct MoveProofApp: App {

    /// Built once, at launch. The Core Data stack lives inside this graph and
    /// nothing in the view layer can reach past it to a managed object context.
    private let environment: AppEnvironment

    init() {
        let store = InspectionStore.shared
        InspectionStore.resetIfRequestedByUITest(store: store)
        environment = AppEnvironment.live(store: store)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(environment: environment)
        }
    }
}
