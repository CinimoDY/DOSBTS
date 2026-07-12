# PLAN: Ratio Lab V3 — empirical ISF from clean correction boluses (wire InsulinImpact)

**Linear:** DMNC-1303 (Backlog → In Progress when starting).
**Rank:** 2 of 6. Effort: M (~1 day). Do after PLAN-ratio-lab-reference-line.

## Goal

Add a fourth card to the Ratio Lab: **YOUR CORRECTIONS** — the empirically observed ISF (mg/dL drop per unit) computed from *clean* correction boluses in the user's own history, with N + spread, sample-gated at n≥5, plus a CORRECTIONS evidence section whose exclusion rows teach what a clean correction experiment is. This wires the dormant `Library/Content/InsulinImpact.swift` (which has tests but **zero production call sites** — verified 2026-07-10). Wire it; do not build a parallel model.

Reference-only, like everything in Ratio Lab: no dosing commands, every number ships with N/spread, both fixed disclaimers stay.

## Preconditions

1. `git pull --ff-only` (needs Build 129 / commit `ee719767`+ — the confounded-rows loader shape from PR #96 is assumed below).
2. Branch `claude/dmnc-1303`.
3. Read these files fully before coding: `Library/Content/InsulinImpact.swift` (45 lines), `Library/Content/RatioEstimator.swift`, `App/Modules/RatioLab/RatioLabMiddleware.swift` (contains `DataStore.getRatioEvidence()` as an extension — the loader does NOT live in `App/Modules/DataStore/`), `App/Views/Settings/RatioLabView.swift`, `docs/plans/2026-07-03-ratio-lab-plan.md` (§ Safety + § Deferred), and **`docs/solutions/logic-errors/grdb-mismatched-fetch-windows-silent-zero-result-20260704.md`** (a bug this exact loader already had once — see trap 2).

## Exact files to touch

| File | Change |
|---|---|
| `Library/Content/InsulinImpact.swift` | Add `Equatable`, add `CorrectionExclusionReason` enum + `ScoredCorrectionObservation` struct (mirrors `MealExclusionReason`/`ScoredMealObservation`) |
| `Library/Content/RatioEstimator.swift` | Extend `RatioEvidence` (new field w/ default), `RatioEstimates` (3 new fields), scoring + median/spread for corrections, new constants |
| `App/Modules/RatioLab/RatioLabMiddleware.swift` | Extend `getRatioEvidence()` — same single `asyncRead` |
| `App/Views/Settings/RatioLabView.swift` | 4th StatCard (grid 3→2×2), CORRECTIONS evidence section, explainer sentence |
| `DOSBTSTests/RatioEstimatorTests.swift` | Correction qualification matrix + gating + median/spread tests |
| `DOSBTSTests/InsulinImpactTests.swift` | Exclusion-reason tests for the new enum |
| `CHANGELOG.md` | `Added` entry — DMNC-1303 |

**Do NOT touch:** `DirectState.swift`, `AppState.swift`, `DirectAction.swift`, `DirectReducer.swift`, `UserDefaults.swift` — see trap 1.

## Design decisions (already made — do not re-litigate)

- **Observation payload = `InsulinImpact` itself.** The loader constructs `InsulinImpact` values via `InsulinImpact.compute(for:glucoseAtDose:glucoseAtPeak:peakOffsetMinutes:iobAtDose:confounders:)`. Semantics for corrections: `glucoseAtPeak` carries the **post-dose nadir** (glucose at peak *insulin effect*), so `deltaMgDL` is **negative** for an effective correction. Empirical ISF per observation = `-deltaMgDL / dose.units`, valid only when `deltaMgDL < 0`.
- **`iobAtDose` stays `nil` in this version.** `computeIOB` evaluates "now"; retrospective at-date IOB is new machinery. Stacking is detected by bolus proximity instead (below). Leave a one-line comment saying exactly this.
- **Clean-correction qualification** (constants in `RatioEstimator`, mirror the existing naming style):
  - `correctionEffectWindowMinutes = 240` — nadir searched in `[t+30, t+240]` min.
  - `correctionMinDoseUnits = 0.5` (reuse spirit of `minPairedBolusUnits`).
  - glucoseAtDose = nearest SensorGlucose within ±10 min of dose (`correctionBaselineToleranceMinutes = 10`); none → excluded `NO BASELINE`.
  - glucoseAtDose < `correctionMinStartMgDL = 140` → excluded `LOW START` (maps to `InsulinConfounder.correctionForLow`; a correction from near-range tells you little and risks hypo-confusion).
  - any meal entry (`MealEntry`) with carbs ≥ `minCarbsGrams` (15g, existing constant) in `[t-120min, t+240min]` → excluded `MEAL IN WINDOW`.
  - any *other* bolus (meal/snack/correction) in `[t-180min, t+240min]` → excluded `STACKED` (`InsulinConfounder.stackedBolus(units:)`).
  - any `ExerciseEntry` overlapping `[t, t+240min]` (`startTime`/`endTime` fields) → excluded `EXERCISE` (`InsulinConfounder.exerciseInWindow`).
  - fewer than `correctionMinReadings = 8` CGM readings in the window → excluded `NO CGM`.
  - `deltaMgDL >= 0` (glucose didn't fall) → excluded `ROSE` — still a teaching row.
  - per-observation ISF outside `[correctionMinISF = 10, correctionMaxISF = 200]` mg/dL/U → excluded `ODD ISF`.
- **Aggregate:** median of qualifying per-observation ISFs; spread = P25–P75 (copy the exact percentile helper the empirical ICR uses); gate `minQualifyingCorrections = 5`.
- **Candidate cap:** score at most the **most recent 20** corrections (`maxCorrectionCandidates = 20`) to bound per-candidate glucose reads; show at most `maxConfoundedEvidenceRows`-style capping only for excluded rows if the section gets long (mirror existing: qualifying rows always shown, excluded capped at 5).

## Implementation steps (in order)

1. **`InsulinImpact.swift`**: add `Equatable` conformances (`InsulinConfounder`, `InsulinImpact` — `InsulinDelivery` is Codable+Identifiable; check if Equatable, add if missing). Add:
   ```swift
   enum CorrectionExclusionReason: Equatable {
       case noBaseline, lowStart, mealInWindow, stacked, exercise, noCGM, rose, tinyDose, oddISF
   }
   struct ScoredCorrectionObservation: Equatable {
       let impact: InsulinImpact
       let isfMgDLPerUnit: Double?   // nil when excluded
       let exclusion: CorrectionExclusionReason?
   }
   ```
2. **`RatioEstimator.swift`**:
   - `RatioEvidence`: add `let correctionImpacts: [InsulinImpact]` and give it a **defaulted custom init** (`correctionImpacts: [InsulinImpact] = []`) so the two existing fallback constructions in `RatioLabMiddleware.swift` (`.catch` fallback and the `dbQueue == nil` guard, plus two early-`promise(.success(...))` paths) compile unchanged.
   - `RatioEstimates`: add `let empiricalISFMgDL: Double?`, `let empiricalISFSpread: ClosedRange<Double>?`, `let scoredCorrections: [ScoredCorrectionObservation]`.
   - New pure functions: `scoreCorrections(_ impacts: [InsulinImpact]) -> [ScoredCorrectionObservation]` (applies the exclusion ladder in the order listed above — first failing gate wins, matching how meal scoring reports a single reason) and median/spread aggregation folded into `estimate(evidence:)`.
   - Add the constants from the design section.
3. **`RatioLabMiddleware.swift` — extend `getRatioEvidence()` inside the SAME `asyncRead`:**
   - `let corrections = allDeliveries.filter { $0.type == .correctionBolus }.suffix(maxCorrectionCandidates)` — `allDeliveries` is already fetched over the **30-day** `mealImpactCutoff` window; reuse it, do not add a second delivery fetch.
   - Fetch once, filter in Swift: `ExerciseEntry` over the same 30-day cutoff; `MealEntry` needs meals near corrections that may not be in `mealById` (which only covers impact meals) — fetch `MealEntry` over the same 30-day cutoff once.
   - Per correction: one `SensorGlucose` fetch `[starts-10min, starts+240min]` ordered by timestamp → glucoseAtDose (nearest within ±10 min) + nadir in `[starts+30min, starts+240min]` + reading count. Detect confounders from the in-memory meal/exercise/delivery arrays. Build `InsulinImpact.compute(...)` with `confounders` populated even for excluded rows (the scorer maps confounders → exclusion reasons; keep detection in the loader, classification in the estimator — same split as meals: loader gathers, `RatioEstimator` judges).
   - Return `RatioEvidence(tddDays:..., mealObservations:..., correctionImpacts: builtImpacts)`.
4. **`RatioLabView.swift`**:
   - `estimatesGrid`: change to 2 flexible columns (2×2). Card 4: `StatCard(label: "YOUR CORRECTIONS", value: correctionsValue(estimates), help: correctionsHelp(estimates))` where value = `estimates.empiricalISFMgDL` rendered via the **existing ISF pattern**: `Int(isf.rounded()).asGlucose(glucoseUnit: store.state.glucoseUnit)`; gated → `—`. Help mirrors YOUR MEALS: `"n=X · LOW–HIGH SPREAD"` (spread bounds converted with `.asGlucose(...)` too!) or `"X/5 CORRECTIONS"` while gated.
   - New `correctionsTable(_:)` section under the meals EVIDENCE table, header `Text("CORRECTIONS").dosHeader()`, rows via a new private `CorrectionEvidenceRow` modeled line-for-line on `RatioEvidenceRow`: timestamp label, `X.XU` dose line, right side `isf.asGlucose(...) + "/U"` in amber for qualifying, exclusion tag in `amberDark` for excluded (`LOW START`, `MEAL IN WINDOW`, `STACKED`, `EXERCISE`, `NO CGM`, `ROSE`, `TINY DOSE`, `ODD ISF`, `NO BASELINE`). `ROSE` is not red — only hypo-class lessons use `cgaRed`, and rising after a correction is not a hypo.
   - Explainer card: append one sentence: `Text("Your corrections estimates ISF from doses given with no food, exercise, or stacked insulin nearby.")`.
   - Show the corrections section only when `!estimates.scoredCorrections.isEmpty` (mirrors the meals table guard).
5. **Tests** (extend the two EXISTING files — see trap 5):
   - `RatioEstimatorTests.swift`: qualification matrix — clean correction yields expected ISF; each exclusion reason triggered by exactly its gate (low start / meal in window / stacked / exercise / no CGM / rose / tiny dose / odd ISF / no baseline); n=4 → `empiricalISFMgDL == nil` with 4 scored qualifying rows; n=5 → median; even-count median; P25–P75 spread values pinned; excluded rows never enter the median.
   - `InsulinImpactTests.swift`: negative-delta semantics for corrections (nadir < start → deltaMgDL < 0).
6. Build both targets, run suite, CHANGELOG entry, PR.

## Cases a weaker model would miss

1. **No Redux changes.** `ratioEvidence` (transient) and the `.setRatioEvidence` action already exist; extending the `RatioEvidence` *struct* rides the existing action/reducer untouched. There is **deliberately no `ratioEvidenceLoading` flag** — `nil` evidence IS the loading state and re-entry shows stale-until-fresh (header comment in `RatioLabView.swift:28-34`). Do not add one.
2. **Matched fetch windows — this loader already shipped this bug once.** Every array you filter in Swift (deliveries, meals, exercise) must cover the SAME 30-day `mealImpactCutoff` window; a narrower fetch silently returns zero matches downstream with no error (see `docs/solutions/logic-errors/grdb-mismatched-fetch-windows-silent-zero-result-20260704.md`, dated four days before this plan — same function, same failure shape).
3. **One `asyncRead`, zero writes.** All new fetches go inside the existing `dbQueue.asyncRead` block. A `dbQueue.write` anywhere inside deadlocks the whole app (`docs/solutions/logic-errors/grdb-write-inside-asyncread-deadlock-20260420.md`). Also keep the `.catch → empty RatioEvidence` fallback: a thrown error otherwise leaves the screen spinning forever (comment in the middleware explains why).
4. **`RatioEvidence` is constructed in FOUR fallback places** in the middleware (catch handler, nil-dbQueue guard, calendar guard, empty-impacts early return). If you add a field without a default value, all four break — use the defaulted init. Grep `RatioEvidence(` in the middleware to confirm you got them all.
5. **New test FILES require manual pbxproj registration** (`DOSBTSTests` group + `PBXSourcesBuildPhase` — tests are NOT `fileSystemSynchronized`). Extending `RatioEstimatorTests.swift` / `InsulinImpactTests.swift` avoids this entirely. If you must add a file, follow CLAUDE.md § "Adding New Files".
6. **mmol/L everywhere a glucose figure appears**: the card value, the spread bounds in the help line, and the per-row ISF all go through `.asGlucose(glucoseUnit:)`. The meals card only converts the value — the ISF *spread* is a new surface; converting the value but not the spread is the likely slip. `deltaMgDL` stays mg/dL internally; convert at render only.
7. **Plausibility discipline**: individual observations outside `[10, 200]` mg/dL/U are excluded as `ODD ISF` (a clinically implausible figure must not anchor a safety screen — same reasoning as `rulePlausible` suppressing the 500/1800 cards, see `RatioLabView.swift:241-249`).
8. **Grid change is 3→2×2, not 4-in-3.** Leaving four `StatCard`s in the current 3-column `LazyVGrid` puts an orphan card on row 2 — change the `columns:` array to two `.flexible()` items.
9. **`suffix(maxCorrectionCandidates)` on a time-ASCENDING array keeps the most recent** — `allDeliveries` is ordered ascending by `starts` (see the `.order(...)` in the fetch); `prefix` would keep the *oldest* 20.
10. **Safety copy rules** (repo-hard): no imperative dosing language anywhere; the section inherits the existing `REFERENCE ESTIMATES — NOT DOSE ADVICE` caption and the footer disclaimer — do not remove or reword either; the "exclusions are the lesson" pattern means excluded rows are *shown dimmed with tags*, not hidden.
11. **Sparse data is the expected state, not a bug.** DMNC-1303 was deferred precisely because clean corrections are rare. `0/5 CORRECTIONS` with a populated exclusions list is a SUCCESSFUL outcome of this feature — do not "fix" it by loosening gates.
    **User-verified 2026-07-10:** Dom confirmed he logs standalone corrections with the CORRECTION type, so the `.correctionBolus` type filter is the correct candidate rule — do NOT widen it to infer corrections from meal-less snack boluses; that idea was considered and rejected at planning time.
12. **`InsulinConfounder` needs `Equatable`** for the scored types to conform — `stackedBolus(units: Double)` has an associated value; derive conformance, don't hand-write `==`.

## Acceptance criteria

1. Both `xcodebuild ... DOSBTSApp ... build` and `... DOSBTSWidget ... build` succeed (`InsulinImpact`/`RatioEstimator` are in `Library/` and compile into the widget — a signature mistake breaks BOTH).
2. Full suite green including all new tests; `StyleGuardTests` green.
3. New tests demonstrably pin the matrix: temporarily flip one exclusion constant (e.g. `correctionMinStartMgDL` 140→0) → at least one test fails; restore → green.
4. Simulator (VirtualConnection): Ratio Lab shows a 2×2 estimates grid; YOUR CORRECTIONS shows `—` + `0/5 CORRECTIONS` on a fresh install; with seeded history (log a correction bolus + no meal, wait for readings) rows appear under CORRECTIONS with tags.
5. Switching Settings → Glucose & Display unit to mmol/L converts the card value AND the spread help line AND row ISFs.
6. `grep -rn "InsulinImpact" App/ Library/ --include="*.swift" | grep -v Tests` now shows production call sites in `RatioLabMiddleware.swift` and `RatioEstimator.swift`/`RatioLabView.swift`.
7. CHANGELOG `[Unreleased]` `Added` entry ` — DMNC-1303`.

## Bookkeeping

Linear DMNC-1303 → In Progress / Done. Commit style: `feat(ratio-lab): empirical ISF from clean corrections (DMNC-1303)`. After merge, consider a `docs/solutions/` capture if the loader work surfaces anything new (repo compound-learning habit).
