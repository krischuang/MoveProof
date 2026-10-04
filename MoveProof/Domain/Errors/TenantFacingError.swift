import Foundation

/// Every domain error the tenant can see answers two questions: what went wrong, and
/// what they can do about it.
///
/// Kept separate from `localizedDescription`, which stays technical and goes to the
/// log. A tenant who hits a rule should never see "Save failed".
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
}

/// Wraps anything that is *not* a domain rule, such as a failed write or a container
/// that cannot be reached, so the UI still has something readable to show while the
/// technical detail goes to the log instead of the screen.
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
