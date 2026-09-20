import SwiftUI

/// Temporary root while the data layer lands. Replaced by the tenancy dashboard
/// on the inspection-workflow branch.
struct ContentView: View {

    let environment: AppEnvironment

    var body: some View {
        ContentUnavailableView(
            "Walkthrough coming next",
            systemImage: "house.badge.clock",
            description: Text("The evidence store is ready. The inspection screens land in the next feature branch.")
        )
    }
}
