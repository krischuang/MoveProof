import Foundation

/// One room or area of the property being documented, e.g. "Kitchen" or "Balcony".
struct InspectionArea: Identifiable, Equatable, Hashable {

    let id: UUID
    var name: String
    var inspectionStatus: AreaInspectionStatus
    /// Controls the order rooms appear in, matching the order a tenant walks the property.
    var displayOrder: Int
    let tenancyID: UUID

    init(
        id: UUID = UUID(),
        name: String,
        inspectionStatus: AreaInspectionStatus = .notStarted,
        displayOrder: Int,
        tenancyID: UUID
    ) {
        self.id = id
        self.name = name
        self.inspectionStatus = inspectionStatus
        self.displayOrder = displayOrder
        self.tenancyID = tenancyID
    }

    /// The rooms MoveProof creates for a new tenancy. These cover the areas a NSW
    /// standard condition report asks about; the tenant can rename or extend them.
    static let defaultAreaNames = [
        "Entry and hallway",
        "Living room",
        "Kitchen",
        "Main bedroom",
        "Second bedroom",
        "Bathroom",
        "Laundry",
        "Balcony or outdoor area"
    ]
}

/// Progress of a single room through the walkthrough.
enum AreaInspectionStatus: String, CaseIterable, Equatable, Hashable {

    /// Nothing recorded yet.
    case notStarted
    /// Some condition items reviewed, sign-off not yet given.
    case inProgress
    /// Every required condition item reviewed and the tenant has signed the room off.
    case complete

    var label: String {
        switch self {
        case .notStarted: "Not started"
        case .inProgress: "In progress"
        case .complete: "Reviewed"
        }
    }

    var symbolName: String {
        switch self {
        case .notStarted: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .complete: "checkmark.circle.fill"
        }
    }
}
