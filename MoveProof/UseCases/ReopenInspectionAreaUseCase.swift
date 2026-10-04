import Foundation

/// Reopens a room the tenant has already signed off, so they can change something
/// they recorded.
///
/// Sign-off is reversible on purpose. A tenant who spots a crack the day after
/// signing a room off should be able to record it; if the room locked, the easier
/// option would be to leave the crack undocumented. `CompleteInspectionAreaUseCase`
/// applies all its rules again at the second sign-off.
///
/// A reopened room goes back to `inProgress` rather than `notStarted`, because
/// things have already been recorded in it and showing it as untouched would give
/// the wrong count on the dashboard and the widget. Reopening a room that was never
/// signed off is reported instead of quietly doing nothing.
struct ReopenInspectionAreaUseCase {

    let inspectionRepository: InspectionRepository

    init(inspectionRepository: InspectionRepository) {
        self.inspectionRepository = inspectionRepository
    }

    /// - Returns: the room, now back in progress.
    /// - Throws: `InspectionAreaEditError` when a rule is broken.
    @discardableResult
    func execute(areaID: UUID) throws -> InspectionArea {

        guard var area = try inspectionRepository.fetchArea(id: areaID) else {
            throw InspectionAreaEditError.inspectionAreaNotFound
        }
        guard area.inspectionStatus == .complete else {
            throw InspectionAreaEditError.roomNotSignedOff(roomName: area.name)
        }

        area.inspectionStatus = .inProgress
        try inspectionRepository.save(area)
        return area
    }
}
