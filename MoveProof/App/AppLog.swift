import OSLog

/// Technical logging, kept separate from anything the tenant reads.
///
/// Domain rules talk to the tenant through `TenantFacingError`. Failures that are the
/// app's fault go here, where a developer can find them, and never on screen.
///
/// Call sites pass a plain `String` instead of an `os` interpolation, so no other
/// file has to import OSLog just to report a problem.
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
    /// state, not the tenant's evidence. Addresses, notes and file contents are never
    /// passed in here.
    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }
}
