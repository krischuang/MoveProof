import Foundation

// MARK: - Starting a tenancy

/// Rules enforced by `StartTenancyInspectionUseCase`.
enum TenancySetupError: TenantFacingError, Equatable {

    case missingPropertyAddress
    case moveInDateTooFarInPast(days: Int)
    case conditionReportDueBeforeMoveIn
    case inspectionAlreadyStarted(existingAddress: String)
    /// Raised by `UpdateTenancyDetailsUseCase` when the tenancy being corrected is
    /// no longer the one MoveProof is documenting, e.g. it was archived on another
    /// screen while this form was open.
    case tenancyNoLongerBeingDocumented

    var title: String {
        switch self {
        case .inspectionAlreadyStarted: "You're already documenting a property"
        case .tenancyNoLongerBeingDocumented: "This property isn't open any more"
        default: "Check these details"
        }
    }

    var whatHappened: String {
        switch self {
        case .missingPropertyAddress:
            "MoveProof needs the property address before it can start a walkthrough."
        case .moveInDateTooFarInPast(let days):
            "The move-in date you entered is \(days) days ago."
        case .conditionReportDueBeforeMoveIn:
            "The condition report due date is earlier than the move-in date."
        case .inspectionAlreadyStarted(let existingAddress):
            "You're already documenting \(existingAddress)."
        case .tenancyNoLongerBeingDocumented:
            "The property you were editing is no longer the one MoveProof is documenting."
        }
    }

    var whatToDoNext: String {
        switch self {
        case .missingPropertyAddress:
            "Enter the address exactly as it appears on your tenancy agreement, so your evidence is easy to match to the right property later."
        case .moveInDateTooFarInPast:
            "Condition reports cover the start of a tenancy. Check the date, or archive this tenancy and start a new one if you've moved again."
        case .conditionReportDueBeforeMoveIn:
            "Set the due date on or after the day you move in. MoveProof suggests seven days after move-in."
        case .inspectionAlreadyStarted:
            "Finish or archive that walkthrough before starting a new property."
        case .tenancyNoLongerBeingDocumented:
            "Close this form and open your property details again from the Walkthrough tab."
        }
    }

    /// A move-in date more than this far in the past is more likely a typo than a real
    /// tenancy start, so MoveProof asks the tenant to confirm.
    static let maximumBackdatedMoveInDays = 90
}

// MARK: - Recording a condition

/// Rules enforced by `RecordConditionEvidenceUseCase`.
enum ConditionRecordingError: TenantFacingError, Equatable {

    case conditionItemNotFound
    case inspectionAreaNotFound
    case damagedConditionNeedsSupportingDetail(itemTitle: String)
    case conditionStateNotChosen
    case evidenceBelongsToAnotherTenancy

    var title: String {
        switch self {
        case .damagedConditionNeedsSupportingDetail: "This damage needs backing up"
        default: "Can't save this yet"
        }
    }

    var whatHappened: String {
        switch self {
        case .conditionItemNotFound:
            "That checklist item is no longer part of this walkthrough."
        case .inspectionAreaNotFound:
            "That room is no longer part of this walkthrough."
        case .damagedConditionNeedsSupportingDetail(let itemTitle):
            "You've marked \"\(itemTitle)\" as damaged, but there's nothing recorded to show what you saw."
        case .conditionStateNotChosen:
            "No condition was selected for this item."
        case .evidenceBelongsToAnotherTenancy:
            "That evidence file belongs to a different property."
        }
    }

    var whatToDoNext: String {
        switch self {
        case .conditionItemNotFound, .inspectionAreaNotFound:
            "Go back to the room list and reopen the room to see the current checklist."
        case .damagedConditionNeedsSupportingDetail:
            "Add a photo or write a short note describing the damage, so you can identify it again at the end of the tenancy."
        case .conditionStateNotChosen:
            "Pick the condition you found: undamaged, minor wear, damaged or not working."
        case .evidenceBelongsToAnotherTenancy:
            "Open the evidence library for this property and pick a file filed against it."
        }
    }
}

// MARK: - Signing off a room

/// Rules enforced by `CompleteInspectionAreaUseCase`.
enum InspectionCompletionError: TenantFacingError, Equatable {

    case inspectionAreaNotFound
    case uncheckedConditionItemsRemain(count: Int, firstItemTitle: String)
    case undocumentedDamageRemains(count: Int)
    case inspectionAlreadyComplete(areaName: String)

    var title: String {
        switch self {
        case .inspectionAlreadyComplete: "Already reviewed"
        default: "This room isn't ready yet"
        }
    }

    var whatHappened: String {
        switch self {
        case .inspectionAreaNotFound:
            "That room is no longer part of this walkthrough."
        case .uncheckedConditionItemsRemain(let count, let firstItemTitle):
            count == 1
                ? "\"\(firstItemTitle)\" still hasn't been reviewed."
                : "\(count) checklist items in this room still haven't been reviewed, starting with \"\(firstItemTitle)\"."
        case .undocumentedDamageRemains(let count):
            count == 1
                ? "One damaged item in this room has no photo or note."
                : "\(count) damaged items in this room have no photo or note."
        case .inspectionAlreadyComplete(let areaName):
            "You've already signed off \(areaName)."
        }
    }

    var whatToDoNext: String {
        switch self {
        case .inspectionAreaNotFound:
            "Go back to the room list to see the rooms in this walkthrough."
        case .uncheckedConditionItemsRemain:
            "Record what you found for each remaining item, then sign the room off."
        case .undocumentedDamageRemains:
            "Open each damaged item and add a photo or a short note before signing off."
        case .inspectionAlreadyComplete:
            "Reopen the room if you need to change something you recorded."
        }
    }
}

// MARK: - Importing shared evidence

/// Rules enforced by `ImportSharedEvidenceUseCase`.
enum SharedEvidenceImportError: TenantFacingError, Equatable {

    case noActiveTenancy
    case unsupportedSharedContent(contentTypeIdentifier: String)
    case sharedItemUnavailable(displayName: String)
    case duplicateEvidence(displayName: String)
    case inboxUnavailable
    /// The shared item could not be filed, so it stays in the inbox to try again.
    case couldNotFileSharedItem(displayName: String)

    var title: String {
        switch self {
        case .noActiveTenancy: "No property to file this against"
        case .duplicateEvidence: "Already in your evidence"
        default: "Couldn't import this"
        }
    }

    var whatHappened: String {
        switch self {
        case .noActiveTenancy:
            "There's no property set up in MoveProof yet, so there's nowhere to file this evidence."
        case .unsupportedSharedContent(let contentTypeIdentifier):
            "MoveProof can file photos and PDFs. This item is a \(Self.readableType(contentTypeIdentifier))."
        case .sharedItemUnavailable(let displayName):
            "\"\(displayName)\" is no longer available. The file may have been removed since it was shared."
        case .duplicateEvidence(let displayName):
            "\"\(displayName)\" has already been filed against this property."
        case .inboxUnavailable:
            "MoveProof couldn't reach the storage it shares with the share sheet."
        case .couldNotFileSharedItem(let displayName):
            "MoveProof couldn't save \"\(displayName)\" into your evidence, so it hasn't been filed."
        }
    }

    var whatToDoNext: String {
        switch self {
        case .noActiveTenancy:
            "Set up your property first, then come back to the shared items inbox to file this."
        case .unsupportedSharedContent:
            "Take a screenshot or export it as a PDF, then share that to MoveProof instead."
        case .sharedItemUnavailable:
            "Remove it from the inbox and share the file to MoveProof again."
        case .duplicateEvidence:
            "You can safely remove this copy from the inbox. The original is in your evidence library."
        case .inboxUnavailable:
            "Close and reopen MoveProof. If the inbox stays empty, share the file again."
        case .couldNotFileSharedItem:
            "It's still waiting in your shared items. Check there's free space on your device, then import it again."
        }
    }

    /// Turns a Uniform Type Identifier into something a tenant can read.
    private static func readableType(_ identifier: String) -> String {
        if identifier.hasPrefix("public.movie") || identifier.hasPrefix("public.video") {
            return "video"
        }
        if identifier.hasPrefix("public.audio") { return "sound file" }
        if identifier.hasPrefix("public.url") || identifier.hasPrefix("public.plain-text") {
            return "link or piece of text"
        }
        return "file type MoveProof doesn't handle"
    }
}

// MARK: - Editing the rooms in a walkthrough

/// Rules enforced by `AddInspectionAreaUseCase`, `RenameInspectionAreaUseCase`,
/// `RemoveInspectionAreaUseCase` and `ReopenInspectionAreaUseCase`.
///
/// The four use cases share one error type because they are four edits to the same
/// thing, the list of rooms in the walkthrough, and a tenant reads them in the same
/// place on the same screens.
enum InspectionAreaEditError: TenantFacingError, Equatable {

    case noActiveTenancy
    case inspectionAreaNotFound
    case roomNameMissing
    case duplicateRoomName(name: String)
    case roomNotSignedOff(roomName: String)
    /// The removal itself did not complete, so the walkthrough is unchanged.
    case couldNotRemoveRoom

    var title: String {
        switch self {
        case .noActiveTenancy: "No property to add rooms to"
        case .duplicateRoomName: "You already have a room with that name"
        case .couldNotRemoveRoom: "Couldn't remove that room"
        default: "Can't change this room"
        }
    }

    var whatHappened: String {
        switch self {
        case .noActiveTenancy:
            "There's no property set up in MoveProof yet, so there's no walkthrough to add a room to."
        case .inspectionAreaNotFound:
            "That room is no longer part of this walkthrough."
        case .roomNameMissing:
            "A room needs a name before MoveProof can add it to your walkthrough."
        case .duplicateRoomName(let name):
            "This walkthrough already has a room called \"\(name)\"."
        case .roomNotSignedOff(let roomName):
            "\"\(roomName)\" hasn't been signed off, so there's nothing to reopen."
        case .couldNotRemoveRoom:
            "MoveProof couldn't remove that room, so your walkthrough is unchanged."
        }
    }

    var whatToDoNext: String {
        switch self {
        case .noActiveTenancy:
            "Add the property you've moved into on the Walkthrough tab first."
        case .inspectionAreaNotFound:
            "Go back to the room list to see the rooms in this walkthrough."
        case .roomNameMissing:
            "Give the room the name you'd use when describing it to your agent, such as \"Study\" or \"Garage\"."
        case .duplicateRoomName:
            "Give this one a name that tells them apart, such as \"Second bathroom\", so your evidence stays easy to match to the right room."
        case .roomNotSignedOff:
            "You can keep recording in it as it is."
        case .couldNotRemoveRoom:
            "Nothing was lost. Try again, and if it keeps happening, close and reopen MoveProof."
        }
    }
}

// MARK: - Capturing evidence inside the app

/// Rules enforced by `CaptureEvidenceUseCase`.
///
/// Deliberately separate from `SharedEvidenceImportError`: a photo the tenant picks
/// inside MoveProof fails for different reasons than a file another app hands over,
/// and telling someone their own camera roll photo "may have been removed since it
/// was shared" would be nonsense. Infrastructure faults underneath, such as a full
/// disk, are mapped onto `couldNotStorePhoto` here rather than leaking to the screen.
enum EvidenceCaptureError: TenantFacingError, Equatable {

    case noActiveTenancy
    case emptyPhoto(displayName: String)
    case conditionItemNoLongerInWalkthrough
    case evidenceBelongsToAnotherProperty
    case couldNotStorePhoto(displayName: String)

    var title: String {
        switch self {
        case .noActiveTenancy: "No property to file this against"
        case .couldNotStorePhoto: "Couldn't keep that photo"
        default: "Couldn't add that photo"
        }
    }

    var whatHappened: String {
        switch self {
        case .noActiveTenancy:
            "There's no property set up in MoveProof yet, so there's nowhere to file this photo."
        case .emptyPhoto(let displayName):
            "\"\(displayName)\" came through empty, so there's no image to keep as evidence."
        case .conditionItemNoLongerInWalkthrough:
            "The checklist item you're adding this photo to is no longer part of this walkthrough."
        case .evidenceBelongsToAnotherProperty:
            "That checklist item belongs to a different property."
        case .couldNotStorePhoto(let displayName):
            "MoveProof couldn't save \"\(displayName)\" into your evidence, so it hasn't been recorded."
        }
    }

    var whatToDoNext: String {
        switch self {
        case .noActiveTenancy:
            "Add the property you've moved into on the Walkthrough tab, then add this photo again."
        case .emptyPhoto:
            "Pick the photo again, or take a new one of what you want to record."
        case .conditionItemNoLongerInWalkthrough:
            "Go back to the room and open the item again. Your photo hasn't been lost from your camera roll."
        case .evidenceBelongsToAnotherProperty:
            "Open the room list for this property and pick a checklist item from it."
        case .couldNotStorePhoto:
            "Check there's free space on your device, then add the photo again."
        }
    }
}

// MARK: - Managing evidence already in the library

/// Rules enforced by `FileEvidenceUseCase` and `DiscardEvidenceUseCase`: the two
/// things a tenant does with evidence after it is already in MoveProof.
enum EvidenceFilingError: TenantFacingError, Equatable {

    case evidenceNoLongerInLibrary
    case conditionItemNoLongerInWalkthrough
    case conditionItemBelongsToAnotherProperty
    /// The record would not delete, so the evidence is still in the library.
    case couldNotDiscardEvidence

    var title: String {
        switch self {
        case .couldNotDiscardEvidence: "Couldn't discard this evidence"
        default: "Couldn't file this evidence"
        }
    }

    var whatHappened: String {
        switch self {
        case .evidenceNoLongerInLibrary:
            "This photo or document is no longer in your evidence library."
        case .conditionItemNoLongerInWalkthrough:
            "The checklist item you picked is no longer part of this walkthrough."
        case .conditionItemBelongsToAnotherProperty:
            "The checklist item you picked belongs to a different property."
        case .couldNotDiscardEvidence:
            "MoveProof couldn't remove that photo or document, so it's still in your evidence library."
        }
    }

    var whatToDoNext: String {
        switch self {
        case .evidenceNoLongerInLibrary:
            "Go back to your evidence library to see what's still filed against this property."
        case .conditionItemNoLongerInWalkthrough:
            "Go back and pick a checklist item from the current room list."
        case .conditionItemBelongsToAnotherProperty:
            "Pick a checklist item from the property this evidence was filed against."
        case .couldNotDiscardEvidence:
            "Nothing was lost. Try again, and if it keeps happening, close and reopen MoveProof."
        }
    }
}

// MARK: - Reviewing progress

/// Rules enforced by `ReviewInspectionProgressUseCase`.
enum InspectionReviewError: TenantFacingError, Equatable {

    case noActiveTenancy

    var title: String { "Nothing to summarise yet" }

    var whatHappened: String {
        "There's no property being documented in MoveProof right now."
    }

    var whatToDoNext: String {
        "Add the property you've moved into to start a walkthrough."
    }
}
