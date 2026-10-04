import Foundation

/// Single source of truth for the App Group container shared by the main app,
/// the Share Extension and the Widget Extension.
///
/// The three processes never talk to each other directly. They cooperate through
/// two clearly separated directories inside one shared container:
///
///     group.com.krischuang.MoveProof/
///       Evidence/              app-controlled evidence files (written by the main app only)
///       SharedEvidenceInbox/   hand-off inbox (written by the Share Extension, drained by the main app)
///       Widget/snapshot.json   read-only summary published by the main app for the widget
///
/// Keeping the identifier and the directory names in one file means a typo cannot
/// quietly split the app and its extensions into two different containers.
enum AppGroup {

    /// Must match the App Group capability enabled on all three targets.
    static let identifier = "group.com.krischuang.MoveProof"

    /// Root of the shared container, or `nil` when the App Group entitlement is
    /// missing or not yet provisioned for this build.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    enum Directory: String {
        /// Evidence files the main app has taken ownership of.
        case evidence = "Evidence"
        /// Files handed over by the Share Extension, awaiting domain-level import.
        case sharedEvidenceInbox = "SharedEvidenceInbox"
        /// Widget-facing snapshot published by the main app.
        case widget = "Widget"
    }

    /// Returns the URL for a shared sub-directory, creating it if required.
    ///
    /// - Throws: `AppGroupAccessError.containerUnavailable` when the entitlement is
    ///   not present, or the underlying `FileManager` error if the directory cannot
    ///   be created.
    static func directoryURL(_ directory: Directory) throws -> URL {
        guard let containerURL else { throw AppGroupAccessError.containerUnavailable }
        let url = containerURL.appendingPathComponent(directory.rawValue, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
}

/// Raised when shared storage cannot be reached. This is a technical fault, not a
/// domain rule, so it is kept out of the domain error files.
enum AppGroupAccessError: Error {
    case containerUnavailable
}
