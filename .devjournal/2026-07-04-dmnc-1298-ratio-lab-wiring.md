# DMNC-1298: Ratio Lab wiring — actions, state, on-demand evidence middleware

**Date:** 2026-07-04
**Branch:** claude/dmnc-1298
**Blocked by:** DMNC-1297 (WP-R1 — `RatioEstimator` core types consumed here)

Part of the Ratio Lab track ([DMNC-1291](https://linear.app/lizomorf/issue/DMNC-1291)). This is **WP-R2**, the Redux wiring layer; WP-R3 (UI) follows. Spec: `docs/plans/2026-07-03-ratio-lab-plan.md § WP-R2`.

## What changed

### `Library/DirectAction.swift` (3 new actions, new `// MARK: Ratio Lab` block)

```
loadRatioEvidence
setRatioEvidence(evidence: RatioEvidence?)
setConfirmedICR(icr: Double?)
```

### State — 4-file lockstep for `confirmedICR`, 3-file for `ratioEvidence`

- **`Library/DirectState.swift`** — `ratioEvidence: RatioEvidence?` (transient) + `confirmedICR: Double?` (persisted)
- **`Library/Extensions/UserDefaults.swift`** — new `confirmedICR` key + optional-Double accessor (same `object(forKey:) != nil` guard + `removeObject` on nil pattern as `dailyDigestReminderHour`)
- **`App/AppState.swift`** — init reads `defaults.confirmedICR`; `ratioEvidence` is a plain `var` (no didSet, not persisted); `confirmedICR` has `didSet { defaults.confirmedICR = confirmedICR }`
- **`Library/DirectReducer.swift`** — `setRatioEvidence` and `setConfirmedICR` cases

### `App/Modules/RatioLab/RatioLabMiddleware.swift` (new, ~130 LOC)

On-demand middleware — responds only to `.loadRatioEvidence` (guards `state.appState == .active`), emits `.setRatioEvidence(evidence:)`. Does NOT compute on app-activation (cold path — the screen opens rarely, unlike MealImpactStore's eager backfill).

Includes a `DataStore` extension with `getRatioEvidence() -> Future<RatioEvidence, DirectError>` that does all GRDB I/O in **ONE `asyncRead`** (GRDB deadlock rule: no writes inside asyncRead):

1. **InsulinDelivery** — 14-day window [startOfDay(today−14d), startOfToday); type filtered in Swift after fetch (InsulinType is Codable, not SQL-filterable). Passed to `RatioEstimator.tddDays(from:asOf:)`.
2. **MealImpact** — isClean + timestamp ≥ now−30d (MealImpactStore backfill bound); fetched with SQL predicates.
3. **MealEntry** — joined in Swift by mealEntryId; uses `idStrings.contains(Column(...))` GRDB filter with `.uuidString.uppercased()` (matching the `databaseUUIDEncodingStrategy = .uppercaseString` encoding).
4. **SensorGlucose** — per-candidate window [t, t+135min] inside the same asyncRead; results passed to `RatioEstimator.endGlucose` and `RatioEstimator.minGlucoseInWindow`.
5. **Bolus pairing** — `RatioEstimator.pairedBolusUnits(mealTimestamp:deliveries:)` using the already-fetched `allDeliveries` (no extra query).

### `App/App.swift` — `ratioLabMiddleware()` added to both `createSimulatorAppStore` and `createAppStore`

### `DOSBTSTests/DirectReducerTests.swift` — 6 new tests in `RatioLabStateTests` suite

- `setRatioEvidence` stores and nil-clears
- `ratioEvidence` is transient (fresh `AppState` from same defaults sees nil)
- `setConfirmedICR` stores value
- nil clears `confirmedICR`
- `confirmedICR` UserDefaults round-trip via `AppState(defaults:)`
- nil clears UserDefaults so fresh `AppState` starts nil

## Decisions worth flagging

- **On-demand only, not app-activation.** MealImpactStore computes eagerly on every glucose reading because it's backfilling data for the chart. Ratio Lab evidence is heavy (multi-table join + per-candidate glucose window reads) and the screen opens rarely — dispatching `.loadRatioEvidence` from `RatioLabView.onAppear` is the right shape.
- **14-day insulin window for both TDD and bolus pairing.** The spec is explicit: `[startOfDay(today−14d), startOfToday)`. Meals from 15–30 days ago that lack bolus data in this window will receive `noBolus` exclusion — a conservative, correct outcome (the estimator teaches; a missing bolus is informative). Extending to 30 days would widen the query for minimal gain.
- **Single `asyncRead`, no writes.** The GRDB deadlock rule (CLAUDE.md + `docs/solutions/logic-errors/grdb-write-inside-asyncread-deadlock-20260420.md`) is the hard constraint. All five data-fetching steps execute on the same `Database` handle inside one `asyncRead` closure. `getRatioEvidence` returns a `Future` that emits the assembled `RatioEvidence`; the middleware maps it to `.setRatioEvidence`.
- **`ratioEvidence` is transient (3-file pattern).** It's computed on demand from GRDB — persisting it would create a stale-data problem (the user opens the screen, evidence is computed fresh; persisting a snapshot would be stale on next launch). Matches `selectedSettingsCategory` and `tightControlCelebration`.
- **`confirmedICR` is persisted (4-file lockstep).** This is a user-chosen reference value — it must survive app restarts. Optional-Double pattern avoids the `double(forKey:)` default-zero trap: `object(forKey:) != nil` guards the read; `removeObject` clears it on `nil`.

## Tests

`** TEST SUCCEEDED **` — all 6 new `RatioLabStateTests` pass, and the **full `DOSBTSTests` suite is green** (no regressions) on iPhone 17 Pro / iOS 26.5.
