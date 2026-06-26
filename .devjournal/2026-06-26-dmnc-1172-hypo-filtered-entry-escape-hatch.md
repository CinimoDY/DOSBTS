# DMNC-1172 — LOG OTHER FOOD escape hatch (hypo-filtered entry sheet)

**Date:** 2026-06-26

Implements the DMNC-1028 plan (`docs/plans/2026-06-25-dmnc-1028-plan.md`).

## What changed

During a treatment cycle the persistent bottom-bar **MEAL** button routes to the
hypo-filtered food entry sheet (`UnifiedFoodEntryView(filterToHypoTreatments: true)`,
R8). In that mode the favourites list is filtered to hypo treatments, recents can
be empty, and the full actions section (MANUAL/SCAN/PHOTO/ASK AI) is suppressed. A
user who deletes both seeded hypo favourites *and* has zero recents had **no** path
to log carbs mid-hypo — a genuine safety dead-end flagged in PR #52's known residuals.

Added a persistent **LOG OTHER FOOD** manual-entry escape row, always present in
filtered mode, that pushes the existing `AddMealView` and dispatches the existing
`.addMealEntry`. Because `TreatmentCycleMiddleware` is purely glucose-driven (it
reacts to `.logHypoTreatment` and `.addSensorGlucose`, never to carb/meal data), a
plain manual meal entry treats the hypo correctly — the countdown/recheck proceeds
on the next glucose reading with no extra wiring.

### Files modified

| File | Change |
|---|---|
| `App/Views/AddViews/UnifiedFoodEntryView.swift` | Added pure `HypoFilteredEntryModel` (mirrors `GlucoseStatusBarModel`); `entryModel` computed; `escapeSection`; DRY `manualEntryLink(icon:title:)` helper now shared by the MANUAL row and the new escape row; filtered List body reads the model. |
| `DOSBTSTests/HypoFilteredEntryTests.swift` | New — pins the no-dead-end model contract (3 tests). |
| `DOSBTS.xcodeproj/project.pbxproj` | 4 entries wiring the new (non-auto-synced) test file (ID `…2300A00023`). |
| `CHANGELOG.md` | `[Unreleased]` Added entry. |

## Why this approach

- **Option A over Option B (KTD-1):** a single low-emphasis manual-entry row, not
  un-suppressing the full actions section. PHOTO/ASK AI are slow, network/consent-gated
  flows deliberately kept out of the hypo flow; re-adding them re-clutters the sheet.
- **Always-on in filtered mode (KTD-2):** `showsEscapeRow == filterToHypoTreatments`.
  Simpler than coupling to favourite/recent counts and removes the dead-end in every
  filtered state. Row sits last, below QUICK and RECENT.
- **Pure model pins the invariant (KTD-4):** the no-dead-end guarantee is a
  regression-protected unit test on the model, not view-only behaviour.

## Plan deviations

- The plan's reserved test-wiring ID `…2200A00022` was already taken by a newly-added
  `DOSTabBarAppearanceTests.swift` (landed after the plan was written); used the next
  free ID `…2300A00023`.

## Review fixes (xhigh code-review)

- **a11y:** the DRY extraction had hardcoded `.accessibilityLabel("Log a meal manually
  by typing carbs")`, which silently changed the existing MANUAL row's VoiceOver
  announcement and made both rows announce identically. Switched to
  `.accessibilityHint(...)` so the visible label ("MANUAL" / "LOG OTHER FOOD") stays
  the VoiceOver label — distinguishable, no regression.
- **Perf:** bound `entryModel` once per `body` render instead of recomputing (it
  filters favourites) at two call sites.
- **CHANGELOG:** dropped `**bold**` markdown — the in-app "What's New" renders entry
  text verbatim, so asterisks would show literally.

Known pre-existing quirk left out of scope: in filtered mode a search matching zero
hypo favourites shows the favourites section header with no chips (rather than a "no
matches" state). The plan committed to behaviour parity on that branch; not a dead-end
since the escape row still renders.

## Result

`** BUILD SUCCEEDED **`; full test suite green including the 3 new
`HypoFilteredEntryModelTests`.
