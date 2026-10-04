import Foundation

/// The property details a tenant types in, before they have been checked.
///
/// Setting up a walkthrough and editing it later use the same three fields, so they
/// are modelled once and checked in one place instead of each use case keeping its
/// own copy of the rules.
struct TenancyDetails: Equatable {

    var propertyAddress: String
    var moveInDate: Date
    /// `nil` means "use the seven-day NSW default MoveProof proposes".
    var conditionReportDueDate: Date?

    init(propertyAddress: String, moveInDate: Date, conditionReportDueDate: Date? = nil) {
        self.propertyAddress = propertyAddress
        self.moveInDate = moveInDate
        self.conditionReportDueDate = conditionReportDueDate
    }
}

/// Details that have passed all the field rules, with the default due date filled in.
///
/// The only way to get one of these is through `TenancyDetailsRules.validate`, so a
/// save path cannot skip the checks by accident.
struct ValidatedTenancyDetails: Equatable {

    let propertyAddress: String
    let moveInDate: Date
    let conditionReportDueDate: Date

    fileprivate init(propertyAddress: String, moveInDate: Date, conditionReportDueDate: Date) {
        self.propertyAddress = propertyAddress
        self.moveInDate = moveInDate
        self.conditionReportDueDate = conditionReportDueDate
    }
}

/// The one implementation of the property detail rules.
///
/// `StartTenancyInspectionUseCase` and `UpdateTenancyDetailsUseCase` both go through
/// here, so a tenant who sets a bad due date gets the same message whether they are
/// setting up or fixing a mistake. None of this is repeated in the view layer.
enum TenancyDetailsRules {

    /// Whether to apply the "this move-in date looks mistyped" check.
    enum BackdatingCheck {

        /// Used at setup. A move-in date months in the past is much more likely to
        /// be a typo than a tenancy the tenant is only now getting round to.
        case enforced

        /// Used when editing a tenancy that is already under way. It started when it
        /// started, possibly months ago, so the typo check would only get in the way.
        case skipped
    }

    /// - Throws: `TenancySetupError` when a field rule is broken.
    static func validate(
        _ details: TenancyDetails,
        backdatingCheck: BackdatingCheck,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> ValidatedTenancyDetails {

        // Rule: the address is what ties every later piece of evidence to a place.
        let address = details.propertyAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            throw TenancySetupError.missingPropertyAddress
        }

        // Rule: a move-in date far in the past is probably a typo.
        if case .enforced = backdatingCheck {
            let daysSinceMoveIn = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: details.moveInDate),
                to: calendar.startOfDay(for: now)
            ).day ?? 0
            if daysSinceMoveIn > TenancySetupError.maximumBackdatedMoveInDays {
                throw TenancySetupError.moveInDateTooFarInPast(days: daysSinceMoveIn)
            }
        }

        // Rule: the due date has to be on or after the move-in date.
        let dueDate = details.conditionReportDueDate
            ?? Tenancy.defaultConditionReportDueDate(movingIn: details.moveInDate, calendar: calendar)
        if calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: details.moveInDate) {
            throw TenancySetupError.conditionReportDueBeforeMoveIn
        }

        return ValidatedTenancyDetails(
            propertyAddress: address,
            moveInDate: details.moveInDate,
            conditionReportDueDate: dueDate
        )
    }
}
