import OSLog

/// Technical logging, kept strictly separate from anything a tenant reads.
///
/// Domain rules speak to the tenant through `TenantFacingError`. Failures that
/// are the app's problem rather than the tenant's are recorded here, where a
/// developer can find them, and never rendered on screen.
///
/// Call sites pass a plain `String` rather than an `os` interpolation, so no file
/// outside this one has to import OSLog to report a fault.
struct AppLog {

    private static let subsystem = "com.krischuang.MoveProof"

    static let persistence = AppLog(category: "persistence")
    static let inspection = AppLog(category: "inspection")
    static let evidence = AppLog(category: "evidence")
    static let sharedInbox = AppLog(category: "shared-inbox")

    private let logger: Logger

    private init(category: String) {
        logger = Logger(subsystem: Self.subsystem, category: category)
    }

    /// Records a fault. The message is marked public because it describes app
    /// state, not the tenant's evidence — addresses, notes and file contents are
    /// never passed in here.
    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }
}
