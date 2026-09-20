import CoreData

/// Owns the Core Data stack. Nothing above the repository layer sees this type,
/// and no view or view model ever touches the context it holds.
struct InspectionStore {

    /// The stack the running app uses.
    static let shared = InspectionStore()

    let container: NSPersistentContainer

    /// - Parameter inMemory: when `true`, the store is discarded on teardown.
    ///   Used by SwiftUI previews and the repository integration tests so they
    ///   never touch the tenant's real records.
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "MoveProof")

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        }

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }

        if let loadError {
            // The store is the app's only record of the tenant's evidence. If it
            // cannot be opened there is no safe degraded mode to continue in, so
            // fail loudly here rather than silently losing writes later.
            fatalError("MoveProof could not open its evidence store: \(loadError)")
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    }

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    /// Empties the store so a UI test starts from a known first-run state.
    ///
    /// Only runs when the UI test harness passes `-MoveProofResetStoreForUITesting`,
    /// so there is no path from normal use into deleting a tenant's evidence.
    static func resetIfRequestedByUITest(store: InspectionStore) {
        guard ProcessInfo.processInfo.arguments.contains("-MoveProofResetStoreForUITesting") else {
            return
        }

        let context = store.viewContext
        // Tenancy cascades to rooms, checklist items and evidence metadata.
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "TenancyEntity")
        if let tenancies = try? context.fetch(request) as? [NSManagedObject] {
            tenancies.forEach(context.delete)
            try? context.save()
        }

        // Clear the App Group directories too, so a previous run's files and
        // widget snapshot cannot leak into the next test.
        for directory in [AppGroup.Directory.evidence, .sharedEvidenceInbox, .widget] {
            guard let url = try? AppGroup.directoryURL(directory),
                  let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            else { continue }
            contents.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }
}
