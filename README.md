# MoveProof

**A platform-integrated iOS application for rental condition evidence management.**

UTS Advanced iOS Development, Assessment 3.

MoveProof helps a tenant moving into a rental property document the condition they
found it in, room by room, and keep the resulting photos, notes and paperwork
organised against the property they belong to.

> MoveProof is an evidence capture and organisation tool. It does not give legal
> advice and does not determine who is responsible for any damage.

---

## Contents

- [The problem](#the-problem)
- [Primary stakeholder](#primary-stakeholder)
- [Key workflow](#key-workflow)
- [Architecture](#architecture)
- [Why Core Data](#why-core-data)
- [Core Data model](#core-data-model)
- [Repository layer](#repository-layer)
- [Use Case layer](#use-case-layer)
- [Human-centred errors](#human-centred-errors)
- [Screens](#screens)
- [System extensions](#system-extensions)
- [App Group](#app-group)
- [Project structure](#project-structure)
- [Setup](#setup)
- [Building](#building)
- [Testing](#testing)
- [What is verified, and how](#what-is-verified-and-how)
- [Git workflow](#git-workflow)
- [Attribution](#attribution)

---

## The problem

In NSW, a tenant moving into a rental property receives a condition report from the
landlord or agent and must return a completed copy **within seven days of moving in**.
NSW Government guidance also recommends taking time-stamped photographs to go with
that report, because "the more detail, including time-stamped photographs, in a
condition report, the less likely disputes will arise at the end of a tenancy."

In practice the resulting evidence ends up scattered. Photos sit in the camera roll
mixed in with everything else from moving week. The condition report PDF arrives by
email. Messages to the agent about a broken fitting sit in a separate thread. Nothing
connects a photograph to the room it was taken in, let alone to the line on the
report it supports.

That leaves the tenant unable to answer questions that matter at the end of a
tenancy, and unable to answer them at the start either:

- Which rooms have I actually been through?
- Which room does this photo belong to?
- Have I recorded anything to back up the damage I ticked?
- Is the initial walkthrough complete?
- Where did that PDF the agent sent me end up?
- How long do I have left?

MoveProof turns that into a single room-based workflow, and treats *damage recorded
with nothing to back it up* as the specific failure worth designing against.

Sources are recorded in [`docs/references.md`](docs/references.md).

## Primary stakeholder

A tenant in NSW who is moving into a rental property and needs to document, organise
and retrieve evidence of the property's condition: at the start of the tenancy, when
the seven-day deadline applies, and throughout it.

The design follows from that stakeholder, not from a generic CRUD app:

- The walkthrough opens pre-populated with rooms and checklists, because a tenant on
  moving day should not have to build a form before they can start.
- The deadline is visible on every screen, because that is the part with a clock on it.
- The app pushes back when damage is recorded without support, because a bare
  "damaged" tick is worthless months later.
- The widget shows progress, **not** the address or the photos, because a Home Screen
  is visible to anyone who can see the phone.

## Key workflow

```
Add property
   └─ MoveProof seeds 8 rooms, each with a condition checklist
        └─ Open a room
             └─ Record each item: undamaged / minor wear / damaged / not working
                  └─ Damage requires a note or a photo before it will save
                       └─ Sign the room off
                            └─ Blocked while items are unreviewed
                               or damage is undocumented

In parallel, from any other app:
   Share a photo or PDF to MoveProof
        └─ lands in the shared items inbox
             └─ tenant files it against a room and checklist item
```

## Architecture

```
View  →  ViewModel  →  Use Case  →  Repository protocol  →  Core Data repository  →  Core Data
```

The rule the whole structure exists to enforce: **no view and no view model imports
CoreData or holds an `NSManagedObjectContext`.** They work exclusively in domain value
types (`Tenancy`, `InspectionArea`, `ConditionItem`, `EvidenceItem`). You can verify
this directly:

```bash
grep -rn "import CoreData\|NSManagedObjectContext\|NSFetchRequest" MoveProof/Features/
# no matches
```

Business rules live in the Use Case structs and nowhere else, and **no view model
writes to a repository directly.** View models read through the repository protocols
to build what the screen shows, and every write goes through a use case. That is also
checkable:

```bash
grep -rn "Repository.save(\|Repository.delete(\|Repository.createAreas(" MoveProof/Features/
# no matches
```

A view can *hint* at a rule (`ConditionItemDetailView` shows a prompt while damage
has no backing), but the refusal itself always comes from the use case, and the
wording the tenant sees is the wording the domain error defines. There is no second
copy of the rules in the UI.

Where two use cases share a rule, the rule is pulled out instead of copied.
`StartTenancyInspectionUseCase` and `UpdateTenancyDetailsUseCase` both check through
`TenancyDetailsRules`, so the address and due date rules have one implementation and
the two screens cannot end up disagreeing.

The full diagram, including the human boundary and the shared-evidence data flow, is
in [`docs/architecture.mmd`](docs/architecture.mmd) (Mermaid).

Object graph assembly happens in one explicit place, `AppEnvironment`, with no
dependency injection container. `AppEnvironment.live()` wires the Core Data
implementations; tests build the same graph with mocks.

## Why Core Data

Core Data rather than CloudKit or SwiftData, for reasons specific to this app:

- **The data is relational and the queries are relational.** The questions MoveProof
  needs to answer, such as "which rooms are still incomplete" and "which damage has
  nothing backing it up", are predicate queries that traverse relationships. The
  undocumented damage query spans two relationships and aggregates a third;
  `NSPredicate` answers it in the store, so the app does not have to load every
  checklist item and sift through it in memory.
- **The extensions must not carry the persistence stack.** A widget has a tight time
  and memory budget and a share extension is killed quickly if it uses much. Core Data
  stays entirely inside the main app; the extensions see only a JSON snapshot and a
  file inbox.
- **CloudKit was rejected** because the evidence is private to one tenant on one device
  and the assessment's value is in the local modelling. Sync would add an account
  requirement and a conflict-resolution problem without serving the stakeholder.
- **SwiftData was rejected** because the assessment calls for Core Data, and because
  the explicit `NSPredicate` and delete-rule modelling below is the part worth showing.

Evidence binaries are **not** stored in Core Data. Photographs are large and a tenant
may file dozens. The files live in the App Group container and Core Data holds metadata
plus a relative file name, which keeps the store small and lets a file handed over by
the Share Extension be adopted without copying it out of the sandbox and back in.

## Core Data model

Four entities, three relationships:

```
TenancyEntity
  ├── areas ──────────► InspectionAreaEntity          (cascade)
  │                       └── conditionItems ────────► ConditionItemEntity   (cascade)
  │                                                      └── evidence ──────► EvidenceItemEntity (NULLIFY)
  └── evidence ───────► EvidenceItemEntity            (cascade)
```

| Entity | Key attributes |
| --- | --- |
| `TenancyEntity` | `id`, `propertyAddress`, `moveInDate`, `conditionReportDueDate`, `createdAt`, `statusRaw` |
| `InspectionAreaEntity` | `id`, `name`, `inspectionStatusRaw`, `displayOrder` |
| `ConditionItemEntity` | `id`, `title`, `categoryRaw`, `conditionStateRaw`, `notes`, `reviewedAt`, `isRequired` |
| `EvidenceItemEntity` | `id`, `kindRaw`, `storedFileName`, `displayName`, `capturedAt`, `notes`, `sourceRaw`, `importedInboxItemID` |

**Delete rules are chosen per relationship, not left at the default.** Rooms and
checklist items cascade from their parent because they have no meaning without it. But
`ConditionItem → evidence` **nullifies**: deleting a checklist item returns the tenant's
photos to the unfiled evidence library instead of destroying them. Losing a checklist
row is an inconvenience; losing the photograph that proves the state of a property is
the thing MoveProof exists to prevent. This is covered by
`testDeletingARoomKeepsTheTenantsEvidenceInTheLibrary`.

Enums are persisted as raw strings and translated in exactly one place,
`ManagedObjectMapping`. An unrecognised raw value degrades to a safe default rather
than crashing a tenant mid-walkthrough.

## Repository layer

Three repository protocols plus two supporting ones, all expressed purely in domain
value types:

| Protocol | Responsibility |
| --- | --- |
| `TenancyRepository` | The property being documented |
| `InspectionRepository` | Rooms and their condition checklists |
| `EvidenceRepository` | Evidence metadata |
| `EvidenceFileStore` | Evidence binaries in the App Group |
| `InspectionSnapshotPublishing` | Publishing the reduced summary to the widget |

### Predicate-based queries

These are real domain questions asked of the store, not `fetchAll()` plus a filter:

| Query | Predicate |
| --- | --- |
| `fetchActiveTenancy()` | `statusRaw IN {documenting, reportReady}`, newest first, `fetchLimit = 1` |
| `fetchConditionItemsMissingSupportingDetail(forTenancy:)` | `inspectionArea.tenancy.id == %@ AND conditionStateRaw IN {damaged, notWorking} AND notes == "" AND evidence.@count == 0` |
| `fetchEvidence(importedFromInboxItem:)` | `importedInboxItemID == %@`, which makes shared-evidence import idempotent |
| `fetchUnassignedEvidence(forTenancy:)` | `tenancy.id == %@ AND conditionItem == nil` |
| `evidenceCount(forConditionItem:)` | `context.count(for:)`, a number without loading the objects |

The third one is the query MoveProof is built around. It combines three domain
conditions, traverses two relationships and aggregates a third.

## Use Case layer

Thirteen structs. Each one is a single operation a tenant would recognise, and owns
its own rules.

| Use Case | Rules enforced | Typed errors |
| --- | --- | --- |
| `StartTenancyInspectionUseCase` | Address required; one walkthrough at a time; move-in date not absurdly backdated; deadline on or after move-in. Seeds rooms and per-room checklists. | `TenancySetupError` |
| `UpdateTenancyDetailsUseCase` | Fixes an address or due date without disturbing the walkthrough. Same field rules via `TenancyDetailsRules`, except the backdating typo check, which does **not** apply to a tenancy already under way. The id, creation date and status are not editable. | `TenancySetupError` |
| `AddInspectionAreaUseCase` | A walkthrough must exist, a room needs a name, and **room names must be unique within a walkthrough** so evidence stays easy to match. Adds the standard checklist and puts the room at the end. | `InspectionAreaEditError` |
| `RenameInspectionAreaUseCase` | Name required; uniqueness re-checked against the other rooms; renaming to the name it already has does nothing and is not treated as a clash. | `InspectionAreaEditError` |
| `RemoveInspectionAreaUseCase` | Removing an absent room is not a failure. Counts the evidence **before** deleting and reports how much goes back to the library unfiled, because the store nullifies instead of cascading. | None |
| `ReopenInspectionAreaUseCase` | Only a signed-off room can be reopened; it returns to in-progress, never to not-started. | `InspectionAreaEditError` |
| `RecordConditionEvidenceUseCase` | **Damage or a fault needs a note or a photo before it will save.** A condition must be chosen. Evidence cannot come from another property. Advances the room to in-progress. | `ConditionRecordingError` |
| `CompleteInspectionAreaUseCase` | No sign-off while required items are unreviewed, or while damage is undocumented. Re-checks the room as it is now instead of trusting it was fine when recorded. | `InspectionCompletionError` |
| `CaptureEvidenceUseCase` | A tenancy must exist, an empty pick is refused instead of saved as a useless file, the checklist link is checked before any bytes are written, photos cannot be attached across properties, and a failed save deletes the file again. | `EvidenceCaptureError` |
| `FileEvidenceUseCase` | Where evidence belongs and what it shows are **one** operation. The evidence must still exist, the target item must be in this walkthrough and this property, and notes are trimmed in one place. | `EvidenceFilingError` |
| `DiscardEvidenceUseCase` | The database row goes before the file. Warns the tenant when a discard leaves damage with nothing to show for it, so they do not quietly lose their only proof. | None |
| `ImportSharedEvidenceUseCase` | A tenancy must exist; only photos and PDFs; the file must still be there; **import is idempotent**; the inbox is drained only after the evidence is committed. | `SharedEvidenceImportError` |
| `ReviewInspectionProgressUseCase` | Status is worked out from what is recorded, not stored by hand. Only counts, progress and the due date reach the widget. This is also the one place the app calls to rewrite the snapshot after a successful save. | `InspectionReviewError` |

Two of these return an outcome instead of throwing, because the operation does
succeed but the tenant still needs to know something. Removing a room reports how many
photos became unfiled, and discarding evidence reports when it was the last thing
backing a damaged item. Neither one refuses what the tenant asked for.

The two rules that actually block the tenant are worth setting out separately:

**Damage needs backing up.** Ticking "damaged" and moving on produces a record that
means nothing at the end of a tenancy. `RecordConditionEvidenceUseCase` refuses it
unless there is a note or at least one piece of evidence.

**Sign-off checks again.** `CompleteInspectionAreaUseCase` re-checks what
`RecordConditionEvidenceUseCase` already enforced, because photos can be deleted
afterwards. `ReviewInspectionProgressUseCase` goes further and pulls a
tenancy back out of `reportReady` if the evidence behind a signed-off room disappears.

## Human-centred errors

Every domain error conforms to `TenantFacingError`, which requires two things: what
went wrong, and what the tenant can do next.

```swift
protocol TenantFacingError: Error {
    var whatHappened: String { get }
    var whatToDoNext: String { get }
    var title: String { get }
}
```

Real examples from the code:

> **This damage needs backing up**
> You've marked "Flooring" as damaged, but there's nothing recorded to show what you saw.
> Add a photo or write a short note describing the damage, so you can identify it again at the end of the tenancy.

> **This room isn't ready yet**
> 2 checklist items in this room still haven't been reviewed, starting with "Windows and coverings".
> Record what you found for each remaining item, then sign the room off.

Anything that is *not* a domain rule, such as a failed write or an unreachable
container, is wrapped in `UnexpectedFailure`, which still tells the tenant what was
happening and what to try, while the technical detail goes to `AppLog` (OSLog) and
never to the screen. There is no path by which "Save failed" can reach a tenant.

## Screens

Eight functional screens (the assessment minimum is five).

| # | Screen | Purpose |
| --- | --- | --- |
| 1 | Tenancy Dashboard | Deadline, progress, evidence count, what needs attention, empty state |
| 2 | Create / Edit Tenancy | Address, move-in date, seven-day default deadline, validation |
| 3 | Inspection Areas | Rooms, per-room progress, undocumented-damage warnings |
| 4 | Inspection Area Detail | Grouped condition checklist and sign-off |
| 5 | Condition Item Detail | Record the condition, write a note, attach photos |
| 6 | Evidence Library | Everything filed, with filters including "needs filing" |
| 7 | Evidence Detail | Preview, provenance, and filing against a checklist item |
| 8 | Shared Evidence Inbox | Items from the Share Extension, imported or discarded |

Every screen has a meaningful empty state, uses rental-inspection vocabulary
throughout ("Walkthrough", "Rooms", "Sign off", "Needs filing", never "Items",
"Records" or "Save"), and combines accessibility elements so VoiceOver reads a row as
one sentence.

## System extensions

### Widget Extension (WidgetKit)

Two families: **`systemSmall`** and **`systemMedium`**.

*Why a widget for this stakeholder:* the tenant has a clock running, seven days from
move-in, and the thing they need at a glance is whether they are on track. That is
the shape of a widget: a number and a date, looked at often, never tapped.

*How it gets its data:* the widget never touches Core Data. `ReviewInspectionProgressUseCase`
reduces the progress to an `InspectionSnapshot` and `WidgetSnapshotPublisher` writes it
to `Widget/snapshot.json` in the App Group, then calls
`WidgetCenter.shared.reloadTimelines(ofKind:)`. The provider decodes one small file.

*When it refreshes:* after **every** successful save, not only when the dashboard
happens to be open. The app has one place where it records a save,
`MoveProofModel.dataChanged()`. Every screen calls it once a use case reports success,
and it calls `ReviewInspectionProgressUseCase.refreshPublishedSnapshot()`. The order
matters both ways: the reload never runs before the save has gone through, and no use
case has to remember to call `WidgetCenter` itself. If the recalculation fails, the
old snapshot stays where it is instead of being overwritten with something worse, and
the tenant is not interrupted over a Home Screen summary.
`WidgetRefreshAfterChangeTests` covers this.

*When data is missing or unreadable:* `InspectionSnapshotStore.read()` returns `nil`
if the container cannot be reached, the file was never written, or the JSON will not
decode. The provider then uses `InspectionSnapshot.noActiveTenancy` and the widget
draws its "nothing set up yet" state. It cannot get stuck on "No data", because that
state is a real designed layout, not a failure.

*The privacy decision:* the widget shows counts, progress and days remaining. It does
**not** show the property address, the damage descriptions or any photograph. All
three would be more useful, and all three are things a tenant would not want visible
to anyone who can see the device. `InspectionSnapshot` has no field that could carry them, and
`testTheWidgetSnapshotCarriesCountsButNotThePropertyAddress` encodes the snapshot and
asserts the address and room names are absent.

### Share Extension

*Why a share extension for this stakeholder:* the evidence problem is a *fragmentation*
problem. The condition report PDF arrives in Mail, photos are in Photos, a receipt is in
Files. Asking the tenant to re-find each one inside MoveProof would recreate the problem;
the share sheet lets them push evidence in from wherever it already is.

*What it does:* claims images and files in the share sheet, copies what it is handed into
the App Group inbox along with its type identifier and original name, confirms, and calls
`completeRequest(returningItems:)` so the sheet dismisses.

*What it does not do:* it holds **no domain logic**. It does not know what a
tenancy is, whether a PDF is usable as evidence, or whether this file has been shared
before. `ImportSharedEvidenceUseCase` in the main app decides all of that. A share
extension is memory-constrained and short-lived, and duplicating those rules would mean
two copies to keep in step.

## App Group

`group.com.krischuang.MoveProof`

Defined once, in `MoveProofShared/AppGroup.swift`, and shared by all three targets. The
container has three separated areas; mixing them would make the widget's read-only
summary and the extension's file hand-off hard to reason about:

```
group.com.krischuang.MoveProof/
├── Evidence/              app-controlled evidence files (main app writes)
├── SharedEvidenceInbox/   hand-off inbox (extension writes, app drains)
│   ├── <uuid>.jpg         the shared file
│   └── <uuid>.json        its metadata sidecar
└── Widget/
    └── snapshot.json      reduced summary (app writes, widget reads)
```

## Project structure

```
MoveProof/
├── App/                       MoveProofApp, AppEnvironment (composition root), AppLog
├── Domain/
│   ├── Models/                Tenancy, InspectionArea, ConditionItem, EvidenceItem, InspectionProgress
│   ├── Errors/                TenantFacingError + the typed domain errors
│   └── Rules/                 TenancyDetailsRules, shared by start and update
├── UseCases/                  the thirteen use case structs
├── Data/
│   ├── CoreData/              Core Data repositories + ManagedObjectMapping
│   ├── Persistence/           InspectionStore, AppGroupEvidenceFileStore, WidgetSnapshotPublisher
│   └── Repositories/          the repository protocols
├── Features/
│   ├── Tenancy/               dashboard + setup
│   ├── Inspection/            room list, room detail, condition item detail
│   ├── Evidence/              library + detail
│   ├── SharedInbox/           shared items inbox
│   └── Shared/                TenantMessage, EvidenceThumbnail
└── MoveProof.xcdatamodeld

MoveProofShared/               compiled into the app AND the extensions
├── AppGroup.swift             identifier + container layout
├── InspectionSnapshot.swift   the reduced widget model + its store
├── InspectionWidgetViews.swift  widget view layer (see note below)
└── SharedEvidenceInbox.swift  the extension ↔ app hand-off

MoveProofWidget/               widget extension target
MoveProofShareExtension/       share extension target

MoveProofTests/
├── Mocks/                     in-memory repository doubles
├── UseCases/                  rule tests against mocks
├── Repositories/              predicate + delete-rule tests against a real in-memory store
└── Widget/                    App Group contract + both-family rendering

MoveProofUITests/              end-to-end workflow and share-sheet tests
docs/                          report draft, architecture diagram, references, rubric audit
```

> **Note on `InspectionWidgetViews.swift`:** the widget's view layer sits in
> `MoveProofShared` so the app target compiles it too. A widget extension cannot be
> instantiated from a test, but its views can, which is what lets
> `WidgetSnapshotTests` render both families with `ImageRenderer` and catch a layout
> that would come out blank on the Home Screen.

## Setup

**Requirements:** Xcode 26.1 or later, iOS 26.1 simulator or device. No package
dependencies to resolve.

```bash
git clone git@github.com:krischuang/MoveProof.git
cd MoveProof
open MoveProof.xcodeproj
```

**Signing.** The three targets are set to automatic signing. For the simulator nothing
further is needed: the App Group works without a provisioning profile, which is how
the extension and widget data flow in this project was verified.

**To run on a physical device** you must, once, in Xcode:

1. Select each of the three targets (`MoveProof`, `MoveProofShareExtension`,
   `MoveProofWidgetExtension`), open *Signing & Capabilities*, and set your Team.
2. Confirm the **App Groups** capability lists `group.com.krischuang.MoveProof` on all
   three. The entitlement files already declare it; Xcode needs to register it against
   your team.

## Building

```bash
xcodebuild -project MoveProof.xcodeproj -scheme MoveProof \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

The `MoveProof` scheme builds all three targets: the app depends on both extensions
and embeds them in `PlugIns/`.

If `iPhone 17` is not installed, list what is:

```bash
xcrun simctl list devices available | grep iPhone
```

## Testing

**Unit tests (148 tests, fast, no UI):**

```bash
xcodebuild test -project MoveProof.xcodeproj -scheme MoveProof \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:MoveProofTests
```

**End-to-end workflow test:**

```bash
xcodebuild test -project MoveProof.xcodeproj -scheme MoveProof \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  -only-testing:MoveProofUITests/MoveProofWalkthroughUITests
```

**The cross-app share-sheet test, and why it is opt-in.**

`ShareExtensionUITests` drives four processes: MoveProof, Photos, the system share
sheet, the extension, then MoveProof again. It **passes**, and it is the evidence that the
extension really is registered, really writes to the App Group, and really dismisses
itself. But it depends on simulator state that the test cannot control: it needs photos
in the library, and Photos' grid does not respond to element-relative taps, so the test
has to tap by window coordinate.

Rather than let that make `xcodebuild test` unreliable, the shared scheme skips this one
class by default. Run it explicitly on a clean simulator:

```bash
xcrun simctl erase "iPhone 17" && xcrun simctl boot "iPhone 17"
xcrun simctl addmedia "iPhone 17" <a-few-image-files>
xcodebuild test -project MoveProof.xcodeproj -scheme MoveProof \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  -only-testing:MoveProofUITests/ShareExtensionUITests
```

Nothing is lost by skipping it in the default run: the extension's own logic is covered
deterministically by `SharedItemCollectorTests`, and the import rules by
`ImportSharedEvidenceTests`, both in the unit target.

**Simulator notes.** Pass `-parallel-testing-enabled NO` when you want a test to run on
the named simulator instead of a throwaway clone, which you need in order to
inspect the App Group container afterwards. The project ships a **shared scheme**, so
a fresh clone gets the same build and test configuration instead of an auto-generated
one.

## What is verified, and how

Stated plainly, because "it compiles" is not verification.

| Claim | How it was verified |
| --- | --- |
| App builds, all three targets | `xcodebuild build` succeeds |
| Whole default suite passes | `xcodebuild test`: **148 unit + 5 UI tests, 0 failures** |
| 148 unit tests pass | `xcodebuild test -only-testing:MoveProofTests`: 148 executed, 0 failures |
| Business rules fire with tenant-facing wording | Unit tests, plus `MoveProofWalkthroughUITests` asserting the exact on-screen strings for both refusals, including the what-to-do-next line |
| Core Data predicates are valid and correctly scoped | `CoreDataRepositoryTests` against a real in-memory store |
| Delete rules behave as modelled | `testDeletingARoomKeepsTheTenantsEvidenceInTheLibrary` |
| App Group container is reachable | Inspected on disk in the simulator; `group.com.krischuang.MoveProof` is created on launch |
| App publishes widget data after a change | Ran the workflow test on the named simulator, then read `Widget/snapshot.json`, which contained `areasTotal: 8`, `daysUntilConditionReportDue: 7`, `hasActiveTenancy: true` |
| Both widget families render | `WidgetSnapshotTests` renders `SmallInspectionView` and `MediumInspectionView` with `ImageRenderer` and asserts non-blank output, including a stress case with three-digit counts and an overdue deadline |
| Widget/app share the same snapshot | `testASnapshotWrittenByTheAppIsReadableByTheWidget` |
| Extensions carry the App Group entitlement | Inspected the built `.appex` binaries |
| Share Extension ↔ app hand-off works | `ImportSharedEvidenceTests` writes into the real App Group inbox exactly as the extension does, then imports through the use case |
| Share Extension's own logic works | `SharedItemCollectorTests`: 13 tests against real `NSItemProvider`s, asserting which attachments are accepted, which UTI is recorded, and that bytes arrive unchanged |
| MoveProof appears in the real iOS share sheet, saves, and dismisses | `ShareExtensionUITests` passed end to end: from Photos, Share lists **MoveProof**; *Save to MoveProof* writes the file and the sheet dismisses itself; the app then finds it in *Shared*, and import files it into the evidence library |

### Widget verification checklist (manual)

Placing a widget on the Home Screen means driving SpringBoard. Automating the widget
gallery was not reliable, so this is listed as a manual check instead of being claimed
as automated. Everything below the Home Screen itself (the snapshot format, both
family layouts, the refresh trigger) is covered by tests.

1. Launch MoveProof and add a property on the **Walkthrough** tab. MoveProof seeds
   eight rooms.
2. Open **Rooms**, open any room, record a few checklist items, and sign the room off.
3. Return to the Home Screen. Long-press, tap **Edit**, then **Add Widget**, and
   search for **MoveProof**.
4. Choose *Walkthrough progress* at the **small** size and add it. Confirm it shows
   the rooms-reviewed count and the days remaining until the condition report is due,
   and **not** the property address.
5. Repeat step 3 and add the **medium** size. Confirm it additionally shows the
   evidence count and anything needing attention.
6. Reopen MoveProof, sign off a second room, and background the app.
7. Confirm both widgets now show the higher reviewed count. This is the refresh
   firing from `dataChanged()`, not from the dashboard being visited.
8. Mark a checklist item as *damaged* without adding a photo or note, then check the
   medium widget reports an item needing attention.
9. Delete the app and reinstall it without opening it. Confirm the widgets show the
   "nothing set up yet" state, not stale numbers or an error.

## Git workflow

`main` holds only stable, building, tested work. Every feature was developed on its own
branch and merged with `--no-ff` so the branch structure stays visible in the history.

```
feature/domain-foundation       domain models, typed errors, App Group
feature/core-data-repository    schema, repository protocols, predicate queries
feature/use-cases               the six use case structs
feature/inspection-workflow     the eight SwiftUI screens
feature/share-extension         Share Extension + App Group inbox
feature/widget-extension        WidgetKit extension, two families
feature/testing                 unit, repository and widget tests
docs/assessment-documentation   README, report draft, diagram, references, audit
fix/assessment3-rubric-gaps     move the remaining mutations into use cases,
                                typed capture errors, widget refresh on write
```

Commits follow Conventional Commits (`feat:`, `fix:`, `test:`, `docs:`, `refactor:`,
`chore:`). Derived data, `xcuserdata/` and signing artefacts are gitignored; no secrets
or local developer files are tracked.

## Attribution

Built with Apple frameworks only, with **no third-party dependencies**. Apple documentation
consulted (WidgetKit, share extensions, App Groups, Core Data predicates and delete
rules, SwiftUI) is listed in [`docs/references.md`](docs/references.md), along with the
NSW Government and Tenants' Union of NSW sources that establish the problem and justify
the seven-day default deadline.

AI assistance was used during development and is described honestly in
[`docs/Assessment3_Report_Draft.md`](docs/Assessment3_Report_Draft.md).
