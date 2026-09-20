import Foundation

/// Works out how far the tenant has got, and publishes the privacy-reduced version
/// of that to the widget.
///
/// ## Rules enforced
/// 1. There must be a tenancy to summarise.
/// 2. A tenancy is only `reportReady` when every room is signed off **and** no
///    damage is left undocumented. Status is derived from the evidence rather than
///    set by hand, so it cannot drift out of step with what is actually recorded.
/// 3. What reaches the widget is a strict subset of what the dashboard shows:
///    counts, progress and the deadline. Never the address, the notes or the photos.
struct ReviewInspectionProgressUseCase {

    let tenancyRepository: TenancyRepository
    let inspectionRepository: InspectionRepository
    let evidenceRepository: EvidenceRepository
    let inbox: SharedEvidenceInbox
    let snapshotPublisher: InspectionSnapshotPublishing

    init(
        tenancyRepository: TenancyRepository,
        inspectionRepository: InspectionRepository,
        evidenceRepository: EvidenceRepository,
        inbox: SharedEvidenceInbox = SharedEvidenceInbox(),
        snapshotPublisher: InspectionSnapshotPublishing
    ) {
        self.tenancyRepository = tenancyRepository
        self.inspectionRepository = inspectionRepository
        self.evidenceRepository = evidenceRepository
        self.inbox = inbox
        self.snapshotPublisher = snapshotPublisher
    }

    struct Summary: Equatable {
        let tenancy: Tenancy
        let progress: InspectionProgress
    }

    /// - Throws: `InspectionReviewError.noActiveTenancy` when nothing is being documented.
    func execute(now: Date = Date(), calendar: Calendar = .current) throws -> Summary {

        // Rule 1
        guard var tenancy = try tenancyRepository.fetchActiveTenancy() else {
            throw InspectionReviewError.noActiveTenancy
        }

        let areas = try inspectionRepository.fetchAreas(forTenancy: tenancy.id)
        let completeAreas = areas.filter { $0.inspectionStatus == .complete }

        var requiredItemsTotal = 0
        var requiredItemsReviewed = 0
        for area in areas {
            let items = try inspectionRepository.fetchConditionItems(inArea: area.id)
            let required = items.filter(\.isRequired)
            requiredItemsTotal += required.count
            requiredItemsReviewed += required.filter(\.isReviewed).count
        }

        // One predicate query does the work the dashboard would otherwise do by
        // loading every checklist item and filtering in memory.
        let undocumentedDamage = try inspectionRepository
            .fetchConditionItemsMissingSupportingDetail(forTenancy: tenancy.id)

        let areasNeedingAttention = areasContaining(undocumentedDamage, among: areas)
        let evidenceCount = try evidenceRepository.fetchEvidence(forTenancy: tenancy.id).count

        let progress = InspectionProgress(
            areasTotal: areas.count,
            areasComplete: completeAreas.count,
            requiredItemsTotal: requiredItemsTotal,
            requiredItemsReviewed: requiredItemsReviewed,
            undocumentedDamageCount: undocumentedDamage.count,
            areasNeedingAttention: areasNeedingAttention,
            evidenceCount: evidenceCount,
            pendingSharedEvidenceCount: inbox.pendingCount(),
            daysUntilConditionReportDue: tenancy.daysUntilConditionReportDue(asOf: now, calendar: calendar)
        )

        // Rule 2: derive status rather than trusting a stored flag.
        let derivedStatus: TenancyStatus = progress.isReportReady ? .reportReady : .documenting
        if tenancy.status != derivedStatus && tenancy.status != .archived {
            tenancy.status = derivedStatus
            try tenancyRepository.save(tenancy)
        }

        // Rule 3: only the reduced snapshot crosses into shared storage.
        snapshotPublisher.publish(progress.snapshot(generatedAt: now))

        return Summary(tenancy: tenancy, progress: progress)
    }

    /// Publishes an empty snapshot so the widget stops showing a stale summary
    /// once the tenant has no active tenancy.
    func publishEmptySnapshot() {
        snapshotPublisher.publish(.noActiveTenancy)
    }

    private func areasContaining(
        _ items: [ConditionItem],
        among areas: [InspectionArea]
    ) -> [InspectionArea] {
        let affectedAreaIDs = Set(items.map(\.inspectionAreaID))
        return areas.filter { affectedAreaIDs.contains($0.id) }
    }
}
