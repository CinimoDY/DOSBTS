---
module: "RatioLabMiddleware / DataStore"
date: "2026-07-04"
problem_type: logic_error
component: database
severity: medium
symptoms:
  - "Confounded meal rows in the Ratio Lab evidence table showed only carbs in the macro line (e.g. '60g') with no insulin amount, even though the user had logged a bolus for the meal"
  - "pairedBolusUnits returned 0 for confounded meals 15–30 days old despite boluses existing in the database"
  - "No error or warning — the macro line silently showed incomplete data"
root_cause: scope_issue
resolution_type: code_fix
tags:
  - grdb
  - fetch-window
  - ratio-lab
  - paired-bolus
  - data-integrity
---

## Problem

When the Ratio Lab's `getRatioEvidence()` loader was widened to include confounded (non-clean) `MealImpact` rows alongside clean ones, the `InsulinDelivery` fetch that feeds `pairedBolusUnits` still used the narrower 14-day TDD window (`tddWindowStart`). Confounded impacts span the same 30-day window as clean ones, so any confounded meal older than 14 days was missing its bolus in the `allDeliveries` array passed downstream.

## Symptoms

- `RatioEvidenceRow.macroLine` renders `"60g"` instead of `"60g/5.0U"` for confounded meals from days 15–30.
- `RatioEstimator.pairedBolusUnits(mealTimestamp:deliveries:)` returns `0.0` — no match in the delivery array — even though the database contains the bolus.
- No crash, no assertion, no log output. The symptom only surfaces in the UI.

## What Didn't Work

Checking the estimator's `pairedBolusUnits` logic first — the ±15-minute window and type filter looked correct. The bug was upstream: the delivery array passed to it had already been truncated.

## Solution

Extend the `InsulinDelivery` fetch to use `mealImpactCutoff` (30 days) instead of `tddWindowStart` (14 days):

```swift
// Before: delivery window tied to TDD lookback (14 days)
let allDeliveries = try InsulinDelivery
    .filter(Column(InsulinDelivery.Columns.starts.name) >= tddWindowStart)
    .order(...)
    .fetchAll(db)

// After: delivery window matches the wider meal-impact cutoff (30 days)
let mealImpactCutoff = now.addingTimeInterval(-30 * 24 * 3600)
let allDeliveries = try InsulinDelivery
    .filter(Column(InsulinDelivery.Columns.starts.name) >= mealImpactCutoff)
    .order(...)
    .fetchAll(db)
```

`RatioEstimator.tddDays(from:asOf:calendar:)` re-filters deliveries to the last 14 complete days internally, so TDD computation is unaffected by the wider array.

## Why This Works

`pairedBolusUnits` looks for deliveries within ±15 minutes of a meal timestamp. If the delivery array starts at day 14 but the meal is at day 20, the bolus simply isn't present — the function returns 0 without error. Widening the delivery array to cover the full 30-day range guarantees all meals in the lookup range have their boluses available.

## Prevention

**When widening a query to cover more rows, audit every related fetch that supplies data for those rows.**

A common pattern in this codebase's `asyncRead` blocks: one primary fetch drives row selection, and several secondary fetches supply per-row data (delivery pairing, glucose windows, meal metadata). If the primary fetch is widened without widening the secondary fetches, the downstream computation silently receives partial or empty data — no error, just zeros or nulls.

Checklist when extending a fetch window:
1. List all computations that operate on the rows the primary fetch returns.
2. For each computation, identify every secondary fetch it depends on.
3. Verify that each secondary fetch covers at least the same date range as the primary.
4. Write a test or at minimum a comment anchoring the window relationship.

In this codebase, `pairedBolusUnits` is the key one: its delivery array must span at least as far back as the oldest impact being resolved.
