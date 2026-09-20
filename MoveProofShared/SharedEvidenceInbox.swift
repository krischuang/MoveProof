import Foundation

/// Metadata the Share Extension records alongside each file it hands over.
///
/// Note what is *absent*: there is no tenancy, no inspection area, no condition
/// item and no evidence classification. The Share Extension deliberately knows
/// nothing about the domain — it captures the file plus enough provenance for the
/// main app to make those decisions later, inside `ImportSharedEvidenceUseCase`.
struct PendingSharedEvidence: Codable, Equatable, Identifiable, Sendable {

    /// Identifies both this record and the file it describes.
    let id: UUID
    /// File name inside the inbox directory, e.g. `"<uuid>.pdf"`.
    let storedFileName: String
    /// Name the file had in the host app, shown to the tenant so they can recognise it.
    let originalFileName: String
    /// Uniform Type Identifier reported by the host app, e.g. `"public.jpeg"`.
    let contentTypeIdentifier: String
    /// Bundle identifier of the app the tenant shared from, when available.
    let sourceApplication: String?
    /// When the Share Extension wrote this record.
    let receivedAt: Date
    /// Size on disk in bytes, used to show the tenant what they are importing.
    let byteCount: Int

    init(
        id: UUID,
        storedFileName: String,
        originalFileName: String,
        contentTypeIdentifier: String,
        sourceApplication: String?,
        receivedAt: Date,
        byteCount: Int
    ) {
        self.id = id
        self.storedFileName = storedFileName
        self.originalFileName = originalFileName
        self.contentTypeIdentifier = contentTypeIdentifier
        self.sourceApplication = sourceApplication
        self.receivedAt = receivedAt
        self.byteCount = byteCount
    }
}

/// The hand-off point between the Share Extension and the main app.
///
/// The extension only ever calls `store(fileAt:...)`. The main app calls
/// `pendingItems()`, `fileURL(for:)` and `remove(_:)` while running the domain
/// import. Neither side needs to know how the other works.
struct SharedEvidenceInbox {

    private let metadataExtension = "json"

    init() {}

    private func inboxURL() throws -> URL {
        try AppGroup.directoryURL(.sharedEvidenceInbox)
    }

    private func metadataURL(for id: UUID) throws -> URL {
        try inboxURL().appendingPathComponent("\(id.uuidString).\(metadataExtension)")
    }

    /// URL of the shared file itself.
    func fileURL(for item: PendingSharedEvidence) throws -> URL {
        try inboxURL().appendingPathComponent(item.storedFileName)
    }

    // MARK: - Writing (Share Extension side)

    /// Copies a shared file into the inbox and writes its metadata sidecar.
    ///
    /// - Returns: the record written, so the extension can report what it captured.
    @discardableResult
    func store(
        fileAt sourceURL: URL,
        originalFileName: String,
        contentTypeIdentifier: String,
        sourceApplication: String?,
        receivedAt: Date = Date()
    ) throws -> PendingSharedEvidence {
        let id = UUID()
        let fileExtension = sourceURL.pathExtension.isEmpty
            ? (URL(fileURLWithPath: originalFileName).pathExtension)
            : sourceURL.pathExtension
        let storedFileName = fileExtension.isEmpty
            ? id.uuidString
            : "\(id.uuidString).\(fileExtension)"

        let destination = try inboxURL().appendingPathComponent(storedFileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
        let byteCount = (attributes?[.size] as? NSNumber)?.intValue ?? 0

        let record = PendingSharedEvidence(
            id: id,
            storedFileName: storedFileName,
            originalFileName: originalFileName,
            contentTypeIdentifier: contentTypeIdentifier,
            sourceApplication: sourceApplication,
            receivedAt: receivedAt,
            byteCount: byteCount
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(to: try metadataURL(for: id), options: .atomic)
        return record
    }

    /// Writes raw data (used when a host app provides bytes rather than a file URL).
    @discardableResult
    func store(
        data: Data,
        originalFileName: String,
        contentTypeIdentifier: String,
        fileExtension: String,
        sourceApplication: String?,
        receivedAt: Date = Date()
    ) throws -> PendingSharedEvidence {
        let id = UUID()
        let storedFileName = fileExtension.isEmpty
            ? id.uuidString
            : "\(id.uuidString).\(fileExtension)"
        let destination = try inboxURL().appendingPathComponent(storedFileName)
        try data.write(to: destination, options: .atomic)

        let record = PendingSharedEvidence(
            id: id,
            storedFileName: storedFileName,
            originalFileName: originalFileName,
            contentTypeIdentifier: contentTypeIdentifier,
            sourceApplication: sourceApplication,
            receivedAt: receivedAt,
            byteCount: data.count
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(to: try metadataURL(for: id), options: .atomic)
        return record
    }

    // MARK: - Reading and draining (main app side)

    /// All items awaiting import, oldest first.
    ///
    /// A metadata file whose companion payload is missing is skipped rather than
    /// thrown on, so one corrupt hand-off cannot block the whole inbox.
    func pendingItems() throws -> [PendingSharedEvidence] {
        let inbox = try inboxURL()
        let contents = try FileManager.default.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: nil
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return contents
            .filter { $0.pathExtension == metadataExtension }
            .compactMap { url -> PendingSharedEvidence? in
                guard let data = try? Data(contentsOf: url),
                      let record = try? decoder.decode(PendingSharedEvidence.self, from: data)
                else { return nil }
                let payload = inbox.appendingPathComponent(record.storedFileName)
                guard FileManager.default.fileExists(atPath: payload.path) else { return nil }
                return record
            }
            .sorted { $0.receivedAt < $1.receivedAt }
    }

    /// Number of items waiting, used for the dashboard badge and widget snapshot.
    func pendingCount() -> Int {
        (try? pendingItems().count) ?? 0
    }

    /// Removes an item and its metadata once the main app has imported or discarded it.
    func remove(_ item: PendingSharedEvidence) throws {
        let payload = try fileURL(for: item)
        if FileManager.default.fileExists(atPath: payload.path) {
            try FileManager.default.removeItem(at: payload)
        }
        let metadata = try metadataURL(for: item.id)
        if FileManager.default.fileExists(atPath: metadata.path) {
            try FileManager.default.removeItem(at: metadata)
        }
    }
}
