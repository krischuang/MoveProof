# MoveProof: rubric audit

A requirement-by-requirement check against the Assessment 3 criteria.

**A row is only marked Complete where the implementation exists *and* was actually
verified.** Anything that could not be verified in this environment is marked
**Manual check required** with the exact steps, rather than claimed.

Last run: 21 September 2026.

| Reference | Result |
| --- | --- |
| Build (`xcodebuild build`, all three targets) | `** BUILD SUCCEEDED **` |
| Unit tests (`-only-testing:MoveProofTests`) | 148 executed, 0 failures |
| Default test action (`xcodebuild test`) | 148 unit + 5 UI tests, 0 failures |
| Cross-app share sheet test (`ShareExtensionUITests`) | Passed |

---

## A. Problem Justification & App Relevance (20%)

| Requirement | Implementation | File(s) | Verification | Status | Remaining risk |
| --- | --- | --- | --- | --- | --- |
| Real documented problem | Fragmented rental condition evidence; NSW seven-day condition report deadline | `docs/Assessment3_Report_Draft.md` §1, `README.md` | Two real sources fetched and quoted, recorded with URLs and access dates | Complete | None. The author's own bond dispute is now recorded alongside the general statement. |
| Specific stakeholder | A NSW tenant moving into a rental property | §1 "Primary stakeholder" | Design decisions trace back to the stakeholder (pre-seeded checklists, deadline prominence, widget privacy) | Complete | None |
| Problem shapes the product, not just the pitch | The seven-day rule is a domain constant driving defaults and UI | `Tenancy.conditionReportWindowInDays`, `defaultConditionReportDueDate` | `testTheConditionReportDefaultsToSevenDaysAfterMovingIn` | Complete | None |
| Extension rationale | Widget = the recurring "am I on track" question; Share Extension = the fragmentation problem itself | §2 | Rationale argued in domain terms, not feature terms | Complete | None |
| Database rationale | Core Data justified by relational queries; CloudKit and SwiftData explicitly considered and rejected | §2 "Why Core Data" | The named predicate exists and is tested | Complete | None |
| Accurate architecture diagram | Mermaid source with all layers, both extension processes, App Group, human boundary, primary flow | `docs/architecture.mmd` | Cross-checked against actual type names | Complete | Must be rendered to an image for the PDF; see §3 of the report. |
| No legal-advice overreach | Scope limit stated in README and report; no liability claims anywhere in UI copy | `README.md`, §1 "Scope limits" | Reviewed all user-facing strings | Complete | None |

## B. System Extension Integration (20%)

| Requirement | Implementation | File(s) | Verification | Status | Remaining risk |
| --- | --- | --- | --- | --- | --- |
| 2+ working extensions | WidgetKit extension + Share Extension | `MoveProofWidget/`, `MoveProofShareExtension/` | Both build and are embedded in `MoveProof.app/PlugIns/` | Complete | None |
| Extensions correctly configured | Correct `NSExtensionPointIdentifier`, principal class, activation rule | `*/Info.plist` | Read back from the **built** `.appex` bundles: `com.apple.share-services` + image/file activation rule; `com.apple.widgetkit-extension` | Complete | None |
| App Group works end-to-end | One identifier, three targets, three separated directories | `MoveProofShared/AppGroup.swift` | Container `group.com.krischuang.MoveProof` confirmed created on disk in the simulator; entitlement confirmed present in all three built binaries | Complete | On a **device** the App Group must be registered against a Team. See README "Setup". |
| Widget consumes App Group data | `InspectionSnapshotStore` reads `Widget/snapshot.json` | `InspectionSnapshot.swift`, `InspectionProgressProvider.swift` | `testASnapshotWrittenByTheAppIsReadableByTheWidget` | Complete | None |
| Widget updates after a data change | `WidgetSnapshotPublisher` writes then calls `WidgetCenter.reloadTimelines(ofKind:)` | `WidgetSnapshotPublisher.swift` | Ran the workflow test on the named simulator, then read the container: `snapshot.json` contained `areasTotal: 8`, `daysUntilConditionReportDue: 7`, `hasActiveTenancy: true`, i.e. it changed from the empty state in response to app activity. `testReviewingProgressRepublishesTheSnapshot…` covers the call | Complete | The `reloadTimelines` call itself is asserted via the publisher protocol, not observed in WidgetKit. |
| Two widget families | `.systemSmall`, `.systemMedium` | `InspectionProgressWidget.swift`, `InspectionWidgetViews.swift` | Both rendered with `ImageRenderer` at 170×170 and 364×170 and asserted non-blank, including a stress case (three-digit counts, overdue deadline) | Complete | None |
| Widget never shows placeholder when data exists | Provider falls back to a genuine "No property yet" state; sample data is used only when `context.isPreview` | `InspectionProgressProvider.swift` | `testBothFamiliesRenderTheFirstRunStateWithoutATenancy` | Complete | None |
| Widget placed on the Home Screen in both families | n/a | n/a | **Not automated**, because SpringBoard's widget gallery could not be driven reliably and the attempt was removed rather than left as a flaky test. **Checked by hand instead:** both the small and the medium family were added to the Home Screen, each displayed the expected MoveProof data, and a change made in the app was reflected by the widget once the shared snapshot had been refreshed. No problems were found. | Complete | Covered by a manual check rather than by an automated one. |
| Share Extension receives content | `SharedItemCollector` filters attachments, picks the concrete UTI, copies into the inbox | `MoveProofShared/SharedItemCollector.swift` | 13 tests against real `NSItemProvider`s and the real App Group inbox, asserting bytes arrive unchanged | Complete | None |
| Share Extension stores into App Group | `SharedEvidenceInbox.store(...)` writes file + JSON sidecar | `SharedEvidenceInbox.swift` | `testSavingWritesTheFileAndItsMetadataIntoTheAppGroupInbox` | Complete | None |
| Main app processes shared evidence | `ImportSharedEvidenceUseCase` + Shared items inbox screen | `ImportSharedEvidenceUseCase.swift`, `SharedEvidenceInboxView.swift` | 10 tests, including duplicate rejection, unsupported content, missing file, and file rollback on save failure | Complete | None |
| Share Extension dismisses correctly | `completeRequest(returningItems:)` on both exit paths | `ShareViewController.swift` | `ShareExtensionUITests` checks the extension's Save button no longer exists after saving, so the sheet really did go away, with Photos back in front | Complete | None |
| Extension does not crash | n/a | n/a | One real crash was found and fixed: `SharedItemCollector` as an `@Observable @MainActor` class aborted in Swift's isolated-deinit path. It is now a value type with no deinit. | Complete | None |
| Appears in the real iOS share sheet | Activation rule claims images and files | `MoveProofShareExtension/Info.plist` | `ShareExtensionUITests` **passed**: from Photos, Share lists **MoveProof**; tapping it presents the extension, which saves and dismisses itself; the main app then finds the item in its Shared tab and import files it into the evidence library. Screenshots captured at each stage. | Complete | None |

## C. Database & Repository (20%)

| Requirement | Implementation | File(s) | Verification | Status | Remaining risk |
| --- | --- | --- | --- | --- | --- |
| Core Data used | `NSPersistentContainer`, one shared `NSManagedObjectModel` | `InspectionStore.swift` | App launches and persists; repository tests run against the real stack | Complete | None |
| Minimum 2 related entities | **4** entities, 3 relationships | `MoveProof.xcdatamodeld` | `testATenancyAndItsRoomsSurviveARoundTripThroughTheStore` | Complete | None |
| Meaningful, domain-driven schema | Tenancy → InspectionArea → ConditionItem → EvidenceItem; binaries kept out of the store | `MoveProof.xcdatamodeld`, `AppGroupEvidenceFileStore.swift` | Schema matches the structure of a condition report | Complete | None |
| Deliberate delete rules | Cascade where the child is meaningless alone; **nullify** on `ConditionItem → evidence` so deleting a room never destroys photos | `MoveProof.xcdatamodeld` | `testDeletingATenancyCascadesToItsRoomsChecklistsAndEvidence`, `testDeletingARoomKeepsTheTenantsEvidenceInTheLibrary` | Complete | None |
| Meaningful predicate query | `fetchConditionItemsMissingSupportingDetail(forTenancy:)`: compound, traverses two relationships, aggregates a third (`evidence.@count == 0`) | `CoreDataInspectionRepository.swift` | `testTheUndocumentedDamageQueryFindsOnlyDamageWithNoNoteAndNoEvidence`, `testTheUndocumentedDamageQueryIsScopedToOneProperty` | Complete | None |
| More than one real query | 5 predicate queries, none relying on fetch-all-and-filter | `CoreData*Repository.swift` | Each covered by a repository test. Four are called from app code; `fetchUnassignedEvidence` is tested but the evidence library filters its already-loaded rows in memory | Complete | None |
| Repository abstraction | 5 protocols, all in domain value types | `Data/Repositories/Repositories.swift` | Mocks substitute cleanly in every use case test | Complete | None |
| Repository protocol (not just a class) | `TenancyRepository`, `InspectionRepository`, `EvidenceRepository`, `EvidenceFileStore`, `InspectionSnapshotPublishing` | ibid. | `AppEnvironment` stores protocol types, not concrete ones | Complete | None |
| No direct Core Data from View/ViewModel | Views and view models never import CoreData | `MoveProof/Features/**` | `grep -rn "import CoreData\|NSManagedObjectContext\|NSFetchRequest" MoveProof/Features/` returns **no matches** | Complete | None |
| Core Data model loaded once | Shared static `NSManagedObjectModel` | `InspectionStore.swift` | Fixed a real defect: with two containers alive, Core Data logged "Failed to find a unique match for an NSEntityDescription". Warning is gone from the test log. | Complete | None |

## D. Domain Architecture (20%)

| Requirement | Implementation | File(s) | Verification | Status | Remaining risk |
| --- | --- | --- | --- | --- | --- |
| Semantic domain models | `Tenancy`, `InspectionArea`, `ConditionItem`, `EvidenceItem`, `InspectionProgress`, `ConditionState`, `EvidenceKind`, `EvidenceSource` | `Domain/Models/` | No `Item`, `Record`, `Manager` or `DataModel` anywhere | Complete | None |
| MVVM | 8 screens, each with its own `@Observable` view model | `Features/**` | View models hold no Core Data and no UI types | Complete | None |
| Use Case layer | 13 use cases | `UseCases/` | All thirteen are exercised by tests | Complete | None |
| Minimum 3 Use Case **structs** | All thirteen are `struct` | ibid. | `grep -n "^struct.*UseCase" MoveProof/UseCases/*.swift` returns 13 | Complete | None |
| Real business rule in each | See the table in README | ibid. | Every rule has at least one passing test and at least one failing-path test | Complete | None |
| Typed domain-specific errors | 8 error enums, all `Equatable`, including `EvidenceCaptureError` and `EvidenceFilingError` | `Domain/Errors/DomainErrors.swift` | Tests assert on specific cases with associated values, not just "some error" | Complete | None |
| Human-centred messages | `TenantFacingError` requires `whatHappened` + `whatToDoNext` | `Domain/Errors/TenantFacingError.swift` | Tests assert on the tenant-facing text; the workflow UI test asserts the exact strings on screen | Complete | None |
| No generic error strings | Non-domain failures wrapped in `UnexpectedFailure`; technical detail goes to `AppLog` | `TenantMessage.swift`, `AppLog.swift` | No "Save failed" / "Invalid input" / "Unknown error" in any user-facing string | Complete | None |
| Rules not duplicated in the UI | Views may prompt, but only use cases refuse | `ConditionItemDetailView.swift` + `RecordConditionEvidenceUseCase.swift` | Reviewed; the view's prompt and the use case's refusal come from the same rule | Complete | None |
| No repository writes in ViewModels | Every persistent mutation goes through a use case | `Features/**` | `grep -rn "Repository.save(\|Repository.delete(\|Repository.createAreas(" MoveProof/Features/` returns **no matches** | Complete | None |
| One implementation per shared rule | `TenancyDetailsRules` serves both the start and the update use case | `Domain/Rules/TenancyDetailsRules.swift` | `UpdateTenancyDetailsTests` asserts both paths produce the same refusal | Complete | None |
| Widget reloads after a successful write | One call site: `MoveProofModel.dataChanged()` → `refreshPublishedSnapshot()` | `App/MoveProofModel.swift` | `WidgetRefreshAfterChangeTests`, including the failure path that leaves the previous snapshot intact | Complete | None |

## E. Code Quality, Testing & Git (15%)

| Requirement | Implementation | Verification | Status | Remaining risk |
| --- | --- | --- | --- | --- |
| App is functional | 8 screens, full workflow | End-to-end UI test covering the first-run state, setting up a property, the dashboard reflecting it, rooms being seeded, damage refused with its exact wording, and sign-off refused | Complete | The UI test no longer drives the note field or photo picker; those rules are covered in the unit target instead. Reason recorded below. |
| Minimum 5 unit tests | **148** | `Executed 148 tests, with 0 failures` | Complete | None |
| Test distribution | 13 share-extension, 12 repository, 11 record-condition, 10 shared-import, 9 widget, 9 start-tenancy, 9 review-progress, 9 complete-area | `grep -rc 'func test' MoveProofTests/` | Complete | None |
| Mock repositories used | 6 mocks | All use case tests run with zero Core Data and zero disk I/O | Complete | None |
| Happy path covered | e.g. `testARoomCanBeSignedOffOnceEveryRequiredItemIsReviewed` | Passing | Complete | None |
| Boundary cases covered | Backdating limit exactly on/over; deadline on move-in day; empty room; optional items; whitespace-only notes; zero rooms | Passing | Complete | None |
| Error cases covered | Every domain error case has a test | Passing | Complete | None |
| Tests named as domain scenarios | e.g. `testDamagedConditionWithNeitherNoteNorPhotoIsRejected` | Reviewed | Complete | None |
| No trivial filler tests | Each asserts a behaviour, not a getter | Reviewed | Complete | None |
| Stable `main` | Every merge is a verified feature branch | `git log --graph` | Complete | None |
| Feature branch workflow | 8 branches, all merged `--no-ff` | `git log --graph --oneline` | Complete | None |
| Conventional Commits | `feat:`, `fix:`, `test:`, `docs:`, `chore:`, `refactor:`, `merge:` | `git log --oneline` | Complete | None |
| No AI/Co-Authored-By attribution | n/a | `git log --format='%B' \| grep -iE "co-authored\|claude\|anthropic\|generated"` returns no matches | Complete | None |
| Git author unchanged | `krischuang <kris.kh.chuang@gmail.com>` | `git log --format='%an <%ae>' \| sort -u` | Complete | None |
| No secrets / derived files committed | `.gitignore` covers DerivedData, `xcuserdata/`, provisioning profiles, certificates | `git ls-files` reviewed | Complete | None |
| Complete README | Overview, problem, stakeholder, architecture, schema, extensions, setup, build, test, verification, Git workflow, attribution | `README.md` | Complete | None |
| No unnecessary dependencies | Zero third-party packages | No `Package.resolved`, no Podfile | Complete | None |

## F. Reflective Report (5%)

| Requirement | Implementation | Verification | Status | Remaining risk |
| --- | --- | --- | --- | --- |
| 700 to 900 words | 876 words of prose in the Word report | Counted programmatically from the report, excluding headings and references | Complete | The Markdown draft's Section 4 runs longer, because it keeps working material (*What I would do differently*) that the report does not carry. Recount after any further edit. |
| Not a feature list | Organised around decisions and their costs | Reviewed | Complete | None |
| Design reasoning | Why this problem, why narrowed to the undocumented-damage case | §4 | Complete | None |
| Database reasoning | Core Data choice, binaries out of the store, delete rules | §4 | Complete | None |
| Extension reasoning | Why each extension, and where the Share Extension's boundary was drawn | §4 | Complete | None |
| Architecture trade-off | **Widget usefulness vs privacy**, which matches the implementation exactly and and is pinned by a test | §4, `testTheWidgetSnapshotCarriesCountsButNotThePropertyAddress` | Complete | None |
| Accurate AI-use description | Names Claude Code as the main AI-assisted development tool, what it was used for, and how its output was checked, including a suggested delete rule that the Core Data model showed to be wrong | §4 "AI usage" | Confirmed by the author | Complete | None |
| No fabricated personal reflection | Every experience-dependent passage is either confirmed by the author or still marked | §4 throughout | Complete | One **[AUTHOR TO REVIEW]** marker remains in the Markdown draft, under *What I would do differently*. The Word report does not carry that section. |

---

## Note on the walkthrough UI test's scope

It asserts navigation and both on-screen refusals, but does not type into the note
field or use the photo picker. A multiline SwiftUI `TextField(axis: .vertical)` reports
a degenerate frame to XCUITest, so tapping it does not focus it and the button beneath
it never becomes hittable. Four different workarounds were tried and each traded one
failure for another, so the test was scoped to what it can assert reliably rather than
left flaky.

Nothing lost coverage as a result: *damage plus a note is accepted* and *sign-off
succeeds once every required item is reviewed* are asserted in
`RecordConditionEvidenceTests` and `CompleteInspectionAreaTests` against mock
repositories.

## Outstanding items before submission

1. ~~Render `docs/architecture.mmd`~~ Done: `docs/architecture.png`, rendered with
   `mermaid-cli` using `docs/mermaid-config.json`.
2. ~~Personalise Section 4~~ Done, except the **[AUTHOR TO REVIEW]** marker under
   *What I would do differently* in the Markdown draft.
3. ~~Manually confirm the widget on the Home Screen~~ Done: both families added, expected
   data shown, refresh reflected, no problems found.
4. ~~Add the human-cost detail in Section 1~~ Done.
5. **Export the final PDF** from the reviewed Word draft. Not done yet, and deliberately
   left to the author.

## Status note: test counts and the cross-app test

The **148** figure quoted above is the `MoveProofTests` target alone. The two UI test
classes (`MoveProofWalkthroughUITests` and `ShareExtensionUITests`) are counted and
reported separately because they are slower and depend on simulator state.

`ShareExtensionUITests` crosses four processes (MoveProof, Photos, the share sheet, the
extension, then MoveProof again) and **passed on a clean `iPhone 17` simulator** with
`-parallel-testing-enabled NO`, with screenshots captured at each stage. That run is the
evidence for the "appears in the real share sheet" row above.

That test depends on simulator state it cannot control: photos must exist in the
library, and Photos' grid does not respond to element-relative taps. So it is **skipped
by default in the shared scheme** and run explicitly with `-only-testing:`. That is a
a configuration choice made on purpose and recorded here, not hidden: `xcodebuild test`
should be trustworthy, and a test that depends on the state of another app is not a
sound thing to gate it on.

Nothing is lost by that: the extension's own logic is covered deterministically by
`SharedItemCollectorTests`, and the import rules by `ImportSharedEvidenceTests`, both in
the unit target.

The project also now ships a **shared scheme** (`xcshareddata/xcschemes/MoveProof.xcscheme`).
Previously the only scheme lived in `xcuserdata/`, which is gitignored, so a fresh clone
would have had Xcode auto-generate one.

The one thing still not automated is placing the widget on the Home Screen. Driving
SpringBoard's widget gallery proved unreliable, so that attempt was removed rather than
left as a flaky test. It has been checked by hand instead, in both families, and the
result is recorded in the table above.
