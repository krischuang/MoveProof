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

    /// Adds a room the standard set did not cover, e.g. a garage or study.
    func addArea(named name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tenancy, !trimmed.isEmpty else { return false }

        let nextOrder = (summaries.map { $0.area.displayOrder }.max() ?? -1) + 1
        let (areas, items) = StartTenancyInspectionUseCase.buildWalkthrough(
            for: tenancy.id,
            areaNames: [trimmed]
        )
        // buildWalkthrough numbers from zero; append this room after the existing ones.
        let area = InspectionArea(
            id: areas[0].id,
            name: trimmed,
            displayOrder: nextOrder,
            tenancyID: tenancy.id
        )

        do {
            try environment.inspectionRepository.createAreas([area], withItems: items)
            load()
            return true
        } catch {
            message = TenantMessage(error, whileDoing: "adding that room")
            return false
        }
    }

    func deleteAreas(at offsets: IndexSet) {
        let ids = offsets.map { summaries[$0].area.id }
        do {
            for id in ids {
                try environment.inspectionRepository.deleteArea(id: id)
            }
            load()
        } catch {
            message = TenantMessage(error, whileDoing: "removing that room")
        }
    }
}
