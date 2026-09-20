import Foundation

/// The tenancy a tenant is documenting: one rental property, one move-in, one
/// condition-report deadline.
///
/// This is a plain value type. It carries no Core Data types, so use cases, view
/// models and tests can all work with it without a persistent store.
struct Tenancy: Identifiable, Equatable, Hashable {

    let id: UUID
    /// Free-text address as the tenant recognises it. Never shown on the widget.
    var propertyAddress: String
    var moveInDate: Date
    /// The date the completed condition report is due back to the landlord or agent.
    var conditionReportDueDate: Date
    let createdAt: Date
    var status: TenancyStatus

    init(
        id: UUID = UUID(),
        propertyAddress: String,
        moveInDate: Date,
        conditionReportDueDate: Date,
        createdAt: Date = Date(),
        status: TenancyStatus = .documenting
    ) {
        self.id = id
        self.propertyAddress = propertyAddress
        self.moveInDate = moveInDate
        self.conditionReportDueDate = conditionReportDueDate
        self.createdAt = createdAt
        self.status = status
    }

    /// NSW residential tenancy condition reports are returned to the landlord or
    /// agent within seven days of moving in, so that is the default deadline the
    /// app proposes. The tenant can override it if their agent set another date.
    ///
    /// See `docs/references.md` for the NSW Government source.
    static let conditionReportWindowInDays = 7

    /// Default deadline for a given move-in date.
    static func defaultConditionReportDueDate(
        movingIn moveInDate: Date,
        calendar: Calendar = .current
    ) -> Date {
        calendar.date(
            byAdding: .day,
            value: conditionReportWindowInDays,
            to: calendar.startOfDay(for: moveInDate)
        ) ?? moveInDate
    }

    /// Whole days from `date` until the report is due. Negative once the date has passed.
    func daysUntilConditionReportDue(asOf date: Date, calendar: Calendar = .current) -> Int {
        let from = calendar.startOfDay(for: date)
        let to = calendar.startOfDay(for: conditionReportDueDate)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }
}

/// Where a tenancy sits in the documentation workflow.
enum TenancyStatus: String, CaseIterable, Equatable, Hashable {

    /// The tenant is still working through the rooms.
    case documenting
    /// Every inspection area has been signed off.
    case reportReady
    /// Kept for reference after the tenancy ends.
    case archived

    var label: String {
        switch self {
        case .documenting: "Documenting"
        case .reportReady: "Report ready"
        case .archived: "Archived"
        }
    }

    /// Only one tenancy is actively being documented at a time; that is the one
    /// the dashboard, the widget and shared-evidence import all resolve to.
    var isActive: Bool {
        self != .archived
    }
}
