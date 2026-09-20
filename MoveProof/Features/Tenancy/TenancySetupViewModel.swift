import Foundation

/// Drives the property setup form.
///
/// Validation wording comes from `TenancySetupError`, so the message the tenant
/// reads in the form is the same message the rule produces — there is no second,
/// drifting copy of the rules in the UI.
@Observable
final class TenancySetupViewModel {

    var propertyAddress = ""
    var moveInDate = Date()
    var conditionReportDueDate = Tenancy.defaultConditionReportDueDate(movingIn: Date())
    /// When on, the due date follows the NSW seven-day default as the move-in date changes.
    var usesDefaultDueDate = true

    private(set) var existingTenancy: Tenancy?
    private(set) var didFinish = false
    var inlineMessage: TenantMessage?
    var message: TenantMessage?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var isEditingExistingTenancy: Bool { existingTenancy != nil }

    var title: String {
        isEditingExistingTenancy ? "Property details" : "Add your property"
    }

    var saveButtonTitle: String {
        isEditingExistingTenancy ? "Save changes" : "Start walkthrough"
    }

    /// Explains the default due date to the tenant, citing the rule it comes from.
    var dueDateFootnote: String {
        "NSW condition reports are returned to the landlord or agent within seven days of moving in. Turn this off if your agent set a different date."
    }

    func load() {
        do {
            if let tenancy = try environment.tenancyRepository.fetchActiveTenancy() {
                existingTenancy = tenancy
                propertyAddress = tenancy.propertyAddress
                moveInDate = tenancy.moveInDate
                conditionReportDueDate = tenancy.conditionReportDueDate
                usesDefaultDueDate = Calendar.current.isDate(
                    tenancy.conditionReportDueDate,
                    inSameDayAs: Tenancy.defaultConditionReportDueDate(movingIn: tenancy.moveInDate)
                )
            }
        } catch {
            message = TenantMessage(error, whileDoing: "opening your property details")
        }
    }

    /// Keeps the suggested due date in step with the move-in date while the tenant
    /// has not overridden it.
    func moveInDateChanged() {
        guard usesDefaultDueDate else { return }
        conditionReportDueDate = Tenancy.defaultConditionReportDueDate(movingIn: moveInDate)
    }

    func defaultDueDateToggled() {
        if usesDefaultDueDate {
            conditionReportDueDate = Tenancy.defaultConditionReportDueDate(movingIn: moveInDate)
        }
    }

    /// - Returns: `true` when the form should close.
    @discardableResult
    func save() -> Bool {
        inlineMessage = nil

        if var tenancy = existingTenancy {
            return updateExisting(&tenancy)
        }
        return startNew()
    }

    private func startNew() -> Bool {
        let request = StartTenancyInspectionUseCase.Request(
            propertyAddress: propertyAddress,
            moveInDate: moveInDate,
            conditionReportDueDate: usesDefaultDueDate ? nil : conditionReportDueDate
        )
        do {
            try environment.startTenancyInspection.execute(request)
            didFinish = true
            return true
        } catch {
            inlineMessage = TenantMessage(error, whileDoing: "setting up your property")
            return false
        }
    }

    /// Editing an existing tenancy re-applies the same field rules by hand, because
    /// `StartTenancyInspectionUseCase` would correctly refuse a second walkthrough.
    private func updateExisting(_ tenancy: inout Tenancy) -> Bool {
        let address = propertyAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            inlineMessage = TenantMessage(
                TenancySetupError.missingPropertyAddress,
                whileDoing: "saving your property details"
            )
            return false
        }

        let calendar = Calendar.current
        let dueDate = usesDefaultDueDate
            ? Tenancy.defaultConditionReportDueDate(movingIn: moveInDate)
            : conditionReportDueDate

        guard calendar.startOfDay(for: dueDate) >= calendar.startOfDay(for: moveInDate) else {
            inlineMessage = TenantMessage(
                TenancySetupError.conditionReportDueBeforeMoveIn,
                whileDoing: "saving your property details"
            )
            return false
        }

        tenancy.propertyAddress = address
        tenancy.moveInDate = moveInDate
        tenancy.conditionReportDueDate = dueDate

        do {
            try environment.tenancyRepository.save(tenancy)
            didFinish = true
            return true
        } catch {
            inlineMessage = TenantMessage(error, whileDoing: "saving your property details")
            return false
        }
    }
}
