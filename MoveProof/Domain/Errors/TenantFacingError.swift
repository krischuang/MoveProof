import Foundation

/// Every domain error MoveProof can show a tenant answers two questions:
/// what went wrong, and what they can do about it.
///
/// This is deliberately separate from `localizedDescription`, which stays technical
/// and goes to the log. A tenant who hits a rule should never see "Save failed".
protocol TenantFacingError: Error {

    /// Plain-language statement of what stopped, in rental-inspection vocabulary.
    var whatHappened: String { get }

    /// The next concrete action the tenant can take.
    var whatToDoNext: String { get }

    /// Short heading for an alert or inline banner.
    var title: String { get }
}

extension TenantFacingError {

    var title: String { "Can't do that yet" }

    /// Single-string form for compact UI such as inline form validation.
    var combinedMessage: String {
        "\(whatHappened) \(whatToDoNext)"
    }
}

/// Wraps anything that is *not* a domain rule — a failed write, an unreachable
/// container — so the UI still has something humane to show while the technical
/// detail goes to the log rather than the screen.
struct UnexpectedFailure: TenantFacingError {

    /// The technical error, for logging only. Never rendered.
    let underlying: Error
    /// What the tenant was trying to do, in their words, e.g. "saving this room".
    let whileDoing: String

    var title: String { "Something went wrong" }

    var whatHappened: String {
        "MoveProof couldn't finish \(whileDoing)."
    }

    var whatToDoNext: String {
        "Your other records are safe. Try again, and if it keeps happening, close and reopen MoveProof."
    }
}
