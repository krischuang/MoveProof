import Foundation
import UniformTypeIdentifiers

/// Pulls the files out of a share sheet invocation and writes them into the App
/// Group inbox.
///
/// This is the whole of the Share Extension's logic, and it is deliberately dull.
/// It does not know what a tenancy is, whether MoveProof can use a PDF, or whether
/// this file has been shared before. It records what it was handed — the bytes, the
/// name, the type identifier — and stops. `ImportSharedEvidenceUseCase` in the main
/// app makes every one of those decisions.
///
/// Keeping it this thin matters for two reasons. A share extension is killed
/// quickly if it uses much memory, and duplicating the import rules here would mean
/// two copies of them to keep in step.
///
/// It lives in `MoveProofShared` rather than inside the extension target so the app
/// target compiles it as well. A share extension cannot be launched from a test, but
/// this type can — which is how `SharedItemCollectorTests` exercises the real
/// attachment handling against real `NSItemProvider`s.
///
/// Deliberately a value type: the attachments are inspected once at init and the
/// outcome is returned rather than mutated in place, so the confirmation view owns
/// the state and this type owns none.
struct SharedItemCollector {

    enum Outcome: Equatable {
        case preparing
        /// Files were found and can be handed over.
        case ready(candidates: [Candidate])
        case saved(count: Int)
        /// Nothing in the share sheet was a file MoveProof could store.
        case nothingUsable
        case failed(reason: String)
    }

    /// One attachment the extension is prepared to copy.
    struct Candidate: Identifiable, Equatable {
        let id = UUID()
        let displayName: String
        let typeIdentifier: String

        static func == (lhs: Candidate, rhs: Candidate) -> Bool { lhs.id == rhs.id }
    }

    /// Type identifiers the extension is willing to carry. Kept broad and purely
    /// structural — the main app decides what is actually usable as evidence.
    private static let acceptedTypes: [UTType] = [.image, .pdf]

    private let providers: [NSItemProvider]

    /// Inspects the share sheet's attachments without copying anything yet.
    init(inputItems: [Any]) {
        providers = inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
            .filter { provider in
                Self.acceptedTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
            }
    }

    /// What the tenant should see before deciding to save.
    var initialOutcome: Outcome {
        guard !providers.isEmpty else { return .nothingUsable }
        return .ready(candidates: providers.map { provider in
            let typeIdentifier = Self.bestTypeIdentifier(for: provider) ?? "public.data"
            return Candidate(
                displayName: Self.displayName(for: provider, typeIdentifier: typeIdentifier),
                typeIdentifier: typeIdentifier
            )
        })
    }

    /// A name the tenant will recognise later in their evidence library.
    ///
    /// Photos hands over attachments with no suggested name at all, so falling back
    /// to a bare "Shared file" would leave a library full of identical rows. Naming
    /// it by kind and date at least tells the tenant what it is and when it arrived.
    static func displayName(
        for provider: NSItemProvider,
        typeIdentifier: String,
        receivedAt: Date = Date()
    ) -> String {
        if let suggested = provider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !suggested.isEmpty {
            return suggested
        }
        let kind = UTType(typeIdentifier)?.conforms(to: .pdf) == true ? "Document" : "Photo"
        return "\(kind) shared \(receivedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    /// Copies every accepted attachment into the App Group inbox.
    ///
    /// - Returns: what to tell the tenant. Nothing is mutated here.
    func save() async -> Outcome {
        let inbox = SharedEvidenceInbox()
        var savedCount = 0

        for provider in providers {
            guard let typeIdentifier = Self.bestTypeIdentifier(for: provider) else { continue }
            let displayName = Self.displayName(for: provider, typeIdentifier: typeIdentifier)

            do {
                if let url = await Self.loadFile(from: provider, typeIdentifier: typeIdentifier) {
                    try inbox.store(
                        fileAt: url,
                        originalFileName: displayName,
                        contentTypeIdentifier: typeIdentifier,
                        sourceApplication: Self.hostApplicationIdentifier
                    )
                    savedCount += 1
                } else if let data = await Self.loadData(from: provider, typeIdentifier: typeIdentifier) {
                    try inbox.store(
                        data: data,
                        originalFileName: displayName,
                        contentTypeIdentifier: typeIdentifier,
                        fileExtension: UTType(typeIdentifier)?.preferredFilenameExtension ?? "",
                        sourceApplication: Self.hostApplicationIdentifier
                    )
                    savedCount += 1
                }
            } catch AppGroupAccessError.containerUnavailable {
                return .failed(
                    reason: "MoveProof can't reach its shared storage on this device, so the file wasn't saved."
                )
            } catch {
                // One bad attachment should not lose the others.
                continue
            }
        }

        return savedCount > 0
            ? .saved(count: savedCount)
            : .failed(reason: "MoveProof couldn't read the file that was shared. Try sharing it again from the app it's stored in.")
    }

    // MARK: - Loading

    /// Picks the most specific accepted type the provider offers, so a JPEG is
    /// recorded as `public.jpeg` rather than the generic `public.image`.
    private static func bestTypeIdentifier(for provider: NSItemProvider) -> String? {
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            return UTType.pdf.identifier
        }
        let concreteImageTypes = provider.registeredTypeIdentifiers.filter { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .image) && type != .image
        }
        if let concrete = concreteImageTypes.first {
            return concrete
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return UTType.image.identifier
        }
        return nil
    }

    /// `loadFileRepresentation` hands back a URL that is only valid inside the
    /// completion block, so the inbox copy has to happen before this returns.
    private static func loadFile(from provider: NSItemProvider, typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                // Copy into the extension's own temporary directory first: the
                // provider deletes its copy as soon as this block returns.
                let staged = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                do {
                    try FileManager.default.copyItem(at: url, to: staged)
                    continuation.resume(returning: staged)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadData(from provider: NSItemProvider, typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// iOS does not expose the host application to a share extension, so provenance
    /// is recorded as unknown rather than guessed. The field exists because the main
    /// app shows it when it is available — for example for evidence added in-app.
    private static var hostApplicationIdentifier: String? { nil }
}
