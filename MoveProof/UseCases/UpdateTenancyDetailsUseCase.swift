import Foundation

/// Corrects the details of the property the tenant is already documenting.
///
/// A tenant might mistype the address, or the agent might tell them the report is
/// due on a different date. They need to fix that without losing the walkthrough
/// they have built. `StartTenancyInspectionUseCase` would refuse, since its job is
/// to begin a new walkthrough, so editing is a separate operation.
///
/// The field rules come from `TenancyDetailsRules`, shared with
/// `StartTenancyInspectionUseCase` so the two screens cannot disagree about what a
/// valid address or due date is. The one exception is the "this move-in date looks
/// mistyped" check, which is skipped here: it exists to catch typos during setup,
/// and a tenancy being edited may have started months ago.
///
/// The id, creation date and status are not editable. They are copied across
/// untouched so that fixing an address cannot detach the evidence already filed
/// against the tenancy.
struct UpdateTenancyDetailsUseCase {

    let tenancyRepository: TenancyRepository

    init(tenancyRepository: TenancyRepository) {
        self.tenancyRepository = tenancyRepository
    }

    struct Request {
        var tenancyID: UUID
        var details: TenancyDetails
    }

    /// - Returns: the tenancy as it now stands.
    /// - Throws: `TenancySetupError` when a rule is broken.
    @discardableResult
    func execute(_ request: Request, now: Date = Date(), calendar: Calendar = .current) throws -> Tenancy {

        guard let active = try tenancyRepository.fetchActiveTenancy(),
              active.id == request.tenancyID else {
            throw TenancySetupError.tenancyNoLongerBeingDocumented
        }

        let validated = try TenancyDetailsRules.validate(
            request.details,
            backdatingCheck: .skipped,
            now: now,
            calendar: calendar
        )

        // Start from the stored tenancy so id, createdAt and status are kept.
        var tenancy = active
        tenancy.propertyAddress = validated.propertyAddress
        tenancy.moveInDate = validated.moveInDate
        tenancy.conditionReportDueDate = validated.conditionReportDueDate

        try tenancyRepository.save(tenancy)
        return tenancy
    }
}
