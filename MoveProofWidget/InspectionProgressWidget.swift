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

// MARK: - Small

/// systemSmall: the two numbers a tenant checks most — how far through, how long left.
struct SmallInspectionView: View {

    let snapshot: InspectionSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("MoveProof", systemImage: "house.badge.clock")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

            Spacer(minLength: 0)

            Text("\(snapshot.areasComplete)/\(snapshot.areasTotal)")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text("rooms reviewed")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ProgressView(value: snapshot.completionFraction)
                .tint(DeadlineStyle(snapshot: snapshot).tint)

            Text(DeadlineStyle(snapshot: snapshot).shortText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(DeadlineStyle(snapshot: snapshot).tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "MoveProof. \(snapshot.areasComplete) of \(snapshot.areasTotal) rooms reviewed. \(DeadlineStyle(snapshot: snapshot).shortText)."
        )
    }
}

// MARK: - Medium

/// systemMedium: adds what still needs attention and what is waiting to be filed,
/// still without naming the property or describing any damage.
struct MediumInspectionView: View {

    let snapshot: InspectionSnapshot

    private var style: DeadlineStyle { DeadlineStyle(snapshot: snapshot) }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("MoveProof", systemImage: "house.badge.clock")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("\(snapshot.areasComplete)/\(snapshot.areasTotal)")
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text("rooms reviewed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ProgressView(value: snapshot.completionFraction)
                    .tint(style.tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                detailRow(
                    symbol: style.symbol,
                    tint: style.tint,
                    text: style.longText
                )

                detailRow(
                    symbol: snapshot.areasNeedingAttention == 0 ? "checkmark.circle" : "exclamationmark.triangle.fill",
                    tint: snapshot.areasNeedingAttention == 0 ? .green : .orange,
                    text: attentionText
                )

                detailRow(
                    symbol: "photo.on.rectangle.angled",
                    tint: .secondary,
                    text: snapshot.evidenceCount == 1 ? "1 item of evidence" : "\(snapshot.evidenceCount) items of evidence"
                )

                if snapshot.pendingInboxCount > 0 {
                    detailRow(
                        symbol: "tray.full",
                        tint: .accentColor,
                        text: snapshot.pendingInboxCount == 1
                            ? "1 shared item to file"
                            : "\(snapshot.pendingInboxCount) shared items to file"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "MoveProof. \(snapshot.areasComplete) of \(snapshot.areasTotal) rooms reviewed. \(style.longText). \(attentionText)."
        )
    }

    private var attentionText: String {
        switch snapshot.areasNeedingAttention {
        case 0: "Nothing outstanding"
        case 1: "1 room needs attention"
        default: "\(snapshot.areasNeedingAttention) rooms need attention"
        }
    }

    private func detailRow(symbol: String, tint: Color, text: String) -> some View {
        Label {
            Text(text)
                .font(.caption)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
        }
    }
}

// MARK: - Empty state

/// Shown only when the app genuinely has no tenancy — never as a stand-in for data
/// that exists but could not be read.
struct NoTenancyView: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("MoveProof", systemImage: "house.badge.plus")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("No property yet")
                .font(.headline)
                .minimumScaleFactor(0.7)
            Text("Add the place you've moved into to start a walkthrough.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Deadline presentation

/// Turns the days-remaining count into wording and a colour, shared by both families.
struct DeadlineStyle {

    let snapshot: InspectionSnapshot

    var shortText: String {
        guard let days = snapshot.daysUntilConditionReportDue else { return "No due date" }
        return switch days {
        case ..<0: "Report overdue"
        case 0: "Due today"
        case 1: "1 day left"
        default: "\(days) days left"
        }
    }

    var longText: String {
        guard let days = snapshot.daysUntilConditionReportDue else {
            return "No report due date set"
        }
        return switch days {
        case ..<0: "Condition report overdue"
        case 0: "Condition report due today"
        case 1: "Condition report due tomorrow"
        default: "\(days) days until the report is due"
        }
    }

    var tint: Color {
        guard let days = snapshot.daysUntilConditionReportDue else { return .secondary }
        if days < 0 { return .red }
        if days <= 2 { return .orange }
        return snapshot.completionFraction >= 1 ? .green : .accentColor
    }

    var symbol: String {
        guard let days = snapshot.daysUntilConditionReportDue else { return "calendar.badge.question" }
        if days < 0 { return "calendar.badge.exclamationmark" }
        if days <= 2 { return "clock.badge.exclamationmark" }
        return "calendar"
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
