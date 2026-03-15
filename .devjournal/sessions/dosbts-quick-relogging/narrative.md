# Food Logging Quick Re-logging (Phase 4)

**Date:** 2026-03-15
**Duration:** ~6 hours
**Builds deployed:** 21, 22
**Linear:** DMNC-532

## The Problem

Food logging in DOSBTS required 30-60 seconds per entry — even for foods eaten daily like dextrose for hypo treatment. There was no way to quickly re-log a previous meal, pin a favorite, or search through past entries. Research shows people eat the same ~15-20 meals repeatedly, so making re-logging instant (3-5 seconds) matters more than any AI feature (15-20 seconds).

## Research Phase: How Do the Best Apps Do It?

Researched YAZIO, MyFitnessPal, Cronometer, MacroFactor, SnapCalorie, and academic studies. Key findings:

- **Speed hierarchy:** One-tap favorite (~3s) > barcode scan (~15s) > AI photo (~15-20s) > database search (~20-30s) > manual entry (~45-60s)
- **MacroFactor** has the best favorites bar — pre-set portions, one-tap re-log
- **YAZIO's biggest mistake:** "Meal Tips" popup after every log — universally hated
- **UCL/Loughborough 2025 study** (13,799 posts): manual entry burden is the #1 reason users quit
- **DOSBTS's unique advantage:** glucose correlation — immediate feedback that generic calorie counters can't provide

## Architecture Decisions

1. **Separate FavoriteFood GRDB table** (not a flag on MealEntry) — favorites are templates, not events. Editing a favorite must not modify historical log entries.
2. **Recents derived from MealEntry** via COLLATE NOCASE subquery — no separate table needed.
3. **No meal categories** — flat timeline. Time-of-day makes categories obvious.
4. **Staging plate deferred** to Phase 5 — YAGNI. AI photo already handles complex meals.
5. **All logging paths dispatch `.addMealEntry`** — guarantees HealthKit export via existing middleware.

## Implementation

### Step 1: Foundation (FavoriteFood + Middleware)
- `FavoriteFood` model matching MealEntry pattern (CustomStringConvertible, Codable, Identifiable, two-init, Equatable by id)
- `FavoriteStore` middleware with CRUD, recents query, hypo treatment seeding
- 8 new Redux actions following add/delete/load/set convention
- COLLATE NOCASE composite index on MealEntry.mealDescription
- mealDescription trimming at init time (prevents whitespace dedup bugs)
- Atomic default seeding (Dextrose tabs 15g, Juice box 25g)

### Step 2: Unified Food Entry View
- Single MEAL button replaces MANUAL + PHOTO in QuickActionsSection
- Favorites bar (horizontal ScrollView with HStack, hypo treatments in CGA green)
- Recents list (vertical List, most recent first)
- Type-ahead search (local computed property, not Redux dispatch per keystroke)
- Camera and manual entry accessible from bottom actions

### Step 3: Interactions
- One-tap logging with toast confirmation (3s undo window)
- "Log again" right-swipe (.swipeActions edge: .leading) on meal list
- "Add to Favorites" context menu (long-press) on meal list and recents
- Favorites management: reorder (.onMove), edit, delete (.onDelete)

## Code Review: 7 Findings

Reviewed with 6 specialized agents in parallel. Results:

| # | Finding | Severity | Fix |
|---|---------|----------|-----|
| 1 | **Undo toast UUID mismatch** — view created local MealEntry with different UUID than middleware | P1 | View creates MealEntry directly, middleware only updates lastUsed |
| 2 | **Recents query needs composite index** — single index insufficient for subquery JOIN | P2 | Composite index (mealDescription COLLATE NOCASE, timestamp DESC) |
| 3 | **moveFavorites N individual dispatches** — each reorder = separate GRDB write + reload | P2 | New .reorderFavoriteFoods batch action, single transaction |
| 4 | **EditFavoriteView missing validation** — no empty guard, no length/range limits | P2 | Added same validation as AddMealView |
| 5 | **Toast Timer RunLoop** — Timer.scheduledTimer won't fire during scroll | P2 | DispatchWorkItem + asyncAfter |
| 6 | **Duplicated conversion logic** — MealEntry↔FavoriteFood in 4 places | P3 | Factory methods: FavoriteFood.from(mealEntry:) + .toMealEntry() |
| 7 | **Cross-middleware comment missing** — .addMealEntry triggers 2 middlewares | P3 | Added clarifying comment |

### Post-Review Bug Fix
- **Sheet presentation collision** — two `.sheet` modifiers in same HStack caused wrong sheet to present (MANUAL appeared when tapping PHOTO). Fixed by placing sheets at different view hierarchy levels.

## Key Learnings

1. **SwiftUI sheet collision on iOS 15:** Two `.sheet` modifiers on sibling views in the same container can present the wrong sheet. Place them at different hierarchy levels (e.g., one on List, one on NavigationView).

2. **Redux undo pattern:** When a middleware creates an object (with new UUID), the view can't know the UUID for undo. Solution: have the view create the object and dispatch it directly, so the same UUID is used for both persistence and undo.

3. **GRDB COLLATE NOCASE:** The index collation must match the query collation. A plain index on `mealDescription` won't accelerate `GROUP BY mealDescription COLLATE NOCASE`.

4. **Separate template from event:** FavoriteFood (template) vs MealEntry (event) is the right separation. Adding `isFavorite` to MealEntry would conflate templates with historical records.

5. **Batch Redux actions for reorder:** Dispatching N individual updates for a drag-to-reorder triggers N writes + N reloads. A single batch action with one transaction is correct.

## What's Next

From the brainstorm (`docs/brainstorms/2026-03-15-food-logging-overhaul-brainstorm.md`):
- **Phase 5:** Food database search + barcode scanning (Open Food Facts + USDA) + staging plate
- **Phase 6:** Natural language input (Claude NL parsing, BYOK)
- **Phase 7:** Smart suggestions + meal templates
- **Phase 8:** Glucose correlation analysis

## Stats

- **New files:** 3 (FavoriteFood.swift, FavoriteStore.swift, UnifiedFoodEntryView.swift)
- **Modified files:** 10
- **Lines added:** ~1,005
- **Actions added:** 9
- **Review agents:** 6 (parallel)
- **Review findings:** 7 (all fixed)
- **TestFlight builds:** 2 (21, 22)
