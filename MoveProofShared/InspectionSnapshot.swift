import Foundation

/// A deliberately small, privacy-reduced summary of the current inspection,
/// published by the main app into the App Group so the widget can render without
/// ever touching Core Data.
///
/// Privacy note: the snapshot intentionally carries **no property address, no
/// photographs and no damage descriptions**. A Home Screen widget is visible to
/// anyone who can see the device, so only counts, progress and the reporting
/// deadline are exposed. Detailed evidence stays inside the app behind the
/// device passcode.
struct InspectionSnapshot: Codable, Equatable, Sendable {

    /// Total number of inspection areas in the active tenancy.
    let areasTotal: Int
    /// Areas whose required condition items have all been reviewed and signed off.
    let areasComplete: Int
    /// Areas that contain damage recorded without a note or supporting evidence.
    let areasNeedingAttention: Int
    /// Count of evidence files the tenant has filed against the active tenancy.
    let evidenceCount: Int
    /// Items sitting in the Share Extension inbox awaiting import.
    let pendingInboxCount: Int
    /// Whole days remaining until the condition report is due. Negative once overdue.
    let daysUntilConditionReportDue: Int?
    /// When the main app last published this snapshot.
    let generatedAt: Date

    /// `true` when there is no active tenancy to summarise.
    let hasActiveTenancy: Bool

    static let noActiveTenancy = InspectionSnapshot(
        areasTotal: 0,
        areasComplete: 0,
        areasNeedingAttention: 0,
        evidenceCount: 0,
        pendingInboxCount: 0,
        daysUntilConditionReportDue: nil,
        generatedAt: Date(timeIntervalSince1970: 0),
        hasActiveTenancy: false
    )

    /// Completion as a 0...1 fraction, safe when there are no areas yet.
    var completionFraction: Double {
        guard areasTotal > 0 else { return 0 }
        return Double(areasComplete) / Double(areasTotal)
    }
}

/// Reads and writes `InspectionSnapshot` at a fixed location in the App Group.
///
/// The main app is the only writer; the widget is a read-only consumer. This keeps
/// the widget decoupled from the Core Data stack entirely.
struct InspectionSnapshotStore {

    private let fileName = "snapshot.json"

    init() {}

    private func snapshotURL() throws -> URL {
        try AppGroup.directoryURL(.widget).appendingPathComponent(fileName)
    }

    func write(_ snapshot: InspectionSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: try snapshotURL(), options: .atomic)
    }

    /// Returns the published snapshot, or `nil` when the main app has never run
    /// or the container is unavailable. Callers render a first-run state instead
    /// of treating this as an error.
    func read() -> InspectionSnapshot? {
        guard let url = try? snapshotURL(),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(InspectionSnapshot.self, from: data)
    }
}
