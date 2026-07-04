# DMNC-1307: Ratio Lab — Surface Confounded Meals as CONFOUNDED Evidence Rows

## What changed

Widened `DataStore.getRatioEvidence()` in `App/Modules/RatioLab/RatioLabMiddleware.swift` to also fetch non-clean (`isClean == false`) `MealImpact` rows alongside the existing clean ones.

**Before:** The loader fetched only `MealImpact` rows where `isClean == true`. Confounded meals (correction bolus in window / overlapping exercise / stacked meal) were silently discarded — they never reached the evidence table, so users had no way to know why their meal didn't count.

**After:** Up to 3 of the most-recent confounded impacts (same 30-day window) are fetched and resolved through the same MealEntry join + glucose window + bolus pairing pipeline as clean ones. The estimator's existing criterion 1 (`if !observation.impact.isClean { return excluded(.confounded) }`) naturally scores them as `.confounded` exclusions, and the UI's pre-existing `"CONFOUNDED"` teaching tag surfaces them in the evidence table.

## Why

The "exclusions teach the method" design philosophy in the Ratio Lab is that users *learn from seeing why a meal didn't qualify*. Confounded meals are the most common exclusion, yet they were invisible. The estimator and UI already had dead code for exactly this case (`.confounded` in `MealExclusionReason`, `"CONFOUNDED"` in `RatioEvidenceRow.tag(for:)`) — the loader just needed to supply the data.

## Capping rationale

Confounded rows are capped at 3 (most-recent) via `DataStore.maxConfoundedEvidenceRows`. A user who eats every meal near a correction bolus would otherwise generate 30 days × multiple meals of confounded rows, drowning out the clean qualifying rows that actually drive the estimates. The cap keeps the table legible while still surfacing the teaching signal.

## No estimator or UI changes needed

- `RatioEstimator.score()` already enforces `isClean == false → .confounded` exclusion at criterion 1 — a loader regression (passing confounded impacts as if clean) cannot pollute the empirical median.
- `RatioEvidenceRow.tag(for:)` already maps `.confounded → "CONFOUNDED"`.
- Both were dead code in production until this change.

## Files changed

- `App/Modules/RatioLab/RatioLabMiddleware.swift` — added step 2b (confounded impact fetch), updated guard to use `allImpacts`, updated steps 3–4 to process all impacts, added `maxConfoundedEvidenceRows` constant.
