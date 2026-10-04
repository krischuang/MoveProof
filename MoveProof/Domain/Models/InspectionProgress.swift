import Foundation

/// A computed view of how far the tenant has got. Produced by
/// `ReviewInspectionProgressUseCase`, consumed by the dashboard and, in reduced
/// form, by the widget.
struct InspectionProgress: Equatable {

    let areasTotal: Int
    let areasComplete: Int
    let requiredItemsTotal: Int
    let requiredItemsReviewed: Int
    /// Condition items recorded as damaged or not working with neither a note nor a photo.
    let undocumentedDamageCount: Int
    /// Areas containing at least one undocumented damage record.
    let areasNeedingAttention: [InspectionArea]
    let evidenceCount: Int
    let pendingSharedEvidenceCount: Int
    let daysUntilConditionReportDue: Int?

    var areaCompletionFraction: Double {
        guard areasTotal > 0 else { return 0 }
        return Double(areasComplete) / Double(areasTotal)
    }

    var itemCompletionFraction: Double {
        guard requiredItemsTotal > 0 else { return 0 }
        return Double(requiredItemsReviewed) / Double(requiredItemsTotal)
    }

    var isReportReady: Bool {
        areasTotal > 0 && areasComplete == areasTotal && undocumentedDamageCount == 0
    }

    /// How urgent the deadline is, used to pick wording and colour on the dashboard.
    var deadlineUrgency: DeadlineUrgency {
        guard let days = daysUntilConditionReportDue else { return .notSet }
        if days < 0 { return .overdue }
        if days <= 2 { return .dueSoon }
        return .comfortable
    }

    enum DeadlineUrgency {
        case notSet, comfortable, dueSoon, overdue
    }

    /// The privacy-reduced form published to the App Group for the widget.
    /// Address, notes and photographs are left out on purpose.
    func snapshot(generatedAt: Date) -> InspectionSnapshot {
        InspectionSnapshot(
            areasTotal: areasTotal,
            areasComplete: areasComplete,
            areasNeedingAttention: areasNeedingAttention.count,
            evidenceCount: evidenceCount,
            pendingInboxCount: pendingSharedEvidenceCount,
            daysUntilConditionReportDue: daysUntilConditionReportDue,
            generatedAt: generatedAt,
            hasActiveTenancy: true
        )
    }
}
