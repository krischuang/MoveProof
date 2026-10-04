import Foundation

/// Drives one room's checklist and its sign-off.
@Observable
final class InspectionAreaDetailViewModel {

    struct ItemRow: Identifiable, Equatable {
        let item: ConditionItem
        let evidenceCount: Int

        var id: UUID { item.id }

        var isFullyDocumented: Bool {
            item.isFullyDocumented(evidenceCount: evidenceCount)
        }

        /// What the row says under the item title.
        var statusLine: String {
            guard item.isReviewed else { return "Not recorded yet" }
            var parts = [item.conditionState.label]
            if evidenceCount == 1 {
                parts.append("1 photo or document")
            } else if evidenceCount > 1 {
                parts.append("\(evidenceCount) photos or documents")
            }
            return parts.joined(separator: " · ")
        }
    }

    private(set) var area: InspectionArea
    private(set) var rows: [ItemRow] = []
    var message: TenantMessage?
    /// Shown inline under the sign-off button, so the tenant sees why it is blocked
    /// without having to dismiss an alert first.
    var signOffBlockedMessage: TenantMessage?

    private let environment: AppEnvironment

    init(environment: AppEnvironment, area: InspectionArea) {
        self.environment = environment
        self.area = area
    }

    var reviewedCount: Int {
        rows.filter { $0.item.isReviewed }.count
    }

    var requiredCount: Int {
        rows.filter { $0.item.isRequired }.count
    }

    var undocumentedDamageCount: Int {
        rows.filter { $0.item.conditionState.requiresSupportingDetail && !$0.isFullyDocumented }.count
    }

    var isComplete: Bool {
        area.inspectionStatus == .complete
    }

    var canAttemptSignOff: Bool {
        !isComplete && !rows.isEmpty
    }

    var groupedRows: [(category: ConditionItemCategory, rows: [ItemRow])] {
        let grouped = Dictionary(grouping: rows, by: \.item.category)
        return ConditionItemCategory.allCases.compactMap { category in
            guard let rows = grouped[category], !rows.isEmpty else { return nil }
            return (category, rows.sorted { $0.item.title < $1.item.title })
        }
    }

    func load() {
        do {
            // Re-read the room so a sign-off made elsewhere is reflected here.
            if let refreshed = try environment.inspectionRepository.fetchArea(id: area.id) {
                area = refreshed
            }
            let items = try environment.inspectionRepository.fetchConditionItems(inArea: area.id)
            rows = try items.map { item in
                ItemRow(
                    item: item,
                    evidenceCount: try environment.evidenceRepository.evidenceCount(forConditionItem: item.id)
                )
            }
        } catch {
            message = TenantMessage(error, whileDoing: "loading this room")
        }
    }

    /// Tries to sign the room off. The use case owns the rules; this only decides
    /// where the resulting message appears.
    /// - Returns: `true` when the room was signed off.
    @discardableResult
    func signOff() -> Bool {
        signOffBlockedMessage = nil
        do {
            area = try environment.completeInspectionArea.execute(areaID: area.id)
            load()
            return true
        } catch {
            signOffBlockedMessage = TenantMessage(error, whileDoing: "signing off this room")
            return false
        }
    }

    /// Reopens a signed-off room so the tenant can change something they recorded.
    /// - Returns: `true` when the room was reopened.
    @discardableResult
    func reopen() -> Bool {
        do {
            area = try environment.reopenInspectionArea.execute(areaID: area.id)
            signOffBlockedMessage = nil
            return true
        } catch {
            message = TenantMessage(error, whileDoing: "reopening this room")
            return false
        }
    }

    /// - Returns: `true` when the room was renamed.
    @discardableResult
    func rename(to newName: String) -> Bool {
        let request = RenameInspectionAreaUseCase.Request(areaID: area.id, newName: newName)
        do {
            let renamed = try environment.renameInspectionArea.execute(request)
            let didChange = renamed.name != area.name
            area = renamed
            return didChange
        } catch {
            message = TenantMessage(error, whileDoing: "renaming this room")
            return false
        }
    }
}
