import WidgetKit

/// Supplies the widget with the summary the main app published into the App Group.
///
/// The provider never touches Core Data. It reads one small JSON file, which is how
/// the widget stays inside WidgetKit's tight time and memory budget, and why the
/// widget process needs to know nothing about the app's storage.
struct InspectionProgressProvider: TimelineProvider {

    private let store = InspectionSnapshotStore()

    /// Shown in the widget gallery and while the real snapshot loads. Uses sample
    /// numbers so the preview looks like a real walkthrough, not a row of zeroes.
    func placeholder(in context: Context) -> InspectionProgressEntry {
        InspectionProgressEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (InspectionProgressEntry) -> Void) {
        // In the gallery there is no tenant data to show, so use the sample.
        let snapshot = context.isPreview ? .sample : currentSnapshot()
        completion(InspectionProgressEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<InspectionProgressEntry>) -> Void) {
        let entry = InspectionProgressEntry(date: Date(), snapshot: currentSnapshot())

        // The app reloads the timeline whenever something is recorded, so all this
        // schedule has to handle is the date changing and the countdown ticking
        // down. Refreshing just after midnight is enough.
        let nextMidnight = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 1),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(60 * 60)

        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }

    /// Reads the written summary, falling back to the "nothing set up yet" state if
    /// the app has never run or the container cannot be reached.
    private func currentSnapshot() -> InspectionSnapshot {
        store.read() ?? .noActiveTenancy
    }
}

struct InspectionProgressEntry: TimelineEntry {
    let date: Date
    let snapshot: InspectionSnapshot
}
