import SwiftUI
import WidgetKit

/// The MoveProof Home Screen widget.
///
/// ## What it deliberately does not show
///
/// A Home Screen widget is visible to anyone who can see the device — over a
/// shoulder on a train, or to a flatmate who picks the phone up. The useful-looking
/// content here would be the property address, the damage descriptions and the
/// photographs, and all three are exactly the things a tenant would not want on a
/// lock screen. So the widget carries only counts, progress and the reporting
/// deadline: enough to answer "am I on track and how long have I got", and not
/// enough to tell a stranger where the tenant lives or what is wrong with the place.
struct InspectionProgressWidget: Widget {

    /// Must match `WidgetSnapshotPublisher.widgetKind` in the main app, which is
    /// what `WidgetCenter.reloadTimelines(ofKind:)` targets after a data change.
    static let kind = "MoveProofInspectionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: InspectionProgressProvider()) { entry in
            InspectionProgressEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Walkthrough progress")
        .description("How many rooms you've reviewed and how long you have until the condition report is due. Your address and photos stay in the app.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// Picks the layout for the family the system asked for.
struct InspectionProgressEntryView: View {

    @Environment(\.widgetFamily) private var family
    let entry: InspectionProgressEntry

    var body: some View {
        if entry.snapshot.hasActiveTenancy {
            switch family {
            case .systemMedium:
                MediumInspectionView(snapshot: entry.snapshot)
            default:
                SmallInspectionView(snapshot: entry.snapshot)
            }
        } else {
            NoTenancyView()
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    InspectionProgressWidget()
} timeline: {
    InspectionProgressEntry(date: .now, snapshot: .sample)
    InspectionProgressEntry(date: .now, snapshot: .noActiveTenancy)
}

#Preview("Medium", as: .systemMedium) {
    InspectionProgressWidget()
} timeline: {
    InspectionProgressEntry(date: .now, snapshot: .sample)
    InspectionProgressEntry(date: .now, snapshot: .noActiveTenancy)
}
