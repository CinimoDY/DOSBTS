# Chart Lab P3 — implementation notes (DMNC-1503, `LAB: SWEEP`)

Worker notes for the orchestrator. Newest entry on top. Folded into the PR body and
`git rm`'d before merge, per the plan.

---

## Deviations from the plan

### D1 — `SweepStatistics` cannot call `computeMealOverlayDelta` / `detectMealConfounders`

**Plan said** (Architecture → "Math to reuse"): "If P2's `ResponseKernel` is on `main` when you
branch, call it; otherwise call these and note it" — i.e. call
`computeMealOverlayDelta` / `detectMealConfounders` from `App/Views/Overview/MealOverlayLogic.swift`.

**What I found.** P2's `ResponseKernel` is indeed not on `main` (P2 runs in parallel). But the
fallback is not reachable either: the plan also puts `SweepStatistics` in
`Library/Content/MealSweep.swift`, and the kickoff constraints require **both targets to build**.
`Library/` is compiled into `DOSBTSWidget`; `App/` is not. A `Library/Content` file that
referenced `MealOverlayLogic` (which lives under `App/` and imports SwiftUI) would fail the
widget build outright.

**What I did.** `SweepStatistics.build` re-implements the baseline / peak / confounder rules in
pure Foundation, with the source lines quoted in the doc comment, and
`ChartLabSweepTests` carries a **parity suite** that runs the shipping App helpers and the new
Library builder over the same fixtures and asserts they agree on the delta and on the
clean/confounded verdict. That is a stronger guarantee than a call would have been: when P2
rewrites `MealOverlayLogic`'s internals, the parity test is what fails.

### D2 — `TwinFinder.summary` returns a struct, not a tuple

Plan: `static func summary(of twins: [MealSweep]) -> (medianDelta: Int, medianPeakMinutes: Int, n: Int)?`.
Shipped: `-> TwinSummary?` (`struct TwinSummary: Equatable`). An optional labelled tuple is not
`Equatable` and cannot be a parameter of the pure LAPS formatter without being destructured at
every call site. Field names and semantics are unchanged.

### D3 — `MealSweep` carries `mealDescription`

The plan's struct sketch has `carbs` but no name, and the LAPS card's title in the artboard is
`LAPS · 80g DINNER` — the name is load-bearing. Added `let mealDescription: String`.

### D4 — the y domain floors in **both** directions

Plan: `yMin = −20`, `yMax = max(100, ceil(maxDelta/20)*20)`. P0's errata ("the y domain is a
floor, not a fixed ceiling") applies equally at the bottom: a meal followed by a hypo produces
deltas well below −20 and a fixed −20 would clip them away silently. Shipped
`bottom = min(−20, floor(minDelta/20)*20)`, `top = max(100, ceil(maxDelta/20)*20)`, both in
mg/dL, converted once for the scale. Every plotted series (sweeps, the p25–p75 band, the median
and today's trace) feeds the same computation, as the errata requires.

### D5 — twins exclude in-progress sweeps

Not stated in the plan. A meal whose 2 h window has not closed has no final delta or peak, so it
cannot be a comparison. Pinned by a test.

### D6 — the bucket/CLEAN chips are a private button inside `LabSweepView.swift`

The instruction says to reuse P0's tab-row style. `ChartTabButton` in `ChartToolbar.swift` is
`private`, so it cannot be referenced. Rather than widen its access (a shared file five parallel
branches also touch), `LabSweepView.swift` carries a private `LabChipButton` with the same font /
padding / 2 pt underline treatment. No shared file is touched.

### D7 — the non-today LAPS label is `ND AGO`, not a formatted date

Locale-dependent month names would make the pure formatter's test locale-dependent. The artboard
only ever shows `TODAY`; the fallback is `2D AGO`.

---

## Sweep rendering — the ForEach vs LinePlot measurement

(filled in during Task 4 verification)

---

## Simulator verification

(filled in at the end)
