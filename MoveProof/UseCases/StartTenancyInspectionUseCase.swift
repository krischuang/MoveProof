import Foundation

/// Starts documenting a new property: validates what the tenant entered, creates
/// the tenancy, and seeds the rooms and checklists they will walk through.
///
/// ## Rules enforced
/// 1. A property address is required. Evidence that cannot be tied to an address is
///    not much use later, so MoveProof refuses to start without one.
/// 2. A move-in date more than `TenancySetupError.maximumBackdatedMoveInDays` in
///    the past is rejected as a likely typo rather than silently accepted.
/// 3. The condition report cannot be due before the tenant moves in.
/// 4. Only one tenancy can be actively documented at a time, so a second start is
///    refused rather than quietly splitting the tenant's evidence in two.
///
/// Rules 1 to 3 are field rules shared with `UpdateTenancyDetailsUseCase`, so they
/// live in `TenancyDetailsRules` and are written once instead of once per screen.
/// Rule 4 only applies when starting out, so it stays here.
struct StartTenancyInspectionUseCase {

    let tenancyRepository: TenancyRepository
    let inspectionRepository: InspectionRepository

    init(tenancyRepository: TenancyRepository, inspectionRepository: InspectionRepository) {
        self.tenancyRepository = tenancyRepository
        self.inspectionRepository = inspectionRepository
    }

    struct Request {
        var propertyAddress: String
        var moveInDate: Date
        /// `nil` means "use the seven-day default MoveProof proposes".
        var conditionReportDueDate: Date?
        /// Rooms to create. Defaults to the standard set.
        var areaNames: [String] = InspectionArea.defaultAreaNames
    }

    /// - Returns: the tenancy that was created, with its rooms already seeded.
    /// - Throws: `TenancySetupError` when a rule is broken. A storage failure comes
    ///   out as `RepositoryError` on purpose: unlike capturing or importing evidence,
    ///   nothing here half-succeeds in a way the tenant needs explaining, so there is
    ///   no domain wording to add that `UnexpectedFailure` does not already give them
    ///   at the UI boundary. See `RepositoryError` for the rule this follows.
    @discardableResult
    func execute(_ request: Request, now: Date = Date(), calendar: Calendar = .current) throws -> Tenancy {

        // Rules 1 to 3. The field checks run first so someone filling in a blank
        // form hears about the field in front of them, not about a walkthrough on
        // another screen.
        let validated = try TenancyDetailsRules.validate(
            TenancyDetails(
                propertyAddress: request.propertyAddress,
                moveInDate: request.moveInDate,
                conditionReportDueDate: request.conditionReportDueDate
            ),
            backdatingCheck: .enforced,
            now: now,
            calendar: calendar
        )

        // Rule 4: refuse a second concurrent walkthrough before writing anything.
        if let existing = try tenancyRepository.fetchActiveTenancy() {
            throw TenancySetupError.inspectionAlreadyStarted(existingAddress: existing.propertyAddress)
        }

        let tenancy = Tenancy(
            propertyAddress: validated.propertyAddress,
            moveInDate: validated.moveInDate,
            conditionReportDueDate: validated.conditionReportDueDate,
            createdAt: now,
            status: .documenting
        )
        try tenancyRepository.save(tenancy)

        // Seed the walkthrough so the tenant opens a ready checklist instead of a
        // blank screen they have to build themselves.
        let (areas, itemsByArea) = Self.buildWalkthrough(
            for: tenancy.id,
            areaNames: request.areaNames
        )
        try inspectionRepository.createAreas(areas, withItems: itemsByArea)

        return tenancy
    }

    /// Builds the default rooms and their checklists.
    ///
    /// Static so a test can check the shape of a new walkthrough without needing a
    /// repository.
    static func buildWalkthrough(
        for tenancyID: UUID,
        areaNames: [String]
    ) -> (areas: [InspectionArea], itemsByArea: [UUID: [ConditionItem]]) {

        var areas: [InspectionArea] = []
        var itemsByArea: [UUID: [ConditionItem]] = [:]

        for (index, name) in areaNames.enumerated() {
            let area = InspectionArea(
                name: name,
                inspectionStatus: .notStarted,
                displayOrder: index,
                tenancyID: tenancyID
            )
            areas.append(area)

            var items = ConditionItem.defaultChecklist.map { entry in
                ConditionItem(
                    title: entry.title,
                    category: entry.category,
                    inspectionAreaID: area.id
                )
            }
            items.append(contentsOf: extraItems(forAreaNamed: name, areaID: area.id))
            itemsByArea[area.id] = items
        }

        return (areas, itemsByArea)
    }

    /// Rooms with appliances or safety fittings get the extra checks a condition
    /// report asks about, so the tenant is prompted instead of having to remember.
    private static func extraItems(forAreaNamed name: String, areaID: UUID) -> [ConditionItem] {
        let lowercased = name.lowercased()
        var extras: [(String, ConditionItemCategory)] = []

        if lowercased.contains("kitchen") {
            extras += [("Oven and cooktop", .appliances), ("Sink and taps", .fixtures)]
        }
        if lowercased.contains("bathroom") {
            extras += [("Toilet, shower and taps", .fixtures), ("Exhaust fan and mould", .safety)]
        }
        if lowercased.contains("laundry") {
            extras += [("Laundry tub and taps", .fixtures)]
        }
        if lowercased.contains("bedroom") || lowercased.contains("living") || lowercased.contains("hallway") {
            extras += [("Smoke alarm", .safety)]
        }

        return extras.map { title, category in
            ConditionItem(title: title, category: category, inspectionAreaID: areaID)
        }
    }
}
