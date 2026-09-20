import Foundation

/// The composition root.
///
/// One explicit place where the Core Data implementations are chosen and the use
/// cases are assembled. Everything downstream depends on protocols, so a test —
/// or a preview — builds the same object graph with mocks and no DI container is
/// needed to make that possible.
struct AppEnvironment {

    let tenancyRepository: TenancyRepository
    let inspectionRepository: InspectionRepository
    let evidenceRepository: EvidenceRepository
    let evidenceFileStore: EvidenceFileStore
    let sharedEvidenceInbox: SharedEvidenceInbox
    let snapshotPublisher: InspectionSnapshotPublishing

    init(
        tenancyRepository: TenancyRepository,
        inspectionRepository: InspectionRepository,
        evidenceRepository: EvidenceRepository,
        evidenceFileStore: EvidenceFileStore,
        sharedEvidenceInbox: SharedEvidenceInbox = SharedEvidenceInbox(),
        snapshotPublisher: InspectionSnapshotPublishing
    ) {
        self.tenancyRepository = tenancyRepository
        self.inspectionRepository = inspectionRepository
        self.evidenceRepository = evidenceRepository
        self.evidenceFileStore = evidenceFileStore
        self.sharedEvidenceInbox = sharedEvidenceInbox
        self.snapshotPublisher = snapshotPublisher
    }

    /// The live graph: Core Data repositories over the shared store, evidence files
    /// in the App Group, widget snapshots published through the same container.
    static func live(store: InspectionStore = .shared) -> AppEnvironment {
        let context = store.viewContext
        return AppEnvironment(
            tenancyRepository: CoreDataTenancyRepository(context: context),
            inspectionRepository: CoreDataInspectionRepository(context: context),
            evidenceRepository: CoreDataEvidenceRepository(context: context),
            evidenceFileStore: AppGroupEvidenceFileStore(),
            snapshotPublisher: WidgetSnapshotPublisher()
        )
    }

    // MARK: - Use cases
    //
    // Assembled here rather than inside view models, so a view model receives a
    // ready use case and never decides which repository implementation to use.

    var startTenancyInspection: StartTenancyInspectionUseCase {
        StartTenancyInspectionUseCase(
            tenancyRepository: tenancyRepository,
            inspectionRepository: inspectionRepository
        )
    }

    var recordConditionEvidence: RecordConditionEvidenceUseCase {
        RecordConditionEvidenceUseCase(
            inspectionRepository: inspectionRepository,
            evidenceRepository: evidenceRepository
        )
    }

    var completeInspectionArea: CompleteInspectionAreaUseCase {
        CompleteInspectionAreaUseCase(
            inspectionRepository: inspectionRepository,
            evidenceRepository: evidenceRepository
        )
    }

    var importSharedEvidence: ImportSharedEvidenceUseCase {
        ImportSharedEvidenceUseCase(
            tenancyRepository: tenancyRepository,
            evidenceRepository: evidenceRepository,
            evidenceFileStore: evidenceFileStore,
            inbox: sharedEvidenceInbox
        )
    }

    var captureEvidence: CaptureEvidenceUseCase {
        CaptureEvidenceUseCase(
            tenancyRepository: tenancyRepository,
            inspectionRepository: inspectionRepository,
            evidenceRepository: evidenceRepository,
            evidenceFileStore: evidenceFileStore
        )
    }

    var reviewInspectionProgress: ReviewInspectionProgressUseCase {
        ReviewInspectionProgressUseCase(
            tenancyRepository: tenancyRepository,
            inspectionRepository: inspectionRepository,
            evidenceRepository: evidenceRepository,
            inbox: sharedEvidenceInbox,
            snapshotPublisher: snapshotPublisher
        )
    }
}
