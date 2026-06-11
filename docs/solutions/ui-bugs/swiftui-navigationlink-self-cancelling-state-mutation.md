---
title: NavigationLink cancels its own push when the destination's onAppear mutates the state that renders the link
date: 2026-06-11
category: ui-bugs
module: App/Views/AddViews/UnifiedFoodEntryView
problem_type: ui_bug
component: frontend_stimulus
symptoms:
  - "Tapping a List row NavigationLink does nothing — no navigation, no error, regardless of how many taps (ASK AI row needed 3-4 taps and still failed)"
  - "Redux action log shows the destination's onAppear dispatch firing, followed ~1s later by the onDisappear cleanup pair — push started and instantly unwound"
  - "OS log (Invalid Configuration): 'The navigationDestination modifier only works inside a NavigationStack' for sibling flows"
root_cause: logic_error
resolution_type: code_fix
severity: high
tags: [swiftui, navigationlink, navigationstack, navigationdestination, onappear, self-cancelling]
---

# NavigationLink cancels its own push when the destination's onAppear mutates the state that renders the link

## Problem

The food-search "ASK AI" row appeared completely dead: tapping it never navigated, with or without the keyboard up. The navigation was actually firing every time — and cancelling itself.

## Symptoms

- First tap (and every tap) on the row does nothing visible.
- The action log shows the smoking-gun pattern: `setFoodAnalysisLoading(isLoading: true)` (destination `onAppear`) followed about a second later by `setFoodAnalysisResult(result: nil)` + `setFoodAnalysisLoading(isLoading: false)` (destination `onDisappear` cleanup). The push started, the destination appeared, and the push unwound.

## What Didn't Work

- Blaming the `.searchable` keyboard: a control test showed sibling NavigationLinks (MANUAL) navigated on the first tap with the search session active. The keyboard was a red herring.

## Solution

Two-part fix in `UnifiedFoodEntryView`:

1. **Decouple navigation from the conditional row.** The link's row lived inside `if foodAnalysisLoading { ProgressView } else { NavigationLink }`. The destination's `onAppear` set `foodAnalysisLoading = true`, the List rebuilt, the branch swapped the link for the loading row, and SwiftUI cancelled the in-flight push because its source link vanished. Replace the link with a `Button` that dispatches first, then navigates via `navigationDestination(isPresented:)` attached to the List — a modifier on the container survives row rebuilds.

```swift
// BEFORE: self-cancelling
NavigationLink {
    FoodPhotoAnalysisView()
        .onAppear { store.dispatch(.setFoodAnalysisLoading(isLoading: true)) /* removes this link! */ }
} label: { askAIRow }

// AFTER: dispatch from the row, navigate via the container
Button {
    store.dispatch(.setFoodAnalysisLoading(isLoading: true))
    store.dispatch(.analyzeFoodText(query: query))
    askAINavigating = true
} label: { askAIRow }
// ...on the List:
.navigationDestination(isPresented: $askAINavigating) { FoodPhotoAnalysisView() }
```

2. **Convert the root `NavigationView` to `NavigationStack`.** `navigationDestination` is *silently ignored* inside legacy `NavigationView` — the OS logs `[Invalid Configuration] The navigationDestination modifier only works inside a NavigationStack` but the UI just does nothing. This had also silently broken the existing relog ("LOG AGAIN") destination.

## Why This Works

A `NavigationLink`'s push is owned by the link view. If a state change removes that link from the hierarchy mid-transition, SwiftUI cancels the navigation. `navigationDestination(isPresented:)` is keyed to a Bool on the container, so row churn cannot kill it. The `NavigationStack` conversion makes the destination modifiers actually register.

## Prevention

- Never dispatch state changes from a NavigationLink destination's `onAppear` when that state controls whether the link itself renders. Dispatch at the tap site instead.
- Treat `navigationDestination` + `NavigationView` as a build error in this codebase — check the OS log for `Invalid Configuration` when a push "does nothing".
- The Redux action log (Log middleware, in-app log export) is the fastest instrument for "did the navigation actually fire": look for present-then-instant-cleanup action pairs.

## Related Issues

- `docs/solutions/ui-bugs/swiftui-nested-sheets-present-wrong-view-20260316.md` — same family of "presentation mechanics silently fail" bugs.
- Remaining `NavigationView` usages (FavoriteManagementView, AddCalibrationView, CombinedEntryEditView) are a follow-up sweep candidate.
