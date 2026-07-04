---
title: "Redux undo path fires live-event middleware side effects when dispatching add* actions for restores"
date: 2026-07-04
category: logic-errors
module: DataStore
problem_type: logic_error
component: development_workflow
severity: critical
symptoms:
  - "Tapping UNDO on a swipe-deleted CGM reading triggers a glucose alarm for a historical value"
  - "ReadAloud speaks the deleted reading's glucose value after the user taps UNDO"
  - "HealthKit and Nightscout receive a duplicate entry on undo of a blood glucose deletion"
  - "Treatment cycle or streak detection re-evaluates against a hours-old restored reading"
root_cause: wrong_api
resolution_type: code_fix
tags: [redux, middleware, undo, swipe-delete, restore, sensor-glucose, live-event]
---

# Redux undo path fires live-event middleware side effects when dispatching add* actions for restores

## Problem

When an undo path dispatches an `add*` action (e.g., `.addSensorGlucose`, `.addBloodGlucose`) to restore a swipe-deleted entry, every middleware that handles that action fires — including alarms, voice readout, HealthKit export, Nightscout upload, and treatment-cycle evaluation. These middlewares are designed for live incoming sensor readings, not list-restore operations.

## Symptoms

- Tapping UNDO on a swipe-deleted CGM reading triggers glucose alarm notifications for a value that may be hours old
- ReadAloud speaks the old glucose value aloud mid-session
- HealthKit and Nightscout receive duplicate entries when blood glucose deletion is undone
- TreatmentCycleMiddleware or TightControlStreakMiddleware re-evaluates against the restored historical value
- MissedBolusMiddleware silently cancels a pending reminder when an insulin undo re-dispatches `.addInsulinDelivery`

## What Didn't Work

Using `.addSensorGlucose(glucoseValues: [g])` in the undo handler directly: the `DataStore` write succeeds but 14+ middlewares treat the action as a live reading and fire their full side-effect chains.

## Solution

Add dedicated `restore*` actions that are handled **only** by the relevant DataStore middleware. No other middleware pattern-matches on `restore*`, so side effects are scoped exclusively to the DB insert + list reload.

```swift
// DirectAction.swift — add alongside the corresponding delete cases
case restoreBloodGlucose(glucose: BloodGlucose)
case restoreInsulinDelivery(insulinDelivery: InsulinDelivery)
case restoreSensorGlucose(glucose: SensorGlucose)

// BloodGlucoseStore.swift — DB-only restore, no Nightscout/HealthKit
case .restoreBloodGlucose(glucose: let glucose):
    DataStore.shared.insertBloodGlucose([glucose])
    return Just(DirectAction.loadBloodGlucoseValues)
        .setFailureType(to: DirectError.self)
        .eraseToAnyPublisher()

// ContentView.swift — undo handler uses restore* not add*
case .deletedBloodGlucose(let g):
    store.dispatch(.restoreBloodGlucose(glucose: g))
case .deletedSensorGlucose(let g):
    store.dispatch(.restoreSensorGlucose(glucose: g))
case .deletedInsulin(let i):
    store.dispatch(.restoreInsulinDelivery(insulinDelivery: i))
```

The reducer's `default: break` arm handles the new cases with no state mutation — the GRDB insert + list reload is the sole state update path, and it goes through the normal `load*` → `set*` action chain.

## Why This Works

The root cause is action overloading: `add*` actions serve double duty as "new live event arrived" (sensor connector, form submission) and "restore historical entry" (undo). Middlewares cannot distinguish these two intents from the action alone — they fire unconditionally on the action case regardless of where the dispatch originated.

Dedicated `restore*` actions break the overloading. Because no other middleware has a `case .restoreXxx:` arm, they are transparent to every middleware except the DataStore one that handles the DB write. The DataStore restore handler mirrors the delete handler: one insert, one reload, no extra side effects.

## Prevention

- **Audit every middleware before adding a new undo path.** For each action you plan to dispatch on undo, list every middleware that handles it and its side effects. If any middleware produces a side effect that is inappropriate for a restore (alarm, export, voice, third-party sync), add a dedicated `restore*` action instead of reusing the existing one.
- **Never use live-event actions as restores.** Actions consumed by `GlucoseNotification`, `ReadAloud`, `AppleHealthExport`, `Nightscout`, `TreatmentCycleMiddleware`, or `TightControlStreakMiddleware` are live-event actions. Any undo/restore path that needs to write to GRDB without these side effects requires its own action case.
- **Reducer's `default: break` makes this low-ceremony.** `restore*` actions need no reducer handling — the `default: break` arm handles them, and the middleware-emitted `load*` action does the state update. No four-file state property addition is needed for pure side-effect-bypass actions.

## Related Issues

- `docs/solutions/logic-errors/redux-undo-uuid-mismatch-middleware-creates-object-20260315.md` — different undo failure mode (UUID mismatch), same area
- `docs/solutions/logic-errors/redux-middleware-async-task-pitfalls-20260420.md` — broader Redux middleware gotchas
