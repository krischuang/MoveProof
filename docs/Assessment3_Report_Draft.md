# MoveProof: A Platform-Integrated iOS Application for Rental Condition Evidence Management

**Assessment 3 — report draft**
UTS Advanced iOS Development

> **How to use this document.** This is source material for the final submitted PDF,
> not a replacement for it. Sections 1–3 are factual and check out against the code.
> Section 4 is a reflective report, and every passage that depends on your own
> experience or judgement is marked **[AUTHOR TO REVIEW]** — those are yours to write,
> not something that can be written for you.

---

## Section 1 — Problem Statement

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

MoveProof treats that as a rule rather than a suggestion. `RecordConditionEvidenceUseCase`
refuses to save a condition of `damaged` or `notWorking` unless the tenant has written a
note or attached at least one piece of evidence, and `CompleteInspectionAreaUseCase`
refuses to sign a room off while any such record exists.

### Primary stakeholder

A tenant in NSW moving into a rental property, who needs to document, organise and
retrieve evidence of the property's condition — at the start of the tenancy, under the
seven-day deadline, and throughout it.

Two constraints follow from who this person is and when they are using the app:

- **They are using it on moving day.** They are tired, surrounded by boxes, and working
  to a deadline. The app opens with rooms and checklists already in place; it does not
  ask them to build a form first.
- **The evidence is sensitive.** It describes where they live and what is wrong with it.
  That directly shapes what the widget is allowed to show (Section 4).

### Human cost

Without a usable record, a tenant entering a bond dispute is arguing from memory against
a documented position. The practical consequences are ordinary rather than dramatic:
paying for damage that was already there, or being unable to demonstrate that it was.
The NSW guidance is explicit that the report and its supporting detail are what get used
as evidence when there is a disagreement.

**[AUTHOR TO REVIEW]** — if you have your own or a friend's experience of a bond dispute,
a rushed condition report, or trying to find a photo from a year ago, one or two concrete
sentences here will be worth more than the general statement above. Keep it factual.

### Scope limits

MoveProof is an evidence capture, organisation, workflow and retrieval tool. It does not
give legal advice, does not determine liability, and makes no claim about who is
responsible for any damage. The seven-day default deadline is taken directly from the
NSW Government page cited in `docs/references.md`, is presented as a default the tenant
can change, and is not presented as legal advice.

Sources: see `docs/references.md`.

---

## Section 2 — Design Justification

### Why iOS

Three properties of the problem make it a platform problem rather than a web one:

1. **The evidence is created on the device.** The camera is the capture tool. A web app
   would add an upload step between seeing the damage and recording it, at exactly the
   moment the tenant is least willing to tolerate friction.
2. **Evidence arrives from other apps.** The condition report PDF is in Mail, receipts
   are in Files, photos are in Photos. iOS already has a mechanism for moving content
   between apps — the share sheet — and a native app can receive on it.
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
two-number question — rooms reviewed, days left. The medium size adds what needs
attention and what is waiting to be filed.

Section 4 covers what the widget deliberately does *not* show, and why.

### Why a Share Extension

The core problem is fragmentation, so the extension addresses the problem directly
rather than adding a convenience.

If MoveProof could only ingest evidence through its own importer, the tenant would have
to re-find each file inside MoveProof — recreating the retrieval problem the app exists
to solve. The share sheet lets them push evidence in from wherever it already lives, at
the moment they are already looking at it.

The extension is deliberately thin. It copies what it is handed into an App Group inbox
with its type identifier and original name, then completes the extension request. It
holds no domain logic at all — Section 4 explains why that boundary was drawn where it
was.

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

The store answers it. The alternative — load every checklist item in the tenancy and
filter in Swift — would produce the same answer while doing work that Core Data is built
to avoid.

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

**What is deliberately not in the database:** evidence binaries. Photographs are large
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

Delete rules were chosen per relationship rather than left at the default — see
Section 4.

---

## Section 3 — Architecture Diagram

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
rule — `ConditionItemDetailView` shows a prompt while damage lacks support — but the
refusal always comes from the use case, and the text the tenant reads is the text the
domain error defines. There is no second copy of the rules in the UI.

### Primary use-case flow — shared evidence

The path worth tracing in the final report, because it crosses every boundary:

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

Two ordering decisions in that flow are deliberate. The bytes are adopted *before* the
metadata is written, so the store can never point at a file that was not saved — and if
the write fails, the file is rolled back. The inbox is drained *only after* the evidence
is committed, so a crash mid-import leaves the item in the inbox to retry rather than
losing it. The idempotency rule stops that retry creating a duplicate.

---

## Section 4 — Reflective Report (draft, ~890 words of prose — inside the 700–900 range)

> **[AUTHOR TO REVIEW] — read this whole section before using it.** The technical
> reasoning below is accurate and matches the implementation. The *first-person framing*
> is a draft you should make your own. Where a sentence claims something about your
> experience, judgement or process, rewrite it in your words or cut it. Do not submit a
> reflection about experiences you did not have.

### The problem and why it justified this app

I chose rental condition evidence because the failure mode is specific and backed by a
real rule: NSW tenants must return a completed condition report within seven days of
moving in, and government guidance recommends time-stamped photographs to go with it.
That gave me a deadline to build the interface around and a checklist to model, rather
than a vague "organise your stuff" premise.

The design got sharper when I narrowed the problem. Tenants do take photographs; the
photographs just never become a record. So I stopped treating the app as storage and
picked one failure to design against: damage recorded with nothing to back it up. A
"damaged" tick with no note and no photo is worthless at the end of a tenancy, and it is
exactly what a generic notes app cannot prevent.

**[AUTHOR TO REVIEW]** — if this app came from something you or someone you know went
through, say so here in one or two sentences. That is worth more than the reasoning above.

### Extension design decisions

Both extensions do something the app cannot do from inside itself. The widget exists
because the tenant's recurring question — "am I on track and how long have I got" — is
numeric, checked often, and needs no interaction. The share extension exists because the
problem is fragmentation: the report PDF is in Mail, the photos are in Photos. Making the
tenant re-find each file inside MoveProof would recreate the problem the app is meant to
solve.

The decision I spent longest on was how much the share extension should know. Letting it
write straight into the domain would have been less code, but the validation rules would
then exist in two processes — and a share extension is memory-constrained and
short-lived, so it is the worst place for logic that matters. Making it a file courier
that records the bytes, the name and the type identifier, and leaves every judgement to
`ImportSharedEvidenceUseCase`, means one place decides what counts as evidence.

### Database design and schema

Core Data, because the questions MoveProof asks are relational. The query the app is built
around — which condition items record damage but have neither a note nor any evidence —
spans two relationships and aggregates a third, and Core Data answers it in the store.

Keeping photographs out of the database is the decision I would defend hardest. They are
large, a tenant may file dozens, and storing them in Core Data would bloat it for no
benefit. They live in the App Group container with metadata in Core Data, which also lets
a shared file be adopted without copying it out of the sandbox and back in.

Delete rules took more thought than I expected. Rooms and checklist items cascade from
their parent because they have no meaning without it. But `ConditionItem → evidence`
nullifies: deleting a checklist item returns the tenant's photos to the unfiled library
rather than destroying them. Losing a checklist row is an inconvenience; losing the
photograph that proves the state of a property is what the app exists to prevent.

### Architecture under pressure — the trade-off

The tension I had to resolve was **widget usefulness against privacy.**

The genuinely useful things to put on a Home Screen widget are the property address, the
outstanding damage, and a photograph. All three would make it better, and all three are
things a tenant would not want visible to a flatmate picking up their phone. A widget
shows what a stranger can see.

I resolved it by giving the widget its own model. `InspectionSnapshot` carries counts,
progress and days remaining, and has no field capable of holding an address, a note or a
file name. The reduction happens in `ReviewInspectionProgressUseCase` before anything
reaches shared storage, so the sensitive data never crosses the boundary — it is not
filtered at render time, it is simply never there. A test encodes the snapshot and asserts
the address and room names are absent, so a future change that undid this would fail.

The cost is real: the medium widget says "2 rooms need attention" and cannot say which. I
judged that acceptable, because the tenant opens the app to act on it anyway, and the
widget's job is to prompt rather than to inform.

**[AUTHOR TO REVIEW]** — if you disagree with where I drew that line, say so. Arguing for
showing the address on a device behind a passcode is a defensible position, and defending
your own judgement reads better than agreeing with the code.

### What I would do differently

**[AUTHOR TO REVIEW]** — your call. Honest candidates from how the build actually went:

- Verifying the extensions was harder than writing them. The share-sheet test does pass
  end to end, but only on a clean simulator, and automating the Home Screen widget
  gallery never became reliable at all. I ended up testing the extensions' logic directly
  in the unit target and leaving the widget placement as a manual check. I would plan for
  that split from the start rather than discovering it late.
- The `@Observable` class I first wrote for the share extension crashed when released
  from a test. Making it a value type fixed it and produced a simpler design, which
  suggests the class was the wrong shape to begin with.
- Six use cases is arguably one more than necessary; `CaptureEvidenceUseCase` and
  `ImportSharedEvidenceUseCase` share a fair amount of shape.

### AI usage

**[AUTHOR TO REVIEW] — this must describe what you actually did. Draft below; correct it
to match.**

I used an AI assistant (Claude) throughout development, as permitted: scaffolding the
Xcode targets for both extensions, drafting the domain models, use cases, repositories and
SwiftUI screens from the design I specified, writing the test suite, and drafting this
documentation.

I directed the decisions that matter and verified the output rather than accepting it. The
domain model and the rules each use case enforces were my calls; the widget's privacy
reduction was my decision; and every claim in the README's verification table was checked
by running the build, running the tests, or inspecting the simulator's App Group container
on disk.

Two defects the process surfaced show the verification was real: a crash in the share
extension's collector when released from a test, traced to Swift's isolated-deinit path on
an `@Observable @MainActor` class; and a Core Data warning about duplicate entity
descriptions, caused by `NSPersistentContainer(name:)` loading a fresh model per container.
Both were found by running the tests, not by reading the code.

I can explain any file in this project, including why each delete rule and each predicate
is what it is.

---

## Appendix — evidence for marking

| Requirement | Where |
| --- | --- |
| Core Data, 4 related entities | `MoveProof/MoveProof.xcdatamodeld` |
| Meaningful predicate query | `CoreDataInspectionRepository.fetchConditionItemsMissingSupportingDetail(forTenancy:)` |
| Repository protocols | `MoveProof/Data/Repositories/Repositories.swift` |
| No Core Data in View/ViewModel | `grep -rn "import CoreData" MoveProof/Features/` → no matches |
| 6 Use Case structs | `MoveProof/UseCases/` |
| Typed domain errors | `MoveProof/Domain/Errors/DomainErrors.swift` |
| Human-centred messages | `TenantFacingError` — `whatHappened` + `whatToDoNext` |
| 8 screens | `MoveProof/Features/` |
| Widget, 2 families | `MoveProofWidget/`, `supportedFamilies([.systemSmall, .systemMedium])` |
| Share Extension | `MoveProofShareExtension/` |
| App Group | `MoveProofShared/AppGroup.swift` |
| 82 unit tests | `MoveProofTests/` |
| Mock repositories | `MoveProofTests/Mocks/MockRepositories.swift` |
| Git workflow | `git log --graph --oneline` |

Full requirement-by-requirement audit, including what is verified and what still needs a
manual check: `docs/Rubric_Audit.md`.
