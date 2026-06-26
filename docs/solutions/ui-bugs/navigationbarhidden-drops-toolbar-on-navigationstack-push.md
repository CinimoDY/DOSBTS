---
title: .navigationBarHidden(true) drops toolbar buttons on a NavigationStack-pushed view
date: 2026-06-26
category: ui-bugs
module: App/Views/AddViews/UnifiedFoodEntryView
problem_type: ui_bug
component: frontend_stimulus
symptoms:
  - "Manual meal entry (Log Meal → MANUAL) had no Add/Cancel buttons and no 'Meal' title — no way to confirm a typed-in meal (shipped in a build)"
  - "Barcode scanner (Log Meal → SCAN) had no Cancel button or title; swiping down dismissed the entire Log Meal sheet instead of returning to the food list"
  - "PHOTO / ASK AI paths kept working — their confirm is an in-Form Section button, not a toolbar item, so the missing bar didn't hide it"
root_cause: wrong_api
resolution_type: code_fix
severity: high
tags: [swiftui, navigationstack, navigationbarhidden, toolbar, push-navigation, interactive-dismiss, ios26]
---

# .navigationBarHidden(true) drops toolbar buttons on a NavigationStack-pushed view

## Problem

The Log Meal entry surface (`UnifiedFoodEntryView`) is a `NavigationStack` presented as a sheet. Its MANUAL (`AddMealView`) and SCAN (`BarcodeScannerView`) sub-screens were pushed with `.navigationBarHidden(true)`. That modifier hides the **parent** stack's navigation bar for the pushed page — which is exactly where a pushed view's title and `.toolbar` buttons render. Every toolbar-based confirm/cancel control silently vanished, leaving no way to confirm a typed meal.

## Symptoms

- MANUAL screen: no **Add**, no **Cancel**, no "Meal" title — the whole top bar was empty. A user could type a meal but had no way to save it.
- SCAN screen: no **Cancel**, no "Scan Barcode" title. The only escape was a swipe-down, which dismissed the *entire* Log Meal sheet (back to Overview) rather than returning to the food list.
- PHOTO / ASK AI screens kept logging fine — their "Log Meal" confirm is an in-`Form` `Section` button, not a `.toolbar` item, so a missing nav bar didn't hide it.

## What Didn't Work

- **DMNC-1027's mechanical `NavigationView → NavigationStack` sweep.** It swapped `AddMealView`'s inner wrapper from a legacy `NavigationView` to a `NavigationStack` and left every `.navigationBarHidden(true)` in place. The bug persisted on `main`: a *nested* `NavigationStack` inside the parent stack still fails to render its own bar, and the call-site `.navigationBarHidden(true)` still hid the parent bar. Swapping the container type alone fixes nothing here.
- **Removing only the inner navigation container** (first attempt). Necessary but insufficient — verified on the simulator that the top bar was *still* empty, because `.navigationBarHidden(true)` at the call site hid the parent stack's bar where the now-correctly-attached toolbar lived.

## Solution

For each view pushed onto the entry `NavigationStack` whose controls live in a `.toolbar`:

1. **Don't nest a navigation container.** Attach `.dosNavigationTitle(...)` and `.toolbar { ... }` directly to the content so the *parent* stack hosts them.
2. **Remove `.navigationBarHidden(true)`** at the call site.
3. **Add `.navigationBarBackButtonHidden(true)`** so the explicit Cancel is the sole leading control.
4. For a full-screen, non-scrollable sub-screen (the scanner), **add `.interactiveDismissDisabled(...)`** so an accidental swipe-down doesn't tear down the whole sheet — but **scope it** so a further-pushed child re-enables the escape.

`AddMealView` — drop the wrapper, attach to the `Form`:

```swift
// BEFORE (buttons missing)
var body: some View {
    NavigationView {              // (DMNC-1027 made this NavigationStack — same failure)
        Form { ... }
        .dosNavigationTitle("Meal")
        .toolbar { /* Add / Cancel */ }
    }
}
// + call site: AddMealView { ... }.navigationBarHidden(true)

// AFTER (buttons render on the parent stack's bar)
var body: some View {
    Form { ... }
    .dosNavigationTitle("Meal")
    .navigationBarBackButtonHidden(true)
    .interactiveDismissDisabled()   // a half-typed meal isn't lost to a stray swipe
    .toolbar { /* Add / Cancel */ }
}
// + call site: AddMealView { ... }   // no .navigationBarHidden
```

Scanner dismiss-disable, **scoped** so the pushed staging plate isn't trapped:

```swift
// while scanning (no result) swipe-down is blocked; once a scan pushes the
// staging plate on top, swipe-to-dismiss is re-enabled there.
.interactiveDismissDisabled(store.state.foodAnalysisResult == nil)
```

## Why This Works

A view pushed onto a `NavigationStack` shares the stack's single navigation bar. `.toolbar { ... }` items and `dosNavigationTitle` (a principal toolbar item) render into *that* bar. `.navigationBarHidden(true)` — though deprecated — still takes effect inside a `NavigationStack` and hides that bar, taking the toolbar items with it. A nested `NavigationView`/`NavigationStack` creates a *second* navigation context that fails to render its own bar when the nesting view is itself pushed. `BarcodeScannerView` was the proof of the correct shape: no inner container, toolbar attached to the parent stack — its Cancel rendered once `.navigationBarHidden(true)` was removed.

## Prevention

- **Don't nest a `NavigationView`/`NavigationStack` inside a view that is pushed onto a `NavigationStack`.** The caller owns the stack; attach `.toolbar`/`dosNavigationTitle` to the content directly.
- **Don't put `.navigationBarHidden(true)` on a pushed destination whose controls live in the toolbar** — it hides the very bar hosting them. If a pushed view genuinely needs no chrome, put its confirm control in-content (like `FoodPhotoAnalysisView`'s "Log Meal" `Section` button), not in `.toolbar`.
- **A `NavigationView → NavigationStack` swap does not fix this class.** It only changes the container type; the nesting and the `navigationBarHidden` remain. Treat a "nav sweep" as orthogonal to "this screen's buttons are missing."
- **Full-screen pushed sub-screens inside a sheet:** swipe-down hits the *sheet's* interactive dismiss, not a navigation pop. Use `.interactiveDismissDisabled()` so a stray swipe doesn't destroy the whole sheet, but scope it (e.g. on a state flag) so a further-pushed child re-enables the swipe and users are never trapped.
- Quick audit: `grep -rn "navigationBarHidden" App/` — any hit on a `NavigationStack`-pushed destination with a `.toolbar` is suspect.

## Related Issues

- `ui-bugs/swiftui-nested-sheets-present-wrong-view-20260316.md` — same Log Meal surface; why push (not a nested sheet) is the right structure.
- `ui-bugs/swiftui-navigationlink-self-cancelling-state-mutation.md` — same file, a different `NavigationStack`/`navigationDestination` subtlety.
- DMNC-1027 — the `NavigationView → NavigationStack` sweep that did **not** fix this (proof a container swap is insufficient).
- DMNC-1185 — remaining `.navigationBarHidden(true)` instances on the PHOTO / ASK AI / relog staging plates (`FoodPhotoAnalysisView`), still to sweep.
- PR #72 — the fix (shipped in Build 114).
