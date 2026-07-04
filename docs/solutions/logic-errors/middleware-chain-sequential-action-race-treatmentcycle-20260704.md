---
module: MissedBolusNudge
date: 2026-07-04
problem_type: logic_error
component: middleware
symptoms:
  - "Missed-bolus nudge fires for hypo treatment meals despite suppression guard"
root_cause: async_timing
resolution_type: code_fix
severity: medium
tags: [redux, middleware, race-condition, sequential-actions, treatment-cycle]
---

# Middleware Chain Sequential-Action Race: Guard on State Set by a Later Action in the Chain

## Problem

A middleware needs to suppress a notification when a hypo treatment meal is being logged via `.logHypoTreatment`. The obvious guard is `!state.treatmentCycleActive`. But when the nudge middleware sees the `.addMealEntry` action emitted as part of the treatment flow, `treatmentCycleActive` is still `false`.

## Root Cause

`TreatmentCycleMiddleware` handles `.logHypoTreatment` by emitting two sequential actions:
1. `.addMealEntry(mealEntryValues:)` — logs the treatment meal
2. `.startTreatmentCycle(...)` — activates the treatment cycle

The store processes emitted actions in order. When the store reaches `.addMealEntry`, the `.startTreatmentCycle` action hasn't been processed yet — so `state.treatmentCycleActive` is still `false`. The nudge middleware's guard `!state.treatmentCycleActive` evaluates `false`, meaning "not suppressed", which is wrong.

This is distinct from the [same-action race](middleware-race-condition-guard-blocks-api-call-Claude-20260313.md) (where a middleware guards on state changed by the reducer for that same action). Here, the state in question is changed by a **different action** that comes later in the chain.

## Solution

Guard on state that IS already set when `.addMealEntry` fires. The `.logHypoTreatment` reducer sets `state.treatmentLoggedAt = Date()` synchronously. By the time `TreatmentCycleMiddleware` emits `.addMealEntry`, `treatmentLoggedAt` is non-nil.

```swift
// Wrong — treatmentCycleActive is still false when this fires
guard state.treatmentLoggedAt == nil else { break }  // ✓ treatmentLoggedAt is already set

// This is set by the .logHypoTreatment reducer, not by .startTreatmentCycle
// so it's reliable at .addMealEntry time
```

## Generalisation

When suppressing on cross-middleware state changes, trace the **complete dispatch chain** for the suppression scenario:

1. What action triggers the chain? (`.logHypoTreatment`)
2. What does its reducer set? (`treatmentLoggedAt`)
3. What does the handling middleware emit? (`.addMealEntry`, then `.startTreatmentCycle`)
4. When does the target action fire in that chain? (Step 3a, before step 3b)
5. What state is available at that point? (reducers for steps 1–3a have run; 3b has not)

Guard on state that's guaranteed to be set by the time the target action arrives, not on state that requires a later action in the chain to be processed.

## Related Issues

- [`middleware-race-condition-guard-blocks-api-call-Claude-20260313.md`](middleware-race-condition-guard-blocks-api-call-Claude-20260313.md) — The simpler variant: guarding on state changed by the reducer for the same action
- [`redux-middleware-async-task-pitfalls-20260420.md`](redux-middleware-async-task-pitfalls-20260420.md) — Related timing issues in async middleware contexts
