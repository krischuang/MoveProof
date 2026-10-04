# MoveProof: A Platform-Integrated iOS Application for Rental Condition Evidence Management

**Assessment 3: report draft**
UTS Advanced iOS Development

> **How to use this document.** This is source material for the final submitted PDF,
> not a replacement for it. Sections 1 to 3 are factual and check out against the code.
> The author-review passages in Sections 1 and 4 have been resolved with confirmed
> information, with one exception: the list under *What I would do differently* is still
> marked **[AUTHOR TO REVIEW]**, because which of those lessons to keep is a judgement
> only the author can make.

---

## Section 1: Problem Statement

### The problem

In NSW, a tenant moving into a rental property is given a condition report by the
landlord or agent and must return a completed copy **within seven days of moving in**.
NSW Government guidance also advises tenants to "take photos to go with the condition
report - making sure to include time stamps to show when images were taken", and states
that "the more detail, including time-stamped photographs, in a condition report, the
less likely disputes will arise at the end of a tenancy."

The problem is not that tenants fail to take photographs. It is that the evidence never
becomes a *record*. In practice it ends up spread across:

- the camera roll, mixed in with everything else from moving week
- the condition report PDF, sitting in an email thread
- messages to the agent about a specific fitting
- screenshots of listings or prior correspondence

Nothing in that pile connects a photograph to the room it was taken in, and nothing
connects it to the line on the condition report it is supposed to support. The tenant
holds the evidence but cannot retrieve it in a usable form.

This leaves a set of questions unanswerable, both during the walkthrough and months
later:

- Which rooms have actually been inspected?
- Which room does this photograph belong to?
- Is there anything backing up the damage that was ticked?
- Is the initial inspection complete?
- Where did the imported document end up?
- How much time remains before the report is due?

### The specific failure MoveProof designs against

One of those is worth singling out, because it quietly destroys the value of the whole
exercise: **damage recorded with nothing to back it up.**

A tick in a "damaged" box, with no note and no photograph, is indistinguishable at the
end of a tenancy from a tick made by mistake. The tenant cannot say what they saw, where
it was, or how bad it looked. They did the work and still have nothing.

MoveProof treats that as a rule, not a suggestion. `RecordConditionEvidenceUseCase`
refuses to save a condition of `damaged` or `notWorking` unless the tenant has written a
note or attached at least one piece of evidence, and `CompleteInspectionAreaUseCase`
refuses to sign a room off while any such record exists.

### Primary stakeholder

A tenant in NSW moving into a rental property, who needs to document, organise and
retrieve evidence of the property's condition: at the start of the tenancy, under the
seven-day deadline, and throughout it.

Two constraints follow from who this person is and when they are using the app:

- **They are using it on moving day.** They are tired, surrounded by boxes, and working
  to a deadline. The app opens with rooms and checklists already in place; it does not
  ask them to build a form first.
- **The evidence is sensitive.** It describes where they live and what is wrong with it.
  That directly shapes what the widget is allowed to show (Section 4).

### Human cost

Without a usable record, a tenant entering a bond dispute is arguing from memory against
a documented position. The practical consequences are ordinary, not dramatic:
paying for damage that was already there, or being unable to demonstrate that it was.
The NSW guidance states that the condition report can be used as evidence if there is a
disagreement about missing items or damage.

This problem is also connected to my own rental experience. In a previous tenancy I had a
disagreement with the landlord about the condition in which the property was returned. The
landlord considered it insufficiently cleaned and deducted money from our bond. That
experience made the value of a clear and organised record of a property's condition much
more concrete to me, particularly where the two parties remember the same situation
differently.

### Scope limits

MoveProof is an evidence capture, organisation, workflow and retrieval tool. It does not
give legal advice, does not determine liability, and makes no claim about who is
responsible for any damage. The seven-day default deadline is taken directly from the
NSW Government page cited in `docs/references.md`, is presented as a default the tenant
can change, and is not presented as legal advice.

Sources: see `docs/references.md`.

---

## Section 2: Design Justification

### Why iOS

Three things about the problem make it a platform problem, not a web one:

1. **The evidence is created on the device.** The camera is the capture tool. A web app
   would add an upload step between seeing the damage and recording it, at the
   moment the tenant is least willing to put up with extra friction.
2. **Evidence arrives from other apps.** The condition report PDF is in Mail, receipts
   are in Files, photos are in Photos. iOS already has a mechanism for moving content
   between apps, the share sheet, and a native app can receive on it.
3. **The data is private and local.** One tenant, one property, one device. There is no
   collaboration requirement and no server that needs to hold the tenant's evidence.

### Why a Widget Extension

The tenant has a clock running: seven days from move-in. The question they ask
repeatedly is not "what did I record in the kitchen" but "am I on track, and how long
have I got".

That is a widget-shaped question. It has a numeric answer, it is checked often, and it
requires no interaction. Putting it on the Home Screen means the deadline stays visible
during the week when it matters, without the tenant opening the app to find out.

MoveProof's widget supports `systemSmall` and `systemMedium`. The small size answers the
two-number question: rooms reviewed, days left. The medium size adds what needs
attention and what is waiting to be filed.

Both families are covered by automated tests, which render each size and assert it is not
blank, check that a snapshot written by the app is readable through the widget's own
reading path, and cover the republish that follows a successful write. In addition to
those tests, I manually verified the widget on the iOS Home Screen. Both the small and
medium families could be added successfully and displayed the expected MoveProof data, and
changes made in the main app were reflected by the widget once the shared snapshot had been
refreshed. No problems were found during that manual check.

Section 4 covers what the widget does *not* show, and why.

### Why a Share Extension

The core problem is fragmentation, so the extension addresses the problem directly
instead of just adding a convenience.

If MoveProof could only ingest evidence through its own importer, the tenant would have
to re-find each file inside MoveProof, recreating the retrieval problem the app exists
to solve. The share sheet lets them push evidence in from wherever it already lives, at
the moment they are already looking at it.

The extension is kept thin on purpose. It filters attachments only by broad
structural type, copies what it is handed into an App Group inbox with its type identifier and
original name, then completes the extension request. Every judgement about what counts
as evidence is left to the main app. Section 4 explains why that boundary was drawn
where it was.

### Why Core Data

**The questions are relational, so the storage should be.** MoveProof does not need to
fetch a list; it needs to answer questions that span relationships:

- "Which rooms in this tenancy are still incomplete?"
- "Which condition items in this tenancy record damage but have neither a note nor a
  single piece of evidence?"

The second one is the query the app is built around. As an `NSPredicate` it traverses two
relationships and aggregates a third:

```swift
NSCompoundPredicate(andPredicateWithSubpredicates: [
    NSPredicate(format: "inspectionArea.tenancy.id == %@", tenancyID as CVarArg),
    NSPredicate(format: "conditionStateRaw IN %@", [damaged, notWorking]),
    NSPredicate(format: "notes == %@", ""),
    NSPredicate(format: "evidence.@count == 0")
])
```

The store answers it. The alternative, loading every checklist item in the tenancy and
filtering in Swift, would produce the same answer while doing work that Core Data is
built to avoid.

**The extensions must not carry the stack.** A widget runs under a tight time and memory
budget; a share extension is killed quickly if it uses much memory. Keeping Core Data
entirely inside the main app, with the extensions seeing only a JSON snapshot and a file
inbox, is a consequence of that.

**Alternatives considered:**

| Option | Why not |
| --- | --- |
| CloudKit | The evidence is private to one tenant on one device. Sync would add an iCloud account requirement and a conflict-resolution problem while serving no need the stakeholder actually has. |
| SwiftData | The assessment specifies Core Data, and the explicit predicate and delete-rule modelling here is the part worth demonstrating. SwiftData would hide it behind macros. |
| Files only (no database) | Answering "which damage is undocumented" would mean reading and parsing every record on every launch. |

**What is kept out of the database:** the evidence files themselves. Photographs are large
and a tenant may file dozens. They live in the App Group container with Core Data holding
metadata and a relative file name. This keeps the store small, lets iOS manage the files,
and means a file handed over by the Share Extension can be adopted without copying it out
of the sandbox and back in.

### Schema

```
TenancyEntity
  ├── areas ──────────► InspectionAreaEntity          (cascade)
  │                       └── conditionItems ────────► ConditionItemEntity   (cascade)
  │                                                      └── evidence ──────► EvidenceItemEntity (NULLIFY)
  └── evidence ───────► EvidenceItemEntity            (cascade)
```

Four entities, chosen to match how a condition report is actually structured: a property,
its rooms, the things checked in each room, and the evidence backing those checks.

Delete rules were chosen per relationship instead of left at the default; see
Section 4.

---

## Section 3: Architecture Diagram

The diagram source is `docs/architecture.mmd` (Mermaid). It shows the human/system
boundary, all four layers, both extension processes, the App Group and the primary
use-case data flow.

To render it: paste the file's contents into <https://mermaid.live>, or use the Mermaid
plugin for your editor, and export as PNG or SVG for the final PDF.

### The layering

```
View  →  ViewModel  →  Use Case  →  Repository protocol  →  Core Data repository  →  Core Data
```

The structural rule the whole design exists to enforce: **no view and no view model
imports CoreData or holds an `NSManagedObjectContext`.** They work exclusively in domain
value types. This is verifiable directly:

```bash
grep -rn "import CoreData\|NSManagedObjectContext\|NSFetchRequest" MoveProof/Features/
# no matches
```

Business rules live in the Use Case structs and nowhere else. A view may anticipate a
rule (`ConditionItemDetailView` shows a prompt while damage lacks support), but the
refusal always comes from the use case, and the text the tenant reads is the text the
domain error defines. There is no second copy of the rules in the UI.

The same holds for writes. No view model performs a persistent business mutation
through a repository; view models read through the repository protocols to assemble
screen state, and every write goes through one of the thirteen use cases. This is
also checkable directly:

```bash
grep -rn "Repository.save(\|Repository.delete(\|Repository.createAreas(" MoveProof/Features/
# no matches
```

Where two use cases share a rule it is pulled out instead of duplicated.
`StartTenancyInspectionUseCase` and `UpdateTenancyDetailsUseCase` both validate
through `TenancyDetailsRules`, so the address and deadline rules have exactly one
implementation. The one difference between them is passed in as a parameter instead
of being written out twice: the "this move-in date looks mistyped" check runs when
starting a walkthrough and is skipped when editing a tenancy that may already be
months old.

### Primary use-case flow: capturing evidence

This is the flow the diagram numbers, because it is the shortest path that still
goes through every layer and finishes on the Home Screen:

```
Tenant photographs a scratched floorboard
  → ConditionItemDetailView
  → ConditionItemDetailViewModel.attachPhoto
  → CaptureEvidenceUseCase
        a tenancy must exist
        the image must carry bytes
        the checklist item must be in this walkthrough and this property
  → EvidenceFileStore writes the file into Evidence/
  → EvidenceRepository writes the metadata
  → Core Data
  → MoveProofModel.dataChanged()        (only after the write committed)
  → ReviewInspectionProgressUseCase.refreshPublishedSnapshot()
  → reduced snapshot written to Widget/snapshot.json
  → WidgetCenter reloads → widget shows the new count
```

The checklist link is validated *before* any bytes are written, so a bad pick costs
nothing on disk, and if the metadata write fails the file is removed again, so the
library can never list evidence that cannot be opened.

### Secondary use-case flow: shared evidence

The path worth tracing alongside it, because it additionally crosses a process
boundary:

```
Tenant shares a PDF from Mail
  → Share Extension (separate process)
      copies the file + its type identifier into the App Group inbox
      calls completeRequest, sheet dismisses
  → Main app, later
      SharedEvidenceInboxView
      → SharedEvidenceInboxViewModel
      → ImportSharedEvidenceUseCase
            tenancy must exist
            type must be a photo or PDF
            file must still be there
            this inbox item must not already have been imported
      → EvidenceFileStore adopts the bytes into Evidence/
      → EvidenceRepository writes the metadata
      → Core Data
      → inbox drained (only now)
  → ReviewInspectionProgressUseCase republishes the reduced snapshot
  → WidgetCenter reloads → widget shows the new count
```

Two ordering decisions in that flow were made on purpose. The file is copied *before*
the database row is written, so the store can never point at a file that was not
saved, and if the write fails the copy is deleted. The inbox is cleared *only after*
the evidence is saved, so a crash part way through leaves the item in the inbox to
retry instead of losing it. The idempotency rule stops that retry creating a
duplicate.

---

## Section 4: Reflective Report

> **Note.** The technical reasoning below is accurate and matches the implementation, and
> the first-person passages have been confirmed with the author. The one remaining
> author-review item is the list under *What I would do differently*.

### The problem and why it justified this app

I chose rental condition evidence because the failure mode is specific and backed by a
real rule: NSW tenants must return a completed condition report within seven days of
moving in, and government guidance recommends time-stamped photographs to go with it.
That gave me a deadline to build the interface around and a checklist to model.

The design got sharper when I narrowed the problem. Tenants do take photographs; the
photographs just never become a record. So I stopped treating the app as storage and
picked one failure to design against: damage recorded with nothing to back it up. A
"damaged" tick with no note and no photo is worthless at the end of a tenancy, and it is
the thing a general notes app cannot prevent.

The problem also had a personal basis. In an earlier tenancy I had a disagreement with a
landlord who believed the property had not been cleaned adequately and deducted money from
our bond. What stayed with me was less the outcome than the difficulty of reconstruction:
once a tenancy has ended, the condition a property was actually in is hard to establish
from memory alone. That pushed me towards designing MoveProof around preserving evidence
with enough context for it to still be understood later, rather than around another place
to put photographs.

### Extension design decisions

Both extensions do something the app cannot do from inside itself. The widget exists
because the tenant's recurring question, "am I on track and how long have I got", is
numeric, checked often, and needs no interaction. The share extension exists because the
problem is fragmentation: the report PDF is in Mail, the photos are in Photos. Making the
tenant re-find each file inside MoveProof would recreate the problem.

The decision I spent longest on was how much the share extension should know. Letting it
write straight into the domain would have been less code, but the validation rules would
then exist in two processes, and a share extension is memory-constrained and short-lived,
so it is the worst place for logic that matters. Making it a file courier that records
the bytes, the name and the type identifier, and leaves every judgement to
`ImportSharedEvidenceUseCase`, means one place decides what counts as evidence.

### Database design and schema

Core Data, because the questions MoveProof asks are relational. The query the app is
built around, which condition items record damage but have neither a note nor any
evidence, spans two relationships and aggregates a third.

Keeping photographs out of the database is the decision I would defend hardest. They are
large, a tenant may file dozens, and storing them in Core Data would bloat it. They
live in the App Group container with metadata in Core Data, which also lets
a shared file be adopted without copying it out of the sandbox and back in.

Delete rules took more thought than I expected. Rooms and checklist items cascade from
their parent because they have no meaning without it. But `ConditionItem → evidence`
nullifies: deleting a checklist item returns the tenant's photos to the unfiled library
instead of destroying them. Losing a checklist row is an inconvenience; losing the
photograph that proves the state of a property is what the app exists to prevent.

### Architecture under pressure: the trade-off

The tension I had to resolve was widget usefulness against privacy.

The useful things to put on a Home Screen widget are the property address, the
outstanding damage, and a photograph. All three would make it better, and all three are
things a tenant would not want visible to whoever can see the phone.

I resolved it by giving the widget its own model. `InspectionSnapshot` carries counts,
progress and days remaining, and has no field capable of holding an address, a note or a
file name. The reduction happens in `ReviewInspectionProgressUseCase` before anything
reaches shared storage, so the sensitive data never crosses the boundary at all. A test
encodes the snapshot and asserts the address and room names are absent, so a future
change that undid this would fail.

The cost is real: the medium widget says "2 rooms need attention" and cannot say which.
I judged that acceptable, because the widget's job is to prompt, not to inform.

### What I would do differently

**[AUTHOR TO REVIEW]**: your call. Honest candidates from how the build actually went:

- Verifying the extensions was harder than writing them. The share-sheet test passes end
  to end, but only on a clean simulator, and automating the widget gallery never became
  reliable. I would plan for that split from the start.
- The `@Observable` class I first wrote for the share extension crashed when released
  from a test. Making it a value type fixed it and produced a simpler design, which
  suggests the class was the wrong shape to begin with.
- `CaptureEvidenceUseCase` and `ImportSharedEvidenceUseCase` share a fair amount of
  shape, and I kept them separate because their provenance and failure modes really
  do differ: one takes bytes the tenant picked in the app, the other adopts a file
  another process left in the inbox. Giving each its own typed error made that split
  pay off, but it is a judgement call I could be argued out of.
- I let the widget refresh hang off the dashboard for too long. It only republished
  when `ReviewInspectionProgressUseCase` happened to run, which meant signing a room
  off left the Home Screen stale until the tenant wandered back to the dashboard.
  Routing it through the one place the app records a save was a small change that
  should have been the design from the start.

### AI usage

Claude Code was the main AI-assisted development tool used on this project, as permitted:
scaffolding the Xcode targets for both extensions, drafting the domain models, use cases,
repositories and SwiftUI screens from the design I specified, writing the test suite,
drafting this documentation, and reviewing the architecture late in the project against the
assessment criteria.

I directed the decisions that matter and checked the output rather than accepting it.
The domain model and the rules each use case enforces were my calls, as was the
widget's privacy reduction. Every claim in the README's verification table was checked
by running the build, running the tests, or inspecting the App Group container on disk.

Four things show that checking was real rather than nominal:

- A crash in the share extension's collector when released from a test, traced to
  Swift's isolated-deinit path on an `@Observable @MainActor` class. Making it a value
  type fixed it.
- A Core Data warning about duplicate entity descriptions, caused by
  `NSPersistentContainer(name:)` loading a fresh model per container.
- A suggested rule for `RemoveInspectionAreaUseCase` that would have refused to delete
  a room holding evidence, on the grounds that deleting the room would destroy the
  photos. Checking the model showed `ConditionItem -> evidence` is set to **nullify**,
  not cascade, so the photos survive and the premise was wrong. The rule was replaced
  with one that reports how much evidence became unfiled.
- Five repository methods that no production code called, including one whose comment
  claimed two callers it did not have. Four were removed and the claim corrected.

The first two were found by running the tests; the last two by reading the Core Data
model and grepping for callers instead of trusting the description of the code.

I can explain any file in this project, including every delete rule and predicate.

---

## Appendix: evidence for marking

| Requirement | Where |
| --- | --- |
| Core Data, 4 related entities | `MoveProof/MoveProof.xcdatamodeld` |
| Meaningful predicate query | `CoreDataInspectionRepository.fetchConditionItemsMissingSupportingDetail(forTenancy:)` |
| Repository protocols | `MoveProof/Data/Repositories/Repositories.swift` |
| No Core Data in View/ViewModel | `grep -rn "import CoreData" MoveProof/Features/` returns no matches |
| No repository writes in ViewModels | `grep -rn "Repository.save(\|Repository.delete(" MoveProof/Features/` returns no matches |
| Widget reloads after a write | `MoveProofModel.dataChanged()` → `ReviewInspectionProgressUseCase.refreshPublishedSnapshot()`; `WidgetRefreshAfterChangeTests` |
| 13 Use Case structs | `MoveProof/UseCases/` |
| Typed domain errors | `MoveProof/Domain/Errors/DomainErrors.swift` |
| Human-centred messages | `TenantFacingError`, via `whatHappened` and `whatToDoNext` |
| 8 screens | `MoveProof/Features/` |
| Widget, 2 families | `MoveProofWidget/`, `supportedFamilies([.systemSmall, .systemMedium])` |
| Share Extension | `MoveProofShareExtension/` |
| App Group | `MoveProofShared/AppGroup.swift` |
| 148 unit tests | `MoveProofTests/` |
| Mock repositories | `MoveProofTests/Mocks/MockRepositories.swift` |
| Git workflow | `git log --graph --oneline` |

Full requirement-by-requirement audit, including what is verified and what still needs a
manual check: `docs/Rubric_Audit.md`.
