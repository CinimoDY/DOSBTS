---
title: "A persisted 'show X' flag must be re-validated against current state by every presenter — the stale LOW GLUCOSE prompt"
date: 2026-10-12
category: logic-errors
module: treatment-cycle
problem_type: bug
component: sheet-coordinator
severity: high
applies_when:
  - "A Redux/UserDefaults flag (showTreatmentPrompt, a 'pending sheet', a 'needs attention' marker) is set by a middleware or a notification action and consumed later by a presenter"
  - "The flag can be set while the scene is backgrounded, where SwiftUI .onChange observers are dormant, so it is first acted on at the next foreground or cold launch"
  - "What the flag asks the user to do is only valid against live data (a glucose reading, a connection state, a timer) that may have moved on"
tags:
  - treatment-cycle
  - alarms
  - sheetcoordinator
  - redux-middleware
  - onchange
  - foreground
  - staleness
  - cgm-safety
---

# A persisted "show X" flag must be re-validated by every presenter

## Problem

The hypo-treatment prompt ("LOW GLUCOSE DETECTED", `TreatmentModalView`) kept appearing when the app was opened hours after a low, over a reading that was in range or high. Dom was dismissing it by hand on most app opens (DMNC-1560, Build 138).

`showTreatmentPrompt` + `alarmFiredAt` were set by three producers — the predictive-low path in `GlucoseNotification.swift`, the `.treatmentCycleStillLow` reducer case, and the notification buttons in `App.swift` — and consumed by `SheetCoordinator.treatmentPresent`, whose prompt branch checked only that the flag was set. Two things made the flag stale by the time it was presented:

1. `ContentView`'s `.onChange(of: showTreatmentPrompt)` is dormant while backgrounded (see `swiftui-onchange-dormant-when-backgrounded-20260424.md`), so the first presenter to see the flag was often the cold-launch / foreground `presentTreatmentSheetIfNeeded()`, long after the alarm.
2. When the observer *did* fire in the background, the modal was presented then and simply stayed up — nothing re-checked it on foreground.

`alarmFiredAt` is persisted and was cleared only on cycle end/dismiss, so the stale pair survived relaunches.

## Root cause

The flag encoded *intent* ("ask the user to treat") but no presenter asked whether the intent was still *current*. There was no predicate relating the flag to the latest reading, no foreground re-validation of an already-presented sheet, and a rejected flag was never cleared — so a stuck `true` would also have turned the next genuine `.showTreatmentPrompt` into a true→true transition that `.onChange` never observes.

A secondary bug hid in the same middleware: the low/high branches returned only `deferredActions.first`, so any second follow-up action (a flag clear queued behind the predictive-flag clear) was silently dropped.

## Solution (PR #126)

1. **One currency predicate, defined once.** `isTreatmentPromptCurrent(latestGlucose:alarmLow:predictive:smoothedMinuteChange:now:)` in `Library/Content/AlarmProfile.swift`: no reading or a `.veryStale` reading (≥15 min, `GlucoseStaleness`) → not current; value below `alarmLow` → current; a predictive prompt is current only with a `.fresh` reading (<5 min) inside the clear zone (`alarmLow + predictiveLowClearMargin`) whose 20-minute projection on the alarm's own 3-reading smoothed slope (`smoothedMinuteChange(of:)`) still crosses `alarmLow`. Exposed once as `DirectState.isTreatmentPromptCurrent(predictive:)` so no call site re-assembles the arguments differently.

2. **Every presenter gates on it.** `SheetCoordinator.treatmentPresent` (prompt branch only — the recheck branch is deliberately *not* staleness-gated: during an active cycle over-prompting is the safe failure); `ContentView` on cold launch **and** on `appState → .active`, where `revalidateTreatmentModalOnForeground()` also dismisses an already-presented modal whose prompt is no longer current; `TreatmentModalView` on each new reading (closes only on actual recovery: `≥ alarmLow`, or `≥ alarmLow + 10` for a predictive prompt — never on a flattened slope, which dismissed mid-interaction); the notification buttons in `App.swift` (TREAT NOW / EAT NOW refuse only when there is no usable reading, so a user who ate and taps late still gets the treatment logged; More… keeps the full gate).

3. **A rejected flag is cleared.** New `.clearStaleTreatmentPrompt` clears `showTreatmentPrompt` and, when no cycle is active, `alarmFiredAt`. `ContentView` dispatches it whenever the decision is nil while the flag is set.

4. **Cleared at the source too.** `shouldClearTreatmentPromptAtSource(...)` in the glucose middleware appends the clear once a reading reaches the clear zone, and the low/high branches now emit **every** deferred action (`Publishers.MergeMany` / `deferredActions.publisher`) instead of `.first`.

5. **Persist what the predicate depends on.** `predictiveLowAlarmFired` is now in `UserDefaults`; without it a cold launch from an EAT NOW tap evaluated a valid predictive prompt as `predictive == false` and dropped it.

`.treatmentCycleStillLow` no longer sets `showTreatmentPrompt` (the recheck sheet is its sole surface), which removed the fall-through to the generic modal on a recovered reading.

Pinned by the `TreatmentPromptCurrencyTests` rows in `DOSBTSTests/SheetCoordinatorTests.swift` (recovered / at-threshold / very-stale / stale-but-presentable / fresh-low / predictive still-falling / flattened / above-zone / no-slope / 7-min-old / stillLow-then-recovered / recheck-not-gated) and reducer tests for the clear action.

## Prevention

When a middleware or notification action sets a persisted "show X" flag for a presenter, ship four things with it, or expect this bug class: (a) a pure currency predicate against the live state the request depends on, exposed once on `DirectState`; (b) re-validation on foreground of both the pending flag *and* any sheet already on screen; (c) clearing the flag when it is rejected; (d) a check that the middleware actually emits every follow-up action it queues. The safety rule to keep while doing so: the gate must only ever suppress what is already over — a genuine, fresh low must always present.
