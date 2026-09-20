import Foundation

/// Stores evidence binaries in the App Group container rather than in Core Data.
///
/// Photographs are large and a tenant may file dozens of them. Keeping the bytes
/// on the file system keeps the SQLite store small and lets iOS manage the files,
/// while Core Data holds only the metadata and the relative file name. Because the
/// directory lives in the App Group, a file handed over by the Share Extension can
/// be adopted without copying it out of the sandbox and back in.
struct AppGroupEvidenceFileStore: EvidenceFileStore {

    init() {}

    func adopt(fileAt sourceURL: URL, preferredExtension: String) throws -> String {
        let storedFileName = makeFileName(extension: preferredExtension)
        let destination = try AppGroup.directoryURL(.evidence)
            .appendingPathComponent(storedFileName)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        // Copy rather than move: the inbox record is removed separately, only once
        // the domain import has actually succeeded.
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return storedFileName
    }

    func store(data: Data, preferredExtension: String) throws -> String {
        let storedFileName = makeFileName(extension: preferredExtension)
        let destination = try AppGroup.directoryURL(.evidence)
            .appendingPathComponent(storedFileName)
        try data.write(to: destination, options: .atomic)
        return storedFileName
    }

    func url(forStoredFileName storedFileName: String) throws -> URL {
        try AppGroup.directoryURL(.evidence).appendingPathComponent(storedFileName)
    }

    func removeFile(named storedFileName: String) throws {
        let url = try url(forStoredFileName: storedFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func fileExists(named storedFileName: String) -> Bool {
        guard let url = try? url(forStoredFileName: storedFileName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func makeFileName(extension fileExtension: String) -> String {
        let id = UUID().uuidString
        return fileExtension.isEmpty ? id : "\(id).\(fileExtension)"
    }
}
