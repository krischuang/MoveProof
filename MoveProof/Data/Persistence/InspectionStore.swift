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
}
