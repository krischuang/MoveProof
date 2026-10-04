import Foundation

/// Drives the evidence library: everything filed against this property, and which
/// of it is still waiting to be pinned to a room.
@Observable
final class EvidenceLibraryViewModel {

    struct EvidenceRow: Identifiable, Equatable {
        let evidence: EvidenceItem
        /// "Kitchen · Flooring", or nil when the evidence has not been filed yet.
        let placement: String?

        var id: UUID { evidence.id }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all, unfiled, photos, documents

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: "All"
            case .unfiled: "Needs filing"
            case .photos: "Photos"
            case .documents: "Documents"
            }
        }
    }

    private(set) var tenancy: Tenancy?
    private(set) var rows: [EvidenceRow] = []
    private(set) var hasLoaded = false
    var filter: Filter = .all {
        didSet { applyFilter() }
    }
    var message: TenantMessage?

    private var allRows: [EvidenceRow] = []
    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var unfiledCount: Int {
        allRows.filter { $0.placement == nil }.count
    }

    func load() {
        do {
            guard let tenancy = try environment.tenancyRepository.fetchActiveTenancy() else {
                self.tenancy = nil
                allRows = []
                rows = []
                hasLoaded = true
                return
            }
            self.tenancy = tenancy

            let evidence = try environment.evidenceRepository.fetchEvidence(forTenancy: tenancy.id)

            // Build the room/item labels once rather than per row, so the list does
            // not issue a lookup for every photo it draws.
            let areas = try environment.inspectionRepository.fetchAreas(forTenancy: tenancy.id)
            var placementByItemID: [UUID: String] = [:]
            for area in areas {
                for item in try environment.inspectionRepository.fetchConditionItems(inArea: area.id) {
                    placementByItemID[item.id] = "\(area.name) · \(item.title)"
                }
            }

            allRows = evidence.map { item in
                EvidenceRow(
                    evidence: item,
                    placement: item.conditionItemID.flatMap { placementByItemID[$0] }
                )
            }
            applyFilter()
            hasLoaded = true
        } catch {
            message = TenantMessage(error, whileDoing: "loading your evidence")
            hasLoaded = true
        }
    }

    private func applyFilter() {
        switch filter {
        case .all:
            rows = allRows
        case .unfiled:
            rows = allRows.filter { $0.placement == nil }
        case .photos:
            rows = allRows.filter { $0.evidence.kind == .photograph }
        case .documents:
            rows = allRows.filter { $0.evidence.kind == .document }
        }
    }

    /// Deletes a piece of evidence and the file behind it.
    ///
    /// `DiscardEvidenceUseCase` reports when this leaves damage with nothing to show
    /// for it. That is worth telling the tenant, since it is the gap the app is built
    /// to prevent and they may not realise that was the only photo.
    /// - Returns: `true` when the evidence was discarded.
    @discardableResult
    func remove(_ row: EvidenceRow) -> Bool {
        do {
            let outcome = try environment.discardEvidence.execute(evidenceID: row.evidence.id)
            if let itemTitle = outcome.leftDamageUndocumented {
                message = TenantMessage(
                    title: "That was the only proof you had",
                    whatHappened: "\"\(itemTitle)\" is still recorded as damaged, but now has no photo and no note.",
                    whatToDoNext: "Open that item and add a photo or a short note, or the damage will count as undocumented when you sign the room off."
                )
            }
            load()
            return true
        } catch {
            message = TenantMessage(error, whileDoing: "removing that evidence")
            return false
        }
    }

    func url(for row: EvidenceRow) -> URL? {
        try? environment.evidenceFileStore.url(forStoredFileName: row.evidence.storedFileName)
    }

    var emptyStateMessage: String {
        switch filter {
        case .all:
            "Photos you add while recording a room, and anything you share to MoveProof from another app, will collect here."
        case .unfiled:
            "Everything you've filed is attached to a room checklist item."
        case .photos:
            "No photos filed against this property yet."
        case .documents:
            "No documents yet. Share a PDF, such as your signed condition report, to MoveProof from Files or Mail."
        }
    }
}
