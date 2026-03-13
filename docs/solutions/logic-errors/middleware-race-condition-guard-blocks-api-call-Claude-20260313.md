---
module: Claude
date: 2026-03-13
problem_type: logic_error
component: service_object
symptoms:
  - "Food analysis stuck on 'Analyzing meal photo...' — never returns results"
  - "API call to Claude Haiku never fires despite valid API key and consent"
root_cause: async_timing
resolution_type: code_fix
severity: critical
tags: [redux, middleware, race-condition, guard, food-analysis, combine]
---

# Troubleshooting: Middleware Guard Blocks API Call Due to Reducer-First Execution Order

## Problem
The AI food photo analysis feature appeared stuck on "Analyzing meal photo..." and never returned results. The API call to Claude Haiku was silently blocked by a middleware guard that checked state already modified by the reducer.

## Environment
- Module: Claude (AI food photo analysis)
- Architecture: Redux-like Store/Action/Reducer/Middleware in SwiftUI
- Affected Component: `ClaudeMiddleware.swift` guard condition
- Date: 2026-03-13

## Symptoms
- User taps "AI" button, selects photo, sees "Analyzing meal photo..." spinner indefinitely
- No network request to `api.anthropic.com` is made
- No error is displayed — the UI just hangs on the loading state
- Cancel button still works (dismisses the view)

## What Didn't Work

**Direct solution:** The problem was identified on the first investigation by tracing the dispatch flow through the Redux architecture.

## Solution

Removed `!state.foodAnalysisLoading` from the middleware guard.

**Code changes:**
```swift
// Before (broken):
case .analyzeFood(let imageData):
    guard state.aiConsentFoodPhoto, !state.foodAnalysisLoading else {
        return Empty().eraseToAnyPublisher()
    }

// After (fixed):
case .analyzeFood(let imageData):
    guard state.aiConsentFoodPhoto else {
        return Empty().eraseToAnyPublisher()
    }
```

## Why This Works

The Redux-like `Store.dispatch()` in this codebase calls `reducer(&state, action)` **first**, then passes the **new state** to middlewares:

```swift
func dispatch(_ action: Action) {
    let lastState = state
    reducer(&state, action)          // 1. Reducer mutates state FIRST
    for mw in middlewares {
        guard let middleware = mw(state, action, lastState) else { ... }  // 2. Middleware sees NEW state
    }
}
```

The view's `analyzeImage()` method dispatched two actions sequentially:
1. `.setFoodAnalysisLoading(isLoading: true)` — reducer sets `foodAnalysisLoading = true`
2. `.analyzeFood(imageData:)` — middleware receives this with `state.foodAnalysisLoading == true`

The middleware guard `!state.foodAnalysisLoading` was always `false` by the time `.analyzeFood` reached it, so it returned `Empty()` and the API call never fired.

The double-dispatch protection was unnecessary anyway — the view already prevents re-entry by switching to the loading UI state, which hides the photo picker buttons.

## Prevention

- **Never guard on state that a prior dispatch in the same flow just changed.** The reducer runs synchronously before middlewares, so the state middlewares see is post-reduction.
- When adding middleware guards, trace the full dispatch chain to check if earlier dispatches modify the guarded state.
- This pattern is now documented in `CLAUDE.md` under "Architecture gotchas."

## Related Issues

- See also: [redux-action-secret-leakage-keychain-side-channel.md](../security-issues/redux-action-secret-leakage-keychain-side-channel.md) — another Redux architecture pitfall in the same codebase
