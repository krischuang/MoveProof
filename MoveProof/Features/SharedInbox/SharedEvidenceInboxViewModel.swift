import Foundation

/// Drives the inbox of files the Share Extension has handed over.
///
/// Every decision here goes through `ImportSharedEvidenceUseCase`. The view model
/// never inspects a content type or checks for duplicates itself — that would put a
/// second copy of the import rules in the UI.
@Observable
final class SharedEvidenceInboxViewModel {

    struct InboxRow: Identifiable, Equatable {
        let item: PendingSharedEvidence

        var id: UUID { item.id }

        /// Where the tenant sent it from, when the host app told us.
        var sourceLine: String {
            guard let source = item.sourceApplication else {
                return item.receivedAt.formatted(date: .abbreviated, time: .shortened)
            }
            return "From \(Self.readableAppName(source)) · \(item.receivedAt.formatted(date: .abbreviated, time: .shortened))"
        }

        var sizeLine: String {
            ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file)
        }

        /// Turns a bundle identifier into something recognisable.
        private static func readableAppName(_ bundleIdentifier: String) -> String {
            switch bundleIdentifier {
            case "com.apple.mobileslideshow": "Photos"
            case "com.apple.DocumentsApp": "Files"
            case "com.apple.mobilemail": "Mail"
            case "com.apple.MobileSMS": "Messages"
            case "com.apple.mobilesafari": "Safari"
            default: bundleIdentifier
            }
        }
    }

    struct FilingOption: Identifiable, Equatable {
        let id: UUID
        let label: String
    }

    private(set) var rows: [InboxRow] = []
    private(set) var filingOptions: [FilingOption] = []
    private(set) var hasTenancy = false
    private(set) var hasLoaded = false

    /// Which checklist item each pending row will be filed against, if any.
    var selectedFilings: [UUID: UUID] = [:]
    var message: TenantMessage?
    var confirmation: String?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func load() {
        do {
            let tenancy = try environment.tenancyRepository.fetchActiveTenancy()
            hasTenancy = tenancy != nil

            if let tenancy {
                let areas = try environment.inspectionRepository.fetchAreas(forTenancy: tenancy.id)
                filingOptions = try areas.flatMap { area in
                    try environment.inspectionRepository.fetchConditionItems(inArea: area.id).map {
                        FilingOption(id: $0.id, label: "\(area.name) · \($0.title)")
                    }
                }
            } else {
                filingOptions = []
            }

            rows = try environment.importSharedEvidence.pendingItems().map(InboxRow.init)
            hasLoaded = true
        } catch {
            message = TenantMessage(error, whileDoing: "opening your shared items")
            hasLoaded = true
        }
    }

    /// Files one pending item as evidence.
    /// - Returns: `true` when the import succeeded.
    @discardableResult
    func importItem(_ row: InboxRow) -> Bool {
        let request = ImportSharedEvidenceUseCase.Request(
            item: row.item,
            conditionItemID: selectedFilings[row.id]
        )
        do {
            let evidence = try environment.importSharedEvidence.execute(request)
            confirmation = "\"\(evidence.displayName)\" is now in your evidence."
            selectedFilings[row.id] = nil
            load()
            return true
        } catch {
            message = TenantMessage(error, whileDoing: "filing that shared item")
            // Reload either way: a duplicate or missing file changes what should be
            // on screen, and leaving a stale row invites the tenant to retry blindly.
            load()
            return false
        }
    }

    func discard(_ row: InboxRow) {
        do {
            try environment.importSharedEvidence.discard(row.item)
            load()
        } catch {
            message = TenantMessage(error, whileDoing: "removing that shared item")
        }
    }

    var emptyStateDescription: String {
        hasTenancy
            ? "Share a photo or PDF to MoveProof from Photos, Files or Mail, and it will wait here until you file it against a room."
            : "Add the property you've moved into on the Walkthrough tab. Anything you share to MoveProof will wait here until there's somewhere to file it."
    }
}
