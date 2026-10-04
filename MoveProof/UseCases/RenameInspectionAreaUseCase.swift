import Foundation

/// Renames a room, for when the default names do not match what the tenant calls
/// the place. "Second bedroom" becomes "Study", "Balcony or outdoor area" becomes
/// "Courtyard".
///
/// A rename cannot blank the name out, and it applies the same uniqueness rule as
/// `AddInspectionAreaUseCase`, since a rename can collide just as easily as a new
/// room can. Renaming a room to the name it already has does nothing, so it is not
/// reported as a clash with itself.
struct RenameInspectionAreaUseCase {

    let inspectionRepository: InspectionRepository

    init(inspectionRepository: InspectionRepository) {
        self.inspectionRepository = inspectionRepository
    }

    struct Request {
        var areaID: UUID
        var newName: String
    }

    /// - Returns: the room under its current name.
    /// - Throws: `InspectionAreaEditError` when a rule is broken.
    @discardableResult
    func execute(_ request: Request) throws -> InspectionArea {

        guard var area = try inspectionRepository.fetchArea(id: request.areaID) else {
            throw InspectionAreaEditError.inspectionAreaNotFound
        }

        let trimmed = request.newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw InspectionAreaEditError.roomNameMissing
        }
        guard trimmed != area.name else { return area }

        // Compare against the other rooms, not this one.
        let siblings = try inspectionRepository
            .fetchAreas(forTenancy: area.tenancyID)
            .filter { $0.id != area.id }
        guard !siblings.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw InspectionAreaEditError.duplicateRoomName(name: trimmed)
        }

        area.name = trimmed
        try inspectionRepository.save(area)
        return area
    }
}
