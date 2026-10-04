import Foundation

/// A photograph or document the tenant has filed as proof of a property's condition.
///
/// The file itself lives in app-controlled storage inside the App Group container.
/// Core Data holds only this metadata and the relative file name, so the store stays
/// small and the binaries stay on the file system where iOS can manage them.
struct EvidenceItem: Identifiable, Equatable, Hashable {

    let id: UUID
    var kind: EvidenceKind
    /// File name relative to the shared `Evidence/` directory, never an absolute path,
    /// because container paths change between installs.
    var storedFileName: String
    /// Name to show the tenant, e.g. the original file name from a shared PDF.
    var displayName: String
    var capturedAt: Date
    var notes: String
    var source: EvidenceSource
    /// The condition item this backs up, when the tenant has assigned it.
    /// Evidence can exist at tenancy level before it is filed against a room.
    var conditionItemID: UUID?
    let tenancyID: UUID
    /// Identifier of the Share Extension inbox record this came from, used to make
    /// import idempotent. `nil` for evidence captured inside the app.
    var importedInboxItemID: UUID?

    init(
        id: UUID = UUID(),
        kind: EvidenceKind,
        storedFileName: String,
        displayName: String,
        capturedAt: Date = Date(),
        notes: String = "",
        source: EvidenceSource,
        conditionItemID: UUID? = nil,
        tenancyID: UUID,
        importedInboxItemID: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.storedFileName = storedFileName
        self.displayName = displayName
        self.capturedAt = capturedAt
        self.notes = notes
        self.source = source
        self.conditionItemID = conditionItemID
        self.tenancyID = tenancyID
        self.importedInboxItemID = importedInboxItemID
    }
}

/// What kind of file the evidence is. MoveProof supports the two formats tenants
/// actually receive: photographs, and PDF paperwork such as a signed condition report.
enum EvidenceKind: String, CaseIterable, Equatable, Hashable {

    case photograph
    case document

    var label: String {
        switch self {
        case .photograph: "Photo"
        case .document: "Document"
        }
    }

    var symbolName: String {
        switch self {
        case .photograph: "photo"
        case .document: "doc.text"
        }
    }

    /// Maps a Uniform Type Identifier reported by another app to a MoveProof
    /// evidence kind. Returns `nil` for anything MoveProof cannot file as evidence,
    /// which `ImportSharedEvidenceUseCase` turns into a domain error.
    static func forContentType(_ identifier: String) -> EvidenceKind? {
        switch identifier {
        case "public.jpeg", "public.png", "public.heic", "public.heif",
             "public.image", "public.tiff":
            .photograph
        case "com.adobe.pdf":
            .document
        default:
            nil
        }
    }
}

/// How a piece of evidence entered MoveProof. Recorded because provenance matters
/// when the tenant later explains where a file came from.
enum EvidenceSource: String, CaseIterable, Equatable, Hashable {

    /// Chosen from the photo library inside MoveProof.
    case capturedInApp
    /// Sent to MoveProof through the iOS share sheet.
    case sharedFromAnotherApp

    var label: String {
        switch self {
        case .capturedInApp: "Added in MoveProof"
        case .sharedFromAnotherApp: "Shared from another app"
        }
    }
}
