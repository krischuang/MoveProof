import XCTest
@testable import MoveProof

/// Checks the promise `TenantFacingError` makes: every error a tenant can hit says
/// what went wrong and what to do about it.
///
/// This started as the same loop copied into three different use case test files.
/// Pulling it into one place covers all eight error types instead of three, and
/// means a new error case only has to be added to one list. The list includes the
/// cases a use case raises when a write will not complete, because those are the ones
/// most likely to be left reading like a developer wrote them.
@MainActor
final class TenantFacingErrorTests: XCTestCase {

    /// One of every case across every domain error type. Associated values are
    /// filled with realistic samples so the interpolated wording is exercised too.
    private let allDomainErrors: [TenantFacingError] = [
        TenancySetupError.missingPropertyAddress,
        TenancySetupError.moveInDateTooFarInPast(days: 120),
        TenancySetupError.conditionReportDueBeforeMoveIn,
        TenancySetupError.inspectionAlreadyStarted(existingAddress: "12 Smith Street"),
        TenancySetupError.tenancyNoLongerBeingDocumented,

        ConditionRecordingError.conditionItemNotFound,
        ConditionRecordingError.inspectionAreaNotFound,
        ConditionRecordingError.damagedConditionNeedsSupportingDetail(itemTitle: "Flooring"),
        ConditionRecordingError.conditionStateNotChosen,
        ConditionRecordingError.evidenceBelongsToAnotherTenancy,

        InspectionCompletionError.inspectionAreaNotFound,
        InspectionCompletionError.uncheckedConditionItemsRemain(count: 2, firstItemTitle: "Windows"),
        InspectionCompletionError.undocumentedDamageRemains(count: 1),
        InspectionCompletionError.inspectionAlreadyComplete(areaName: "Kitchen"),

        InspectionAreaEditError.noActiveTenancy,
        InspectionAreaEditError.inspectionAreaNotFound,
        InspectionAreaEditError.roomNameMissing,
        InspectionAreaEditError.duplicateRoomName(name: "Kitchen"),
        InspectionAreaEditError.roomNotSignedOff(roomName: "Kitchen"),
        InspectionAreaEditError.couldNotRemoveRoom,

        EvidenceCaptureError.noActiveTenancy,
        EvidenceCaptureError.emptyPhoto(displayName: "photo.jpg"),
        EvidenceCaptureError.conditionItemNoLongerInWalkthrough,
        EvidenceCaptureError.evidenceBelongsToAnotherProperty,
        EvidenceCaptureError.couldNotStorePhoto(displayName: "photo.jpg"),

        EvidenceFilingError.evidenceNoLongerInLibrary,
        EvidenceFilingError.conditionItemNoLongerInWalkthrough,
        EvidenceFilingError.conditionItemBelongsToAnotherProperty,
        EvidenceFilingError.couldNotDiscardEvidence,

        SharedEvidenceImportError.noActiveTenancy,
        SharedEvidenceImportError.unsupportedSharedContent(contentTypeIdentifier: "public.movie"),
        SharedEvidenceImportError.sharedItemUnavailable(displayName: "report.pdf"),
        SharedEvidenceImportError.duplicateEvidence(displayName: "report.pdf"),
        SharedEvidenceImportError.inboxUnavailable,
        SharedEvidenceImportError.couldNotFileSharedItem(displayName: "report.pdf"),

        InspectionReviewError.noActiveTenancy
    ]

    func testEveryDomainErrorSaysWhatHappenedAndWhatToDoNext() {
        for error in allDomainErrors {
            XCTAssertFalse(error.title.isEmpty, "Missing title on \(error)")
            XCTAssertFalse(error.whatHappened.isEmpty, "Missing whatHappened on \(error)")
            XCTAssertFalse(error.whatToDoNext.isEmpty, "Missing whatToDoNext on \(error)")
        }
    }

    /// The rubric asks for messages a renter can act on, so the generic developer
    /// phrasings are the ones to keep out.
    func testNoDomainErrorFallsBackToGenericDeveloperWording() {
        let banned = ["save failed", "invalid input", "database error", "unknown error", "operation failed"]

        for error in allDomainErrors {
            let text = "\(error.title) \(error.whatHappened) \(error.whatToDoNext)".lowercased()
            for phrase in banned {
                XCTAssertFalse(text.contains(phrase), "\(error) uses the generic phrase \"\(phrase)\"")
            }
        }
    }

    /// A technical failure still has to reach the tenant as something readable, with
    /// the underlying error kept for the log only.
    func testAnUnexpectedFailureStillReadsAsSomethingATenantCanActOn() {
        let failure = UnexpectedFailure(
            underlying: RepositoryError.saveFailed(underlying: CocoaError(.fileWriteUnknown)),
            whileDoing: "signing off this room"
        )

        XCTAssertTrue(failure.whatHappened.contains("signing off this room"))
        XCTAssertFalse(failure.whatToDoNext.isEmpty)
        XCTAssertFalse(failure.whatHappened.lowercased().contains("cocoa"))
        XCTAssertFalse(failure.whatHappened.lowercased().contains("nserror"))
    }
}
