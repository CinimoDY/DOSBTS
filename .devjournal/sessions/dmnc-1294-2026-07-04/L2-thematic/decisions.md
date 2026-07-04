# Decisions — DMNC-1294

## Stage/show split instead of direct show

**Chose** a `stage()` + `showStagedIfAny()` split **over** calling `show()` directly in the callback.

**Why:** All three non-quick-log paths call `dismiss()` after the callback (either explicitly in the callback or the child view calls it). SwiftUI sheets present above the ContentView's overlays in UIKit's modal stack, so any overlay added to ContentView would be hidden while the sheet is open. Staging during the callback, then promoting in `onDismiss`, guarantees the toast appears after the sheet is fully gone.

## Kept in-sheet LoggedMealToast for quick-logs

**Chose** to keep the existing `LoggedMealToast` inside `UnifiedFoodEntryView` **over** routing quick-logs through the ContentView-level controller.

**Why:** Quick-log sheets stay open. The user can log multiple items in one session. The in-sheet toast provides immediate inline feedback and UNDO while the sheet is still active. Moving it to ContentView level would require the toast to appear above the open sheet (a UIKit-window overlay), which is unnecessarily complex and breaks the in-context UX.

## LoggedEntry as an App-target enum, not Library

**Chose** to place `LoggedEntry` in `App/Views/SharedViews/` **over** `Library/Content/`.

**Why:** It carries display logic (`label(glucoseUnit:)`) and references SwiftUI-adjacent types. It has no reason to be in the widget target. The Library is for domain models and shared utilities; display enums with glucoseUnit formatting belong in App.
