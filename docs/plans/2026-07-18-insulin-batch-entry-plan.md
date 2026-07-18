# Insulin Batch Entry — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**User feedback (verbatim, source of truth for intent):** "When we add insulin, I add one type, say, correction bolus, and then I want to add another insulin type immediately. After I add the first entry, the whole model closes again and slides down. I want to maybe create another one before I confirm my insulin intake. It might be that I create a correction bolus, and then I also want to log a snack bolus."

**Goal:** The Add Insulin sheet supports staging multiple insulin entries (e.g. a correction bolus AND a snack bolus) and committing them all with one CONFIRM. Nothing is logged until confirm. The common single-entry flow stays one-tap: fill form → CONFIRM.

**Architecture:** The single-entry constraint is entirely view-layer — `AddInsulinView.save()` (`App/Views/AddViews/AddInsulinView.swift:197-202`) fires one callback then `dismiss()`es. Everything below already supports batches: `.addInsulinDelivery(insulinDeliveryValues: [InsulinDelivery])` (`Library/DirectAction.swift:12`), reducer `append(contentsOf:)` (`Library/DirectReducer.swift:29-34`), one-transaction batch insert (`App/Modules/DataStore/InsulinDeliveryStore.swift:170-189`), and all downstream middlewares (AppleHealth, Nightscout, IOB, MissedBolus) key off the same array action. **No changes below the view layer.** Pattern precedent: the food staging plate (`FoodPhotoAnalysisView.swift` — `stagedItems` @State, per-row remove, single terminal commit).

**Tech Stack:** SwiftUI, Swift Testing (`@Test`/`#expect`).

## Global Constraints

- **Safety — IOB stacking warning must see staged entries.** `currentIOB` (`AddInsulinView.swift:19-32`) currently reads only committed `store.state.iobDeliveries`. In a batch session, a staged snack bolus MUST be counted when the user then selects correction bolus, or the stacking warning under-reports. Fold staged deliveries into the `deliveries:` argument of `computeIOB`.
- No dosing advice anywhere — this is logging UX only. The passive `referenceRatioLine` stays exactly as is (display-only).
- Single-entry flow must not gain taps: fill form → CONFIRM commits the current form directly (no forced staging step).
- `.interactiveDismissDisabled()` stays; Cancel with staged entries must confirm before discarding.
- DOS design system: `DOSTypography`, `AmberTheme`, `DOSSpacing`, `.dosCard`/`.dosHeader` where applicable; no raw hex, no `.font(.system(` (StyleGuardTests enforce).
- User-visible change → `CHANGELOG.md` `[Unreleased]` entry required.
- New test files need manual pbxproj registration (`DOSBTSTests` group + `PBXSourcesBuildPhase`) — tests are NOT auto-synced.

---

### Task 1: Pure commit-set + staged-IOB helpers with tests

**Files:**
- Create: `Library/Content/InsulinBatchBuilder.swift` (precedent for pure logic in Library/Content: `SparklineBuilder`, `RatioEstimator`)
- Create test: `DOSBTSTests/InsulinBatchBuilderTests.swift` (+ pbxproj registration)

**Interfaces:**

```swift
enum InsulinBatchBuilder {
    /// The full set to commit on CONFIRM: staged entries plus the current
    /// form if it holds a valid (units > 0) entry the user never staged.
    static func commitSet(
        staged: [InsulinDelivery],
        currentUnits: Double?,
        currentType: InsulinType,
        starts: Date,
        ends: Date
    ) -> [InsulinDelivery]

    /// Deliveries the IOB stacking warning should consider: committed + staged.
    static func iobInputs(
        committed: [InsulinDelivery],
        staged: [InsulinDelivery]
    ) -> [InsulinDelivery]
}
```

- [ ] **Step 1 (failing tests first):** `commitSet` — staged only (form empty) → staged; form only (nothing staged) → one entry; staged + valid form → staged + form entry appended; staged + zero/nil units form → staged only; empty everything → `[]`. Basal form entry keeps its own `ends`; non-basal entries get `ends == starts` (mirror `save()`'s `insulinType == .basal ? ends : starts` rule, `AddInsulinView.swift:199`). `iobInputs` — concatenation, order stable (committed first).
- [ ] **Step 2:** Implement; run `-only-testing:DOSBTSTests/InsulinBatchBuilderTests` green.

### Task 2: Rework `AddInsulinView` for staging

**Files:**
- Modify: `App/Views/AddViews/AddInsulinView.swift`

- [ ] **Step 1:** Add `@State private var staged: [InsulinDelivery] = []`.
- [ ] **Step 2:** Below the form rows, add a **STAGE ENTRY** ghost/secondary button (visible whenever `(units ?? 0) > 0`): constructs an `InsulinDelivery(id: UUID(), starts:, ends:, units:, type:)` from the current form (same ends rule as `save()`), appends to `staged`, then clears `units` only — type and time selections persist for the next entry.
- [ ] **Step 3:** Add a STAGED section (shown when `!staged.isEmpty`): header via `.dosHeader()` (e.g. `STAGED · 2`), one row per entry — `type.shortLabel` + units (`asInsulinUnits()`) + `HH:mm` time — with a ✕ remove button per row (in-place editing of a staged row is **out of scope** for V1; remove + re-enter).
- [ ] **Step 4:** Toolbar trailing button: label becomes **CONFIRM** (append the count when the commit set holds > 1, e.g. `CONFIRM 2`); action computes `InsulinBatchBuilder.commitSet(...)`, guards non-empty, calls the (new, Task 3) callback once with the array, then `dismiss()`. Disabled iff the commit set is empty.
- [ ] **Step 5:** Cancel: when `staged.isEmpty` behave as today; otherwise show a `confirmationDialog` ("Discard N staged entries?") before dismissing.
- [ ] **Step 6 (safety):** `currentIOB` uses `InsulinBatchBuilder.iobInputs(committed: store.state.iobDeliveries, staged: staged)` as the `deliveries:` argument. The warning display condition (`insulinType == .correctionBolus, currentIOB > 0.05`, line 56) is unchanged.
- [ ] **Step 7:** Update `AddInsulinView_Previews` for the new callback signature.

### Task 3: Batch callback in `RootSheetContent`

**Files:**
- Modify: `App/Views/RootSheetContent.swift:22-36`

- [ ] Change the callback to `addCallback: (_ deliveries: [InsulinDelivery]) -> Void`. The `.insulin` case dispatches **once**: `store.dispatch(.addInsulinDelivery(insulinDeliveryValues: deliveries))`; flash `addedHighlighter.flash(...)` for each id; one `hapticNotification(.success)`; stage the toast (Task 4).

### Task 4: Batch-aware logged toast

**Files:**
- Modify: `App/Views/SharedViews/LoggedEntryToast.swift`
- Modify: the `ContentView` UNDO switch for the new case
- Extend test: the existing toast/undo tests if present, else add cases to `DOSBTSTests` where LoggedEntry is covered

- [ ] Add `case insulinBatch([InsulinDelivery])` to `LoggedEntry` (`LoggedEntryToast.swift:19-27`). Label: `"Logged: N insulin entries"` (keep the existing `.insulin` single-entry label for N == 1 — RootSheetContent stages `.insulin(d)` when the batch has one element, `.insulinBatch(ds)` otherwise). UNDO for the batch dispatches `.deleteInsulinDelivery` per element (mirror how `.insulin` undo deletes one).

### Task 5: CHANGELOG + full verification

- [ ] `CHANGELOG.md` `[Unreleased]` → `### Added`: `- Add Insulin sheet can stage multiple entries (e.g. correction + snack bolus) and log them with one CONFIRM; the IOB stacking warning accounts for staged entries`
- [ ] Full suite: `xcodebuild test -project DOSBTS.xcodeproj -scheme DOSBTSApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -configuration Debug 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)" | tail` → SUCCEEDED
- [ ] Both targets build (app + `DOSBTSWidget` scheme).

## Verification (end-to-end, simulator + VirtualConnection)

1. INSULIN → enter 2U CORR → STAGE ENTRY → enter 3U SNACK → CONFIRM 2 → sheet closes once, both entries on the chart/list, toast "Logged: 2 insulin entries", UNDO removes both.
2. Single entry: enter 4U MEAL → CONFIRM (no staging) → identical to today's behavior.
3. Safety: stage a 5U SNACK, switch type to CORR → ACTIVE IOB warning includes the staged 5U.
4. Cancel with 2 staged → discard confirmation appears; confirming discards, nothing logged.
