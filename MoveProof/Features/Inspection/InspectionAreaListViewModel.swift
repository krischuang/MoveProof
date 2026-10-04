import Foundation

/// Drives the room list.
@Observable
final class InspectionAreaListViewModel {

    /// A room plus the counts the list needs, assembled once so the row itself does
    /// no work while scrolling.
    struct AreaSummary: Identifiable, Equatable {
        let area: InspectionArea
        let reviewedCount: Int
        let requiredCount: Int
        let undocumentedDamageCount: Int

        var id: UUID { area.id }

        var progressFraction: Double {
            guard requiredCount > 0 else { return 0 }
            return Double(reviewedCount) / Double(requiredCount)
        }

        var detailLine: String {
            if area.inspectionStatus == .complete {
                return "Reviewed and signed off"
            }
            if reviewedCount == 0 {
                return "\(requiredCount) items to check"
            }
            return "\(reviewedCount) of \(requiredCount) items recorded"
        }
    }

    private(set) var tenancy: Tenancy?
    private(set) var summaries: [AreaSummary] = []
    private(set) var hasLoaded = false
    var message: TenantMessage?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var completeCount: Int {
        summaries.filter { $0.area.inspectionStatus == .complete }.count
    }

    func load() {
        do {
            guard let tenancy = try environment.tenancyRepository.fetchActiveTenancy() else {
                self.tenancy = nil
                summaries = []
                hasLoaded = true
                return
            }
            self.tenancy = tenancy

            let areas = try environment.inspectionRepository.fetchAreas(forTenancy: tenancy.id)
            let undocumented = try environment.inspectionRepository
                .fetchConditionItemsMissingSupportingDetail(forTenancy: tenancy.id)
            let undocumentedByArea = Dictionary(grouping: undocumented, by: \.inspectionAreaID)

            summaries = try areas.map { area in
                let items = try environment.inspectionRepository.fetchConditionItems(inArea: area.id)
                let required = items.filter(\.isRequired)
                return AreaSummary(
                    area: area,
                    reviewedCount: required.filter(\.isReviewed).count,
                    requiredCount: required.count,
                    undocumentedDamageCount: undocumentedByArea[area.id]?.count ?? 0
                )
            }
            hasLoaded = true
        } catch {
            message = TenantMessage(error, whileDoing: "loading your rooms")
            hasLoaded = true
        }
    }

    /// Adds a room the default set did not cover, e.g. a garage or study.
    ///
    /// The name check, the uniqueness check, the checklist and the ordering are all
    /// handled by `AddInspectionAreaUseCase`. This just reloads and shows the result.
    /// - Returns: `true` when a room was added.
    @discardableResult
    func addArea(named name: String) -> Bool {
        do {
            try environment.addInspectionArea.execute(named: name)
            load()
            return true
        } catch {
            message = TenantMessage(error, whileDoing: "adding that room")
            return false
        }
    }

    /// Removes rooms the tenant swiped away.
    ///
    /// Photos filed against a removed room are not deleted with it. They go back to
    /// the library unfiled. `RemoveInspectionAreaUseCase` reports how many, and the
    /// tenant is told, because an unfiled photo no longer counts as documenting
    /// anything.
    /// - Returns: `true` when at least one room was removed.
    @discardableResult
    func deleteAreas(at offsets: IndexSet) -> Bool {
        let ids = offsets.compactMap { summaries.indices.contains($0) ? summaries[$0].area.id : nil }
        var removedAny = false
        var detachedEvidenceCount = 0

        for id in ids {
            do {
                let outcome = try environment.removeInspectionArea.execute(areaID: id)
                removedAny = removedAny || outcome.didRemoveRoom
                detachedEvidenceCount += outcome.detachedEvidenceCount
            } catch {
                if message == nil {
                    message = TenantMessage(error, whileDoing: "removing that room")
                }
            }
        }

        if detachedEvidenceCount > 0 {
            message = TenantMessage(
                title: "Your photos are still here",
                whatHappened: detachedEvidenceCount == 1
                    ? "1 photo was filed against that room. It's back in your evidence library, no longer attached to a checklist item."
                    : "\(detachedEvidenceCount) photos were filed against that room. They're back in your evidence library, no longer attached to a checklist item.",
                whatToDoNext: "Open the Evidence tab and file them against another room, or leave them as a general record of the property."
            )
        }

        load()
        return removedAny
    }
}
