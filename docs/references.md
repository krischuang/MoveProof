# References

Sources actually consulted while building MoveProof. Nothing here is cited that was
not read, and no claim is attributed to a source beyond what the source says.

MoveProof is an evidence capture and organisation tool. It does not give legal
advice and does not determine who is responsible for any damage. The sources below
are used to establish that the documentation problem exists and to justify specific
product decisions, most importantly the seven-day default deadline.

---

## Real-world evidence that the problem exists

### 1. Rental property condition reports (NSW Government)

- **Title:** Rental property condition reports
- **Organisation:** NSW Government (Housing and Construction)
- **URL:** https://www.nsw.gov.au/housing-and-construction/rules/rental-property-condition-reports
- **Accessed:** 21 September 2026

**What it supports:**

- That a tenant must return a completed copy of the condition report to the landlord
  or agent **within seven days of moving in**. The page states tenants must "return
  one completed copy to the landlord or agent within seven days of moving in."
- That photographs are recommended supporting evidence, and that they should be
  time-stamped. The page advises tenants to "take photos to go with the condition
  report - making sure to include time stamps to show when images were taken", and
  states that "The more detail, including time-stamped photographs, in a condition
  report, the less likely disputes will arise at the end of a tenancy."
- That the report is used as evidence in a dispute: "If there is a disagreement or
  dispute about missing items or damage, the condition report can be used as
  evidence."

**Where it is used in MoveProof:**

- `Tenancy.conditionReportWindowInDays = 7` and
  `Tenancy.defaultConditionReportDueDate(movingIn:)`, the seven-day default the app
  proposes, which the tenant can override.
- The deadline countdown on the dashboard and on both widget families.
- `TenancySetupViewModel.dueDateFootnote`, which explains the default to the tenant.

---

### 2. Starting a tenancy (Tenants' Union of NSW)

- **Title:** Starting a tenancy
- **Organisation:** Tenants' Union of NSW
- **Updated:** August 2025
- **URL:** https://www.tenants.org.au/factsheet-02-starting-a-tenancy
- **Accessed:** 21 September 2026

**What it supports:**

- That the landlord or agent must complete a condition report and give the tenant two
  copies when they move in, one to keep and one to return.
- That the report describes the condition of the premises and can be used as evidence
  if there is a disagreement about missing items or damage.
- That tenants are advised to take photographs at the start of the tenancy and store
  them in a safe place.

**Where it is used in MoveProof:**

- The room-by-room checklist structure, which follows the shape of a condition report
  rather than being a generic note-taking list.
- The premise that the tenant ends up holding evidence in several places at once
  (their own photos, the agent's report, email attachments), which is the
  fragmentation MoveProof's evidence library and shared-items inbox address.

---

## Apple documentation and platform guidance used

These were consulted while implementing the extensions and the persistence layer. No
sample code was copied verbatim; the APIs below were used as documented.

| Topic | Where it was used |
| --- | --- |
| `WidgetKit`: `TimelineProvider`, `StaticConfiguration`, `supportedFamilies`, `WidgetCenter.reloadTimelines(ofKind:)` | `MoveProofWidget/`, `WidgetSnapshotPublisher.swift` |
| Share extensions: `NSExtensionActivationRule`, `NSItemProvider`, `NSExtensionContext.completeRequest(returningItems:)` | `MoveProofShareExtension/` |
| App Groups: `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` | `MoveProofShared/AppGroup.swift` |
| Core Data: `NSPersistentContainer`, `NSPredicate` including aggregate (`@count`) and keypath traversal, relationship delete rules | `MoveProof/Data/` |
| SwiftUI: `@Observable`, `NavigationStack`, `ContentUnavailableView`, `PhotosPicker`, `ImageRenderer` | `MoveProof/Features/`, `MoveProofTests/Widget/` |

## Third-party dependencies

**None.** MoveProof uses only Apple frameworks. There are no Swift Package Manager
dependencies, no CocoaPods and no Carthage. This is a deliberate choice: the
assessment is about demonstrating platform integration, and a third-party UI or
persistence library would hide exactly the work being assessed.
