import Foundation

/// Adds a room the default set did not cover, such as a study, a garage or a second
/// bathroom, and gives it the same checklist as every other room.
///
/// Room names have to be unique within a walkthrough. Two rooms both called
/// "Bedroom" make the report ambiguous when the tenant is showing an agent a photo
/// and saying which room it came from.
///
/// The new room gets the standard checklist from the same
/// `StartTenancyInspectionUseCase.buildWalkthrough` used at setup, so a room added
/// later is no different from one created at the start, and it goes after the
/// existing rooms so the list still follows the order the tenant walks the property.
struct AddInspectionAreaUseCase {

    let tenancyRepository: TenancyRepository
    let inspectionRepository: InspectionRepository

    init(tenancyRepository: TenancyRepository, inspectionRepository: InspectionRepository) {
        self.tenancyRepository = tenancyRepository
        self.inspectionRepository = inspectionRepository
    }

    /// - Returns: the room that was created, with its checklist already stored.
    /// - Throws: `InspectionAreaEditError` when a rule is broken.
    @discardableResult
    func execute(named name: String) throws -> InspectionArea {

        guard let tenancy = try tenancyRepository.fetchActiveTenancy() else {
            throw InspectionAreaEditError.noActiveTenancy
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw InspectionAreaEditError.roomNameMissing
        }

        let existing = try inspectionRepository.fetchAreas(forTenancy: tenancy.id)
        guard !existing.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw InspectionAreaEditError.duplicateRoomName(name: trimmed)
        }

        // Reuse the setup flow's seeding so there is one definition of what a new
        // room starts with.
        let (seeded, itemsBySeededArea) = StartTenancyInspectionUseCase.buildWalkthrough(
            for: tenancy.id,
            areaNames: [trimmed]
        )
        guard let template = seeded.first else {
            throw InspectionAreaEditError.roomNameMissing
        }

        // buildWalkthrough numbers from zero, so renumber it onto the end.
        let area = InspectionArea(
            id: template.id,
            name: trimmed,
            inspectionStatus: .notStarted,
            displayOrder: (existing.map(\.displayOrder).max() ?? -1) + 1,
            tenancyID: tenancy.id
        )

        try inspectionRepository.createAreas([area], withItems: itemsBySeededArea)
        return area
    }
}
