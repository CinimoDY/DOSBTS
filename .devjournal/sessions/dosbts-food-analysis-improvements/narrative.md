# Food Analysis Improvements Session

**Date:** 2026-03-13
**Duration:** ~2 hours
**Builds deployed:** 14, 15, 16, 17, 18

## The Problem

The AI food photo analysis feature (shipped in Phase 3) had a critical bug: scanning would get stuck on "Analyzing meal photo..." and never return results. The user reported no progress feedback and suspected something was broken.

Additionally, the results view only showed carbs — all the other nutritional data (protein, fat, calories, fiber) returned by Claude was being discarded.

## Root Cause: Middleware Race Condition

The bug was a race condition in `ClaudeMiddleware.swift`. The flow was:

1. View dispatches `.setFoodAnalysisLoading(isLoading: true)` — reducer sets `foodAnalysisLoading = true`
2. View dispatches `.analyzeFood(imageData:)` — middleware receives it
3. Middleware guard checks `!state.foodAnalysisLoading` — **always false** because step 1 already set it
4. Guard fails → returns `Empty()` → API call never fires

The fix: removed `!state.foodAnalysisLoading` from the middleware guard. The view's loading state already prevents double-dispatch via the UI switching to the loading section.

## Changes Made

### 1. Bug Fix — Middleware Race Condition
- **File:** `ClaudeMiddleware.swift`
- Removed the `!state.foodAnalysisLoading` guard condition

### 2. Full Nutritional Breakdown
- **`MealEntry.swift`** — Added `proteinGrams`, `fatGrams`, `calories`, `fiberGrams` (all optional)
- **`DataStore.swift`** — Added new columns to GRDB `Columns` enum
- **`MealStore.swift`** — Added `DatabaseMigrator` to `ALTER TABLE` for existing databases
- **`NutritionEstimate.swift`** — Added computed `totalProteinG`, `totalFatG`, `totalFiberG` from items
- **`FoodPhotoAnalysisView.swift`** — Complete results redesign:
  - Editable macro rows for all nutrients (carbs/protein/fat/calories/fiber)
  - Per-item breakdown with macro tags showing C/P/F/kcal
  - Save passes all macros through to MealEntry
- **`MealEntryListView.swift`** — Shows protein/fat/calories alongside carbs in meal history

### 3. Progress Animation
- **`FoodPhotoAnalysisView.swift`** — Timer-driven phased messages:
  - "Identifying foods..." → "Estimating portions..." → "Calculating nutrition..." → "Finalizing results..."
  - DOS-style progress bar: `[===         ]`
  - Timer properly invalidated on dismiss/cancel

### 4. HealthKit Nutrition Export
- **`AppleHealthExport.swift`** — Added `proteinType`, `fatType`, `calorieType`, `fiberType` HKQuantityTypes
  - All added to `requiredPermissions` (triggers re-authorization for new types)
  - Replaced `addMealCarbs` with `addMealNutrition` — writes all available macros as separate `HKQuantitySample`s
  - Uses same sync identifier pattern for deduplication
  - Calories use `.kilocalorie()` unit; protein/fat/fiber use `.gram()`

### 5. Quick Actions Button Redesign
- **`OverviewView.swift`** — Iterative UI refinement:
  - MANUAL (fork.knife) and PHOTO (camera.viewfinder) combined as a pair with 1px gap
  - INSULIN button on the right, separated by larger gap
  - Combined pair matches INSULIN width
  - Fixed icon height (20px) for pixel-perfect alignment
  - Added horizontal padding to button section

### 6. Deploy Infrastructure Fix
- **`ExportOptions.plist`** — Switched from manual signing (hardcoded profile UUIDs) to automatic signing
  - Old profiles weren't installed on machine; automatic signing lets Xcode resolve them

## Architecture Decisions

- **GRDB migration pattern:** Used `DatabaseMigrator.registerMigration` with `ALTER TABLE ADD COLUMN` — matches existing pattern from `SensorGlucoseStore.swift`. New columns are optional (nullable) so existing meals aren't affected.

- **HealthKit write pattern:** One `HKQuantitySample` per nutrient type per meal (HealthKit requires separate samples per type). All share the same `HKMetadataKeySyncIdentifier` (meal UUID) for deduplication.

- **Progress animation:** Timer-based phases rather than API streaming. Streaming would require significant refactoring of the middleware/Combine pipeline for marginal benefit — the API call typically completes in 2-5 seconds.

## Learnings

- **Redux middleware guard ordering matters:** The Store runs reducer first, THEN passes new state to middlewares. If the reducer changes state that the middleware guards against, the middleware will never fire.

- **SF Symbols have inconsistent intrinsic sizes:** `camera.viewfinder` renders slightly shorter than `fork.knife` at the same font size. Fixed with `.frame(height: 20)` on the icon.

- **ExportOptions.plist with manual signing requires specific profile UUIDs:** Switching to `automatic` signing style removes this dependency entirely.
