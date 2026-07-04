# DMNC-1299: Ratio Lab UI — workbench screen, guidance checklist, evidence table

**Date:** 2026-07-04
**Branch:** claude/dmnc-1299
**Blocked by:** DMNC-1298 (WP-R2 — state/actions/middleware consumed here)

Part of the Ratio Lab track ([DMNC-1291](https://linear.app/lizomorf/issue/DMNC-1291)). This is **WP-R3**, the UI layer — the last of the R1 (estimator) → R2 (wiring) → R3 (UI) sequence. Spec: `docs/plans/2026-07-03-ratio-lab-plan.md § WP-R3 + the Safety rules section`.

## What changed

### `App/Views/Settings/RatioLabView.swift` (new, ~450 LOC)

A plain `ScrollView` workbench (not a `List`), top-to-bottom: explainer `.dosCard(.info)` → ESTIMATES grid (3 × `StatCard`: 500 RULE / YOUR MEALS / 1800 RULE ISF) → `REFERENCE ESTIMATES — NOT DOSE ADVICE` caption → `COLLECTING EVIDENCE n/5` line (empty state) → REFERENCE row (`SET 1:X AS REFERENCE` / `CLEAR` → `.setConfirmedICR`) → EVIDENCE table (`RatioEvidenceRow`, newest-first, excluded meals dimmed with a teaching tag replacing the ratio) → always-on `CleanExperimentCard` checklist → safety footer. Renders `RatioEstimator.estimate(evidence:)` (pure).

### `App/Views/Settings/InsulinSettingsView.swift`

New "Ratios" `Section` — `Label("Ratios", systemImage: "function")`, a `NavigationLink` "Ratio Lab" (pushes inside SettingsView's existing `NavigationStack`, no sheets), a `REF 1:X` line once a reference is set, and the footer "…Reference only."

### `CHANGELOG.md` + `CLAUDE.md`

`[Unreleased]` Added entry; a "Ratio Lab" architecture bullet documenting the screen composition, the memoized-estimate loading model, and the safety hard rules.

## Code-review fixes folded in (xhigh workflow review)

A workflow-backed xhigh review (10 finders → 32 candidates → 12 reported) ran against the first cut; all real findings were addressed before opening the PR:

- **Today's boluses were dropped (`RatioLabMiddleware`).** The WP-R2 loader fetched `InsulinDelivery` filtered `< startOfToday` and used that same set for BOTH TDD *and* bolus pairing — so a meal logged today paired to 0 U and was mislabeled `NO BOLUS`, silently excluded from the sample. Fix: widened the fetch to include today; `RatioEstimator.tddDays` already re-filters `< startOfToday` internally, so TDD still counts only complete days while pairing now sees today's boluses.
- **Infinite loading spinner on DB read error (`RatioLabMiddleware`).** `getRatioEvidence()` can emit `.failure`, which the Store logs but never re-dispatches → `.setRatioEvidence` never lands → the nil-as-loading screen spins forever. Fix: `.catch` → log + fall back to empty evidence, so the screen lands on its safe empty/"collecting" state.
- **Rule cards unclamped.** A low median TDD could display `1:100` / `360 ISF` as reference figures (the empirical path clamps 2–50 g/U, these didn't). Fix: one plausibility gate — if `500/TDD` ∉ [2,50] both rule cards are suppressed (`—`), which also keeps ISF in a sane ~[7,180] band since ISF = 1800/TDD.
- **mmol/L users saw raw mg/dL.** The `ENDED +54` return-delta tag and the CLEAN EXPERIMENT numbers (`80–180`, `±30`) were bare mg/dL. Fix: routed every glucose figure through the shared `Int.asGlucose(glucoseUnit:)` formatter (locale-correct). The checklist numbers are now sourced from the estimator's own gate constants (`baselineMinMgDL`=70 / `baselineMaxMgDL`=180 / `returnToBaselineToleranceMgDL`=30) so the taught method can't drift from the code (also fixed the "80 vs 70" mismatch the reviewer flagged).
- **Cleanups:** memoized the estimate into `@State` (recompute on `ratioEvidence` change, not on every ~1/min glucose publish); extracted the `1:X` label into `RatioEstimator.icrLabel(_:)` — shared by the grid, evidence rows, and the Settings `REF` line — with a `.isFinite` guard so bad data renders `—` instead of trapping `Int(_:)`; locale-aware evidence-row timestamp via `.formatted(.dateTime…)` instead of a hard-coded `d MMM HH:mm`; stable `ForEach(id: \.observation.meal.id)`.

## Decisions worth flagging

- **Confounded meals are omitted, not tagged — accepted limitation.** The `.confounded` teaching tag is unreachable because the WP-R2 loader filters `MealImpact.isClean == true` (per `docs/plans/… § WP-R2`). Surfacing confounded meals as `CONFOUNDED` rows would need the loader to also fetch un-clean impacts — a change to the shipped R2 contract, out of scope here. The defensive `.confounded` UI branch stays. Candidate follow-up issue if dogfooding shows users want to see *why* a confounded meal didn't count.
- **No set-date on the reference.** WP-R2 persists only `confirmedICR: Double?` (no timestamp), so the reference row shows `REF RATIO 1:X` without the "SET 14 JUN" the plan sketch illustrated — adding a set-date would be a new persisted property outside R3's scope.
- **Middleware fixes folded into the R3 PR.** Two of the review findings live in the WP-R2 `RatioLabMiddleware`, but they materially break the R3 UX (a NO-BOLUS-mislabeled today's meal, an infinite spinner), so they're fixed here rather than deferred.
- **Safety hard rules honoured:** no imperative dosing language, no carbs-in→units-out field, every number ships with N/spread, both fixed disclaimers present.

## Tests

`** TEST SUCCEEDED **` — full `DOSBTSTests` suite green (incl. all 8 `StyleGuardTests` source-scan rules — tokens only, sharp corners, `DOSTypography`, no bare `ProgressView()`), app + widget both build, on iPhone 17 Pro / iOS 26.5. Empty→gated→full visual acceptance (and the mmol toggle) is the human reviewer's step per the plan.
