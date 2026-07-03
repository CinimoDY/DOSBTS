# DMNC-1297: RatioEstimator — pure ICR/ISF estimation core + test suite

**Date:** 2026-07-03
**Branch:** claude/dmnc-1297
**PR:** https://github.com/CinimoDY/DOSBTS/pull/85 (draft)

Part of the Ratio Lab track ([DMNC-1291](https://linear.app/lizomorf/issue/DMNC-1291)). This is **WP-R1**, the pure-logic core; WP-R2 (wiring) and WP-R3 (UI) follow. Spec: `docs/plans/2026-07-03-ratio-lab-plan.md § WP-R1`.

## What changed

### `Library/Content/RatioEstimator.swift` (new, ~330 LOC incl. doc comments)

A pure, I/O-free estimator in the `IOBCalculator.swift` mold — no UI, no Redux, no state. Types (all `Equatable`): `TDDDay`, `MealObservation`, `RatioEvidence`, `MealExclusionReason`, `ScoredMealObservation`, `RatioEstimates`. Entry point `RatioEstimator.estimate(evidence:)`.

- **500 rule** (Walsh, *Using Insulin*): ICR = 500 / TDD. **1800 rule**: ISF = 1800 / TDD mg/dL. TDD = **median** of qualifying days (robust to a forgotten bolus — commented why not mean). A day qualifies with **≥1 basal AND ≥1 bolus** logged (basal-/bolus-only = MDI logging gap). Gate: **≥5 qualifying days**, else the rule estimates are `nil`.
- **Empirical ICR** = median of carbs÷bolus over qualifying "clean" meals; spread = **P25–P75**. Gate: **≥5 qualifying meals**.
- **Meal qualification** — each rejection maps to a `MealExclusionReason` (the teaching tag the UI will show). Checked in the plan's criterion order (1→7); the first unmet criterion wins: `confounded` (isClean) → `noBaseline`/`baselineOutOfRange` (70–180) → `noBolus`/`tinyBolus` (<0.5 U) → `smallMeal` (<15 g) → `hypoInWindow` (visible low, checked first for safety) → `insufficientData` (CGM gap) → `didNotReturnToBaseline(deltaMgDL:)` (|end−baseline| >30, signed) → `implausibleRatio` (2–50 g/U clamp).
- **All thresholds are `static let`** and test-pinned.

The file also carries the **pure derivation helpers** WP-R2 will call to build `MealObservation`/`TDDDay` from GRDB rows — kept here (not in the wiring layer) so they're pinned by the same unit suite:
- `tddDays(from:asOf:calendar:)` — buckets deliveries into complete-day totals within the last 14 complete days (today excluded); basal attributed to its `starts` date.
- `pairedBolusUnits(mealTimestamp:deliveries:)` — sums meal/snack boluses within ±15 min (time-window, not timegroup; correction/basal excluded).
- `endGlucose(mealTimestamp:readings:)` — reading nearest t+120 within t+105..t+135; earlier reading wins a tie.
- `minGlucoseInWindow(mealTimestamp:readings:)` — min glucose in [t, t+2h].
- `median` / `percentile` — type-7 linear interpolation (numpy/`PERCENTILE.INC`).

### `DOSBTSTests/RatioEstimatorTests.swift` (new, 48 tests)

Swift Testing suites covering the full plan matrix: 500/1800 formulas, the 5-day gate, median-not-mean (skewed fixture), basal-/bolus-only exclusion; one test per exclusion reason (incl. `confounded` + `insufficientData`); a boundaries & precedence suite pinning inclusivity at every threshold and the criterion-precedence order; bolus-pairing windows; endGlucose nearest-selection + tie-break + out-of-window nil; TDD day builder (partial-today excluded, late-night basal attribution, 14-day window, basal-/bolus-only days returned); median + P25/P75 pinned exactly (n=4 → nil, n=5 → value). Registered via the **4 manual `project.pbxproj` entries** (PBXBuildFile / PBXFileReference / DOSBTSTests group / PBXSourcesBuildPhase) — the tests target is not file-system-synchronized.

## Decisions worth flagging

- **Two justified `MealExclusionReason` additions beyond the plan's 8-case sketch**, each implementing a plan meal-criterion the sketch under-specified:
  - `confounded` — plan **criterion 1** (`impact.isClean == false`). The sketch delegated this entirely to WP-R2's query filter; the estimator now enforces it too (defense-in-depth for a clinical estimate — a loader regression can't pollute the empirical median).
  - `insufficientData` — plan **criterion 6**'s "missing +2h reading → excluded". `didNotReturnToBaseline(deltaMgDL:)` needs a concrete Int a missing reading can't supply, so this represents "not enough CGM coverage" (missing endGlucose OR in-window minimum).
- **Derivation helpers live in WP-R1, not WP-R2.** The plan lists "pairing windows" and "endGlucose nearest-selection" in the WP-R1 test matrix, only testable if the functions exist here. WP-R2 becomes a thin GRDB adapter that calls them. Mirrors how `IOBCalculator` exposes `computeIOB` for `IOBMiddleware`.
- **`estimate()` stays pure of `Date()`** — the day-window filtering that needs "today" lives in `tddDays(from:asOf:)` (asOf injected), so both are deterministic and testable.

## Code review (self, xhigh multi-agent)

Ran `/code-review` at xhigh effort (47 agents, adversarial verify). Fixes applied from verified findings:
- **Safety:** a *visible* hypo is now checked **before** the CGM-coverage gate, so a real low with a missing +2h reading is tagged `hypoInWindow`, not `insufficientData` (the safety lesson is never masked).
- **Robustness:** added the `confounded` isClean backstop (above); guarded `percentile([])` against an empty-array index trap; documented the identity-only `Equatable` caveat on `RatioEstimates`.
- **Order:** reordered `score()` to the plan's 1→7 criterion numbering and pinned the precedence + every threshold boundary with tests.
- **Repo rule:** replaced test force-unwraps with `try #require`.

## Tests

`** TEST SUCCEEDED **` — all 48 `RatioEstimator*` tests pass, and the **full `DOSBTSTests` suite is green** (no regressions) on iPhone 17 Pro / iOS 26.5. No app/state/UI changes; nothing else touched.
