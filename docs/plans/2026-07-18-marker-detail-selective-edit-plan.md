# Marker Detail Sheet — Per-Entry Times, Swipe-Delete, Per-Row Edit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**User feedback (verbatim, source of truth for intent):** "When I click on the meal marker, I should be able to just swipe left on any entry to delete it. When I go to edit, I can only delete, and then it asks me to delete both. It deletes the meal and the sub-entry, and that's a bit weird. I should be able to more selectively delete or edit entries, single entries within the meal marker display." And (from a related complaint): "they don't have the times. When I try to edit, sometimes the time would be important."

**Goal:** In the chart marker-group detail sheet, every entry row shows its own logged time, swipe-left deletes just that entry, and tapping a meal/insulin row edits just that entry. The group-level "edit" button — whose delete path dispatches BOTH `.deleteMealEntry` and `.deleteInsulinDelivery` ("Delete Both") — is removed.

**Architecture (verified findings):**
- Every chip tap opens `EntryGroupListOverlay` (`App/Views/Overview/EntryGroupListOverlay.swift`) via `SheetCoordinator` case `.entryGroupReadOverlay`. Its body is a **`ScrollView` + `VStack`** (lines 46-60) with read-only `HStack` rows (107-132) — no per-entry time (only one header time, 92-94), no swipe, no per-row tap.
- The only mutation path is the header "edit" button (66-84) → `RootSheetContent.swift:110-112` → `sheets.dismissThenPresent(.combinedEntryEdit(group))` → `CombinedEntryEditView` (`App/Views/AddViews/CombinedEntryEditView.swift`), which hydrates at most one meal + one insulin (`hydrateFromGroup()` 84-121, silently dropping extras; exercise not editable) and whose `performDelete()` (347-355) dispatches BOTH delete actions — the "Delete Both" trap (label logic 333-341).
- `MealEntry` is a flat record — the "sub-entry" the user sees deleted alongside the meal is the co-located insulin delivery in the same group, not a child record. Whole-record delete actions already exist for every type: `.deleteMealEntry`, `.deleteInsulinDelivery`, `.deleteExerciseEntry` (`Library/DirectAction.swift:32-34`).
- Swipe-delete precedent: `MealItemRow` `.list` variant (`App/Views/SharedViews/MealItemRow.swift:87-104`), `InsulinDeliveryListView.swift` trailing swipeActions.

**Tech Stack:** SwiftUI, Swift Testing.

## Global Constraints

- `.swipeActions` only works on `List` rows — the overlay's rows region must convert from `ScrollView`/`VStack` to a `List` (`.listStyle(.plain)`, `.scrollContentBackground(.hidden)`, `listRowBackground(AmberTheme.dosBlack)`, separators styled to match the current `Divider().background(AmberTheme.borderSubtle)` look). The header and OK bar keep their current placement (header above the List or as a list section header; `okBar` stays in `safeAreaInset(edge: .bottom)`).
- **Never present a sheet from within a sheet** — per-row edit must route through `sheets.dismissThenPresent(...)` (the SheetCoordinator-mandated sequencing), exactly like the old header edit button did.
- Keep the `.combinedEntryEdit` sheet case and `CombinedEntryEditView` — still used by the Lists tab, and it becomes the single-entry editor here. With a single-marker group its label logic already yields "Delete Meal" / "Delete Insulin"; "Delete Both" simply becomes unreachable from this flow. Expected: **no changes** to `CombinedEntryEditView` (only touch it if single-entry hydration needs a nudge).
- Preserve existing row content: icons, primary text, sublines (IOB / impact / paired / confounders), value column, VoiceOver labels, and the `EntryGroupListOverlayTests`-pinned static `subline(for:...)` helper (extend, don't break).
- Deletion race handling already exists (`entryStub` nil fallbacks, lines 147-177) — keep it.
- DOS design system rules apply (no `.font(.system(`, tokens only — StyleGuardTests enforce).
- User-visible change → `CHANGELOG.md` `[Unreleased]` entry required. New test files need manual pbxproj registration.

---

### Task 1: Pure row-model helper + tests

**Files:**
- Modify: `App/Views/Overview/EntryGroupListOverlay.swift` (add static helpers alongside `subline`)
- Extend test: `DOSBTSTests/EntryGroupListOverlayTests.swift`

- [x] **Step 1 (failing tests first):** add static, unit-testable helpers and pin them:
  - `rowTime(for: EventMarker, insulin: InsulinDelivery?) -> String` — `HH:mm`; insulin rows use `delivery.starts`, others `marker.time` (reuse the existing `headerTimeFormatter`).
  - `isEditable(_ type: EventMarkerType) -> Bool` — true for `.meal/.bolus/.correction/.basal`, false for `.exercise` (the combined editor cannot edit exercise).
  - Delete-action mapping per type (meal → `.deleteMealEntry`, insulin types → `.deleteInsulinDelivery`, exercise → `.deleteExerciseEntry`) — expressible as a pure function returning an enum/`DirectAction` the tests can assert on.
- [x] **Step 2:** Implement; targeted test run green.

### Task 2: Overlay rework — List rows, times, swipe-delete, tap-to-edit

**Files:**
- Modify: `App/Views/Overview/EntryGroupListOverlay.swift`

- [x] **Step 1:** Replace `onEdit: () -> Void` with two callbacks:
  ```swift
  var onEditEntry: (EventMarker) -> Void
  var onDeleteEntry: (EventMarker) -> Void
  var onDismiss: () -> Void
  ```
  Delete the header "edit" button (66-84); the header keeps the time + "Logged" text.
- [x] **Step 2:** Local row state: `@State private var markers: [EventMarker]` seeded from `group.markers` (chronological). On delete: call `onDeleteEntry(marker)`, remove locally; when the last row goes, call `onDismiss()`.
- [x] **Step 3:** Convert the rows region to a `List` (see Global Constraints for styling). Each row:
  - shows its **own time** — `rowTime(...)` as a `DOSTypography.caption` under the value column (trailing VStack) or leading the subline; pick one placement and keep it consistent for all types;
  - `.swipeActions(edge: .trailing)` destructive DELETE on **every** row type;
  - meal/insulin rows: tappable (add a trailing chevron affordance, `contentShape(Rectangle())`, `onTapGesture { onEditEntry(marker) }`); exercise rows: not tappable, no chevron;
  - VoiceOver: include the time in `voiceOverLabel`, add `.isButton` trait only on tappable rows.

### Task 3: Wiring in `RootSheetContent`

**Files:**
- Modify: `App/Views/RootSheetContent.swift` (the `.entryGroupReadOverlay` construction, currently wiring `onEdit` at 110-112)

- [x] **Step 1:** `onEditEntry`: synthesize a single-marker group and route through the coordinator:
  ```swift
  let single = ConsolidatedMarkerGroup(id: "edit-\(marker.id)", time: marker.time, markers: [marker])
  sheets.dismissThenPresent(.combinedEntryEdit(single))
  ```
- [x] **Step 2:** `onDeleteEntry`: dispatch the mapped delete action with the resolved entity (look up by `marker.sourceID` in `store.state.mealEntryValues` / `insulinDeliveryValues` / `exerciseEntryValues`). Mirror the Lists-tab delete behavior per type: stage the undo toast where a `LoggedEntry` case exists (`.deletedInsulin`); meal/exercise deletes without an undo case just delete (adding `.deletedMeal` is optional polish, not required).
- [x] **Step 3:** Remove the now-dead `onEdit` wiring. Verify no other caller of the overlay passes `onEdit` (grep).

### Task 4: CHANGELOG + verification

- [x] `CHANGELOG.md` `[Unreleased]`: under `### Changed`: `- Chart marker detail sheet: every entry shows its logged time, swipe-left deletes a single entry, tap edits a single entry — the group-level edit with its "Delete Both" is gone`
- [x] Full suite green; both targets build.

## Verification (end-to-end, simulator + VirtualConnection)

1. Seed a meal + correction bolus + snack bolus in one 15-min window; tap the merged chip → detail sheet lists 3 rows, each with its own `HH:mm`.
2. Swipe left on the snack bolus → only it is deleted; the sheet still shows 2 rows; the chart chip total updates.
3. Tap the meal row → sheet swaps (dismissThenPresent, no nested sheet) to the editor showing ONLY the meal; its delete button reads "Delete Meal" — no "Delete Both" reachable anywhere.
4. Delete the last remaining row → sheet dismisses itself.
5. Exercise entry in a group: row shows time, swipe-deletes, is not tappable.
