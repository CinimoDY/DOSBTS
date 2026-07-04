# DMNC-1301 — Food Impact ranking screen (WP-N2)

## What changed

Surfaced `PersonalFood.avgDeltaMgDL` and `observationCount` (already computed by `MealImpactStore` but never displayed) in a new "FOOD IMPACT" pushed screen accessible from the Log tab.

## Files modified

- `Library/DirectState.swift` — added `scoredPersonalFoodValues: [PersonalFood]`
- `App/AppState.swift` — added `scoredPersonalFoodValues: [PersonalFood] = []`
- `Library/DirectAction.swift` — added `loadScoredPersonalFoods` and `setScoredPersonalFoods`
- `Library/DirectReducer.swift` — reducer case for `setScoredPersonalFoods`
- `App/Modules/DataStore/FoodCorrectionStore.swift` — new `getScoredPersonalFoods()` GRDB query (IS NOT NULL, sorted by avgDeltaMgDL DESC), middleware handling for `loadScoredPersonalFoods`, triggered on `.startup`, `.setAppState(.active)`, and `.saveMealWithCorrections`
- `App/Modules/MealImpact/MealImpactStore.swift` — added `loadScoredPersonalFoods` dispatch after `computePendingMealImpacts` completes (this is when PersonalFood scores are actually updated in the DB)
- `App/Views/Overview/MealOverlayLogic.swift` — extracted `mealImpactDeltaColor(delta:)` free function (thresholds: <30 → cgaGreen, 30–59 → amber, ≥60 → cgaRed) so both the chart overlay and the new screen share the same constants
- `App/Views/Lists/FoodImpactView.swift` — NEW: ranked list with `FoodImpactRow`, `DOSEmptyState` for fresh installs, footer caption
- `App/Views/ListsView.swift` — `NavigationLink` row to push `FoodImpactView`
- `DOSBTSTests/MealImpactTests.swift` — appended `FoodImpactDisplayModelTests` suite (13 tests)

## Key decisions

**Separate `scoredPersonalFoodValues` state** — the existing `personalFoodValues` is capped at 12 rows by `getPersonalFoods()` (designed for AI autocomplete context). Rather than removing that cap and changing AI behaviour, I added a dedicated `scoredPersonalFoodValues` property backed by `getScoredPersonalFoods()` which fetches all rows with `avgDeltaMgDL IS NOT NULL` sorted by score descending. This follows the 3-file GRDB pattern (no UserDefaults since it's a DB-sourced array).

**Delta tier color extracted** — the 30/60 mg/dL thresholds were only inline assertions in `MealImpactTests.swift`. Extracted to `mealImpactDeltaColor(delta:)` in `MealOverlayLogic.swift` so both the existing overlay and the new FoodImpactView reference one source of truth.

**Low confidence dimming** — rows with `observationCount < 3` render in `amberDark` (both name and delta) to signal unreliable averages, rather than being hidden (spec says "dimmed, not hidden").

**Trigger timing** — `loadScoredPersonalFoods` is dispatched from both `foodCorrectionStoreMiddleware` (covers load on activation and after new food entries) and `mealImpactStoreMiddleware` (covers the case where scores are updated when a MealImpact is computed after a glucose tick).
