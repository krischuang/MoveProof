import Foundation

// MARK: - Starting a tenancy

/// Rules enforced by `StartTenancyInspectionUseCase`.
enum TenancySetupError: TenantFacingError, Equatable {

    case missingPropertyAddress
    case moveInDateTooFarInPast(days: Int)
    case conditionReportDueBeforeMoveIn
    case inspectionAlreadyStarted(existingAddress: String)

    var title: String {
        switch self {
        case .inspectionAlreadyStarted: "You're already documenting a property"
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
        }
    }

    /// A move-in date more than this far in the past is almost certainly a typo
    /// rather than a real tenancy start, so MoveProof asks the tenant to confirm.
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
            "Pick the condition you found — undamaged, minor wear, damaged or not working."
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
            "\"\(displayName)\" is no longer available — the file may have been removed since it was shared."
        case .duplicateEvidence(let displayName):
            "\"\(displayName)\" has already been filed against this property."
        case .inboxUnavailable:
            "MoveProof couldn't reach the storage it shares with the share sheet."
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
            "You can safely remove this copy from the inbox — the original is in your evidence library."
        case .inboxUnavailable:
            "Close and reopen MoveProof. If the inbox stays empty, share the file again."
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
