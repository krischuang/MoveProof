import Foundation

/// A single thing the tenant checks inside a room (walls, flooring, a window, an
/// appliance) together with the condition they found it in.
struct ConditionItem: Identifiable, Equatable, Hashable {

    let id: UUID
    var title: String
    var category: ConditionItemCategory
    var conditionState: ConditionState
    /// What the tenant wrote about what they found.
    var notes: String
    /// Set the first time a condition is recorded; `nil` means still unreviewed.
    var reviewedAt: Date?
    /// Required items must be reviewed before the room can be signed off.
    var isRequired: Bool
    let inspectionAreaID: UUID

    init(
        id: UUID = UUID(),
        title: String,
        category: ConditionItemCategory,
        conditionState: ConditionState = .notReviewed,
        notes: String = "",
        reviewedAt: Date? = nil,
        isRequired: Bool = true,
        inspectionAreaID: UUID
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.conditionState = conditionState
        self.notes = notes
        self.reviewedAt = reviewedAt
        self.isRequired = isRequired
        self.inspectionAreaID = inspectionAreaID
    }

    var isReviewed: Bool {
        conditionState != .notReviewed
    }

    /// Whether this record carries enough detail for the tenant to identify later
    /// what they saw. Damage with neither a note nor a photo is the case MoveProof
    /// exists to prevent, so it is modelled explicitly.
    ///
    /// - Parameter evidenceCount: how many evidence files are filed against this item.
    func isFullyDocumented(evidenceCount: Int) -> Bool {
        guard conditionState.requiresSupportingDetail else { return isReviewed }
        return !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || evidenceCount > 0
    }

    /// The checklist MoveProof seeds into each new room.
    static let defaultChecklist: [(title: String, category: ConditionItemCategory)] = [
        ("Walls and ceiling", .structure),
        ("Flooring", .structure),
        ("Windows and coverings", .fixtures),
        ("Doors and locks", .fixtures),
        ("Power points and lighting", .fixtures),
        ("Cleanliness", .cleanliness)
    ]
}

/// Groups condition items the way a condition report does.
enum ConditionItemCategory: String, CaseIterable, Equatable, Hashable {

    case structure
    case fixtures
    case appliances
    case cleanliness
    case safety

    var label: String {
        switch self {
        case .structure: "Structure"
        case .fixtures: "Fixtures"
        case .appliances: "Appliances"
        case .cleanliness: "Cleanliness"
        case .safety: "Safety"
        }
    }

    var symbolName: String {
        switch self {
        case .structure: "square.split.bottomrightquarter"
        case .fixtures: "lightbulb"
        case .appliances: "oven"
        case .cleanliness: "sparkles"
        case .safety: "flame"
        }
    }
}

/// What the tenant found. Ordered from "nothing to report" to "needs recording
/// carefully", which is also the order shown in the picker.
enum ConditionState: String, CaseIterable, Equatable, Hashable {

    case notReviewed
    case undamaged
    case minorWear
    case damaged
    case notWorking

    var label: String {
        switch self {
        case .notReviewed: "Not reviewed"
        case .undamaged: "Undamaged"
        case .minorWear: "Minor wear"
        case .damaged: "Damaged"
        case .notWorking: "Not working"
        }
    }

    /// States the tenant may choose; `notReviewed` is the starting value only.
    static var selectableStates: [ConditionState] {
        allCases.filter { $0 != .notReviewed }
    }

    /// Damage and faults are the records most likely to be questioned later, so
    /// MoveProof requires a note or a photo before treating them as documented.
    ///
    /// This is the business rule enforced by `RecordConditionEvidenceUseCase`.
    var requiresSupportingDetail: Bool {
        switch self {
        case .damaged, .notWorking: true
        case .notReviewed, .undamaged, .minorWear: false
        }
    }

    var symbolName: String {
        switch self {
        case .notReviewed: "questionmark.circle"
        case .undamaged: "checkmark.circle"
        case .minorWear: "exclamationmark.circle"
        case .damaged: "exclamationmark.triangle.fill"
        case .notWorking: "xmark.octagon.fill"
        }
    }
}
