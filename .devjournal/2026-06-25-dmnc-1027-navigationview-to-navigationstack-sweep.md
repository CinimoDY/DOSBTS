# DMNC-1027 — NavigationView → NavigationStack sweep

**Date:** 2026-06-25

## What changed

Replaced every remaining `NavigationView` root with `NavigationStack` across the Add/modal sheet views. On iOS 26 (deployment target), `navigationDestination` modifiers are silently ignored inside `NavigationView`, which had already broken the ASK AI row and the relog flow in `UnifiedFoodEntryView` (fixed separately in PR #52). This sweep closes the remaining exposure.

### Files modified

| File | Structs updated |
|---|---|
| `App/Views/AddViews/AddCalibrationView.swift` | `AddCalibrationView`, `AddCalibrationView2` |
| `App/Views/AddViews/AddMealView.swift` | `AddMealView` |
| `App/Views/AddViews/AddBloodGlucoseView.swift` | `AddBloodGlucoseView` |
| `App/Views/AddViews/TreatmentModalView.swift` | `TreatmentModalView` |
| `App/Views/AddViews/FoodPhotoAnalysisView.swift` | `FoodPhotoAnalysisView` (non-relog branch only) |
| `App/Views/AddViews/UnifiedFoodEntryView.swift` | `FavoriteManagementView`, `EditFavoriteView` |

`CombinedEntryEditView` was already on `NavigationStack` — untouched.

## Why this approach

Pure mechanical substitution — `NavigationStack` is a drop-in for `NavigationView` when there are no typed-path push destinations (none of these views use programmatic `NavigationPath`). No toolbar, title, or `.sheet` behaviour changes.

### FoodPhotoAnalysisView relog path preserved

The existing conditional (`if relogMeal != nil { formContent } else { NavigationStack { formContent } }`) is intentional: the relog path is presented inside the caller's nav stack (set up by `UnifiedFoodEntryView`), so double-wrapping would break the navigation hierarchy. The non-relog path (standalone sheet) now correctly owns its own `NavigationStack`, which makes the barcode-scanner `navigationDestination` work.

## Build result

`** BUILD SUCCEEDED **` — no compile errors or warnings from the change.
