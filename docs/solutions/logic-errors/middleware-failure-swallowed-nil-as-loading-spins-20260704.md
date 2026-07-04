---
date: 2026-07-04
module: Redux
tags: [combine, middleware, error-handling, loading-state, ratio-lab]
problem_type: logic-error
severity: high
---

# A Middleware Combine `.failure` Is Swallowed by the Store — "nil-as-loading" Views Spin Forever

## Problem

A view that treats "its backing state is still `nil`" as its loading indicator will spin **forever** if the middleware that populates that state emits a Combine `.failure` instead of a value. The `Store.dispatch` pipeline logs middleware failures via `DirectLog.error` but never converts them into a follow-up action, so the state-setting action never lands and the view never leaves its loading branch.

## Trigger

Ratio Lab (`RatioLabView`) has no `ratioEvidenceLoading` flag — by codebase convention the pure-trigger `.loadRatioEvidence` action falls through the reducer's `default:`, so the view uses `ratioEvidence == nil` as its "still loading" signal. `ratioLabMiddleware` called `DataStore.getRatioEvidence()` (a `Future<RatioEvidence, DirectError>`) and `.map`-ed only the success case:

```swift
return DataStore.shared.getRatioEvidence()
    .map { DirectAction.setRatioEvidence(evidence: $0) }
    .eraseToAnyPublisher()
```

`getRatioEvidence()` emits `.failure(.withError(error))` on any GRDB read error (locked/corrupt DB, migration failure, disk pressure). On failure, `.setRatioEvidence` is never dispatched, `ratioEvidence` stays `nil`, and `FiguresLoadingView.inline` renders indefinitely with no error surface and no retry.

## Root Cause

`Store.dispatch` treats a middleware publisher's `.failure` as terminal-and-logged, not as something to re-inject. So a failed async load produces **no** state mutation. Any view whose loading state is "the value hasn't arrived yet" cannot distinguish "still loading" from "load failed" — the two are the same `nil`.

## Fix

Make the middleware's publisher **total**: convert failure into a terminal action (usually the empty/safe value) so the view always leaves its loading branch. Log first, then fall back.

```swift
return DataStore.shared.getRatioEvidence()
    .map { DirectAction.setRatioEvidence(evidence: $0) }
    .catch { error -> Just<DirectAction> in
        DirectLog.error("Ratio Lab evidence load failed: \(error)")
        return Just(.setRatioEvidence(evidence: RatioEvidence(tddDays: [], mealObservations: [])))
    }
    .setFailureType(to: DirectError.self)   // .catch → Just makes Failure == Never; restore the channel's error type
    .eraseToAnyPublisher()
```

The screen now lands on its safe empty / "collecting evidence" state instead of an endless spinner.

## Prevention

- When a view uses "state is `nil`" (or empty) as its loading indicator, the middleware feeding it **must** emit a value on every path — `.catch`/`.replaceError` to a terminal action, never a bare `.map` over a fallible `Future`.
- `.catch { … Just(action) }` changes `Failure` to `Never`; add `.setFailureType(to: DirectError.self)` before `eraseToAnyPublisher()` to match the `Middleware` return type.
- Related: `grdb-future-nil-dbqueue-hangs-subscriber-20260318.md` (a `Future` that never *completes*) and `combine-future-async-bridge-double-resume-20260420.md` (a `Future` that completes *twice*). This one is a `Future` that completes with `.failure` and gets dropped.
