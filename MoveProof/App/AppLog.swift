import OSLog

/// Technical logging, kept strictly separate from anything a tenant reads.
///
/// Domain rules speak to the tenant through `TenantFacingError`. Failures that
/// are the app's problem rather than the tenant's are recorded here, where a
/// developer can find them, and never rendered on screen.
enum AppLog {

    private static let subsystem = "com.krischuang.MoveProof"

    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let inspection = Logger(subsystem: subsystem, category: "inspection")
    static let evidence = Logger(subsystem: subsystem, category: "evidence")
    static let sharedInbox = Logger(subsystem: subsystem, category: "shared-inbox")
}
