import Foundation

/// Drives the property setup form.
///
/// The form holds no rules of its own. Setting up goes through
/// `StartTenancyInspectionUseCase` and editing goes through
/// `UpdateTenancyDetailsUseCase`. Both check the fields with the same
/// `TenancyDetailsRules`, so the message the tenant reads comes from the rule itself
/// and there is no second copy of it here that could drift.
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

        if let tenancy = existingTenancy {
            return updateExisting(tenancy)
        }
        return startNew()
    }

    /// What the tenant has typed, in the shape the domain checks. The only thing
    /// decided here is whether they are using the suggested due date or their own.
    private var enteredDetails: TenancyDetails {
        TenancyDetails(
            propertyAddress: propertyAddress,
            moveInDate: moveInDate,
            conditionReportDueDate: usesDefaultDueDate ? nil : conditionReportDueDate
        )
    }

    private func startNew() -> Bool {
        let request = StartTenancyInspectionUseCase.Request(
            propertyAddress: enteredDetails.propertyAddress,
            moveInDate: enteredDetails.moveInDate,
            conditionReportDueDate: enteredDetails.conditionReportDueDate
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

    /// Editing the details of the walkthrough already under way.
    ///
    /// `StartTenancyInspectionUseCase` would refuse this as a second walkthrough, so
    /// it is a separate use case instead of a repository write with the rules copied
    /// into this file.
    private func updateExisting(_ tenancy: Tenancy) -> Bool {
        let request = UpdateTenancyDetailsUseCase.Request(
            tenancyID: tenancy.id,
            details: enteredDetails
        )
        do {
            existingTenancy = try environment.updateTenancyDetails.execute(request)
            didFinish = true
            return true
        } catch {
            inlineMessage = TenantMessage(error, whileDoing: "saving your property details")
            return false
        }
    }
}
