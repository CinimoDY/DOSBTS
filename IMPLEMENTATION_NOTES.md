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

### D8 — `SweepStatistics.build` had to window the reading series, not scan it

**Not a plan deviation — a bug the simulator run exposed.** The first implementation resolved
each meal's baseline, response window and 55 grid points by `filter`ing the whole readings array.
That is O(meals x steps x readings): 271 meals over a 90-day 5-minute series (25 922 readings) is
~390 M comparisons, and the 90 d chip took **15-20 s** to draw, spinning the loading pulse the
whole time. The array is time-ascending, so each meal now takes ONE binary-searched slice
(`lowerBound`) covering `[t-35 min, t+245 min]` and everything is resolved inside it.

Measured on the fixture, same device, same build settings:

| stage | before | after |
|---|---|---|
| `SweepStatistics.build` (271 meals, 25 922 readings, off-main) | 15-20 s (inferred from the visible load) | **74 ms** |
| cold launch to a drawn 90 d chart | > 20 s | **< 2 s** |

Pinned by two new tests: `slicingIsExact` (a meal's sweep is byte-identical whether it is built
alone or inside a 3-day multi-meal series - guards the binary search's off-by-one) and
`buildsLargeFixtureQuickly` (270 meals over ~26 000 readings under 3 s; the scanning version
missed that by two orders of magnitude).

### D9 — three visual fixes the artboard could not have predicted

1. **The `MEDIAN - n CLEAN` and `TODAY +N` annotations were illegible** drawn straight onto the
   sweep cloud. The artboard gets this for free with SVG `paint-order: stroke fill` + a 3 px black
   stroke; SwiftUI has no text-stroke, so both annotations now carry a `dosBlack` ground with
   `DOSSpacing.xxs` of horizontal padding.
2. **The `+4h` x-axis label was silently dropped.** It is centred on the plot's trailing edge,
   under the y-axis label gutter, and `AxisValueLabel`'s default `.automatic` collision
   resolution removes it - so the axis stopped saying where the window ends. Fixed with
   `collisionResolution: .disabled` plus `anchor: .topTrailing` on the last tick only. (This is
   the same class of nit P0 accepted for its edge hour labels; here the label carries the
   window length, so it was worth fixing rather than documenting.)
3. **At 30-90 days the cloud saturated** and swallowed both aggregate marks. The artboard was
   drawn at 23 sweeps; at 269 the p25-p75 wash and the median disappeared into solid amber. Added
   the pure `SweepChartMath.densityOpacity(count:base:)` - a no-op at or below the artboard's
   density (20 sweeps), ~0.22x at the 120 cap, floored at `minSweepOpacity` 0.12 - applied to all
   three age tiers. Pinned by `SweepDensityTests`.

### D10 — the expanded twin list sank the persistent bottom bar

With `WHY THESE` expanded, five twin rows pushed the page past its height and the INSULIN/MEAL
bar slid under the tab bar - the documented
`swiftui-vstack-overflow-sinks-safeareainset` failure. The expanded list is now a `ScrollView`
capped at `twinListMaxHeight` (60 pt, four rows visible), so the card's growth is bounded.

### D11 — the count caption claimed `N=0` while the first load was in flight

`N=0 SWEEPS - 0 CLEAN` next to a loading pulse reads as a finding. The caption is blank until
`labSweeps != nil`.

---

## Sweep rendering - the ForEach vs LinePlot measurement

The plan asked for a measurement before choosing between `ForEach` of `LineMark`s and the iOS 18
vectorized `LinePlot`. Temporary `DirectLog` timers around the Chart content builder, the view's
render-model build and `SweepStatistics.build`, read back out of the app's own
`Documents/Logs/AllLogs.log` and removed afterwards. iPhone 17 Pro simulator, iOS 26.4, Debug,
the 90-day fixture (271 meals / 25 922 readings):

```
SWEEPPERF stats-build  74ms  meals=271 readings=25922      (off-main, in the middleware)
SWEEPPERF model-build  30ms  sweeps=271 drawn=119          (main thread, on the inputs gate)
SWEEPPERF chart-marks   0ms  lines=119 points=6545         (the ForEach mark construction)
```

Per-chip samples, tapped live on the device:

```
16-45  model-build 11ms  drawn=90   chart-marks 0ms  points=4950
ALL    model-build 30ms  drawn=119  chart-marks 0ms  points=6545
>80    model-build  2ms  drawn=24   chart-marks 0ms  points=1320
```

**Choice: keep `ForEach`.** Building 6 545 `LineMark`s across 119 series measures as under 1 ms,
so the vectorized `LinePlot` would be optimising the one stage that costs nothing, at the price
of its per-series styling (the age tiers and the confounded dash would have to move to
`foregroundStyle(by:)` + `chartForegroundStyleScale` and `lineStyle(by:)`). The 30 ms main-thread
cost is the render-model rebuild, which `LinePlot` would not touch. Chip taps were visually
instant. **Caveat:** this is mark-construction and model-build timing, not a frame-drop trace -
true frame accounting needs Instruments on a device, which is not available to this worker.

---

## Simulator verification

iPhone 17 Pro (`60D83334-1820-41BC-8056-5D921FD8296B`), iOS 26.4. Fixture seeded straight into
the app's GRDB file: 90 days of 5-minute readings (25 945 rows) with plausible post-meal
excursions, 271 meals (breakfast 45 g / lunch 60 g / dinner 75-95 g per day, all bolused), an
in-progress 80 g dinner 40 min before "now", ONE correction bolus 30 min into the previous day's
dinner, ONE 30-minute run overlapping a lunch, and a 10 g snack with no bolus. Screenshots in
`$TMPDIR/p3-shots/`.

| # | Step | Result |
|---|---|---|
| 1 | Lab on, `LAB: SWEEP` loads; caption `N=... SWEEPS - ... CLEAN`; axis `t=0 ... +4h`; sweeps align at t=0 with the baseline at 0 | **PASS** - `N=271 SWEEPS - 269 CLEAN` at 90 d, `N=22 - 20 CLEAN` at 7 d. Exactly 2 of 271 are non-clean: the correction-bolus dinner and the exercise-overlapped lunch. Axis reads `t=0 +1h +2h +3h +4h` |
| 2 | The corrected meal is dashed; older meals fade; the median and wash exist once >= 3 clean sweeps | **PASS** - the dashed confounded trace is plainly visible in the 7 d crop, with the p25-p75 wash behind the bright median. The age fade is only observable over 30/90 d (a 7 d window is entirely inside the "recent" tier) and is visible there |
| 3 | Chips filter by bucket; `CLEAN ONLY` hides dashed sweeps and recomputes the wash; caption N updates | **PASS** - real taps: `46-80` -> `N=13 - 11 CLEAN`, `>80` -> `N=24 - 24 CLEAN`, `16-45` -> 90 drawn, `ALL` -> 119 drawn. `CLEAN ONLY` on -> `N=269 - 269 CLEAN` (the 2 confounded drop out) |
| 4 | Log a meal now -> it appears as the amberLight in-progress trace with `TODAY +D`; the LAPS card names it and its twins; `WHY THESE` expands the list | **PASS** - `TODAY +43` on the pale trace with its end dot; `LAPS - 80g DINNER` / `TODAY +43 (40 MIN) - TWINS MEDIAN +62 - PEAK 60 MIN (n=5)`; expanded: `2D AGO - 78g - +59 (60 MIN) - CLEAN` and four more. (The in-progress meal came from the seeded fixture rather than the Log Meal sheet - same code path, `.addMealEntry` re-trigger is registered in both middleware arrays) |
| 5 | 7d/30d/90d chips reload; `ALL` behaves as 90 d | **PASS** for 7d/30d/90d (`N=22 / 91 / 271`). `ALL` **NOT TAPPED** - `LabSweepStore.effectiveDays` clamps the 9999 sentinel to 90 and is unit-pinned (`daysCap`), but the chip itself was not exercised on the device |
| 6 | mmol/L users see `D mmol/L` and converted values | **PASS** - `D mmol/L from -15 min`, axis `+4,4 / +2,2 / +0 / -2,2`, `TODAY +2,4`, `TWINS MEDIAN +3,4`, locale decimal comma throughout |
| 7 | GLUCOSE tab unchanged; lab off -> nothing renders | **PASS** - with the lab off the row is `GLUCOSE - TIME IN RANGE - STATISTICS`, the shipping chart, marker lane, hour chips and persistent bar are untouched |

### How the interactive steps were driven, and what that is worth

Four other worker simulators were live on the same Mac display throughout, and windows were
raised out from under the cursor mid-sequence. Steps 3 and 5 were driven by **real taps** on this
device's window (verified frontmost immediately before each click). Two states were reached by
**temporarily flipping the view's `@State` defaults** in a throw-away build rather than by
tapping, because a mis-aimed click would have landed in a sibling worker's app:

- `CLEAN ONLY` **on** and `WHY THESE` **expanded** (screenshot 06) - this proves the *rendering*
  of both states, not the tap wiring. The tap wiring is the same `LabChipButton` /
  `Button(.plain)` shape that steps 3 and 5 exercised for real.
- The 90 d window, via a temporary `AppState.statisticsDays = 90` default.

Every temporary edit is reverted; `grep -rn "TEMPVERIFY|SWEEPPERF" App/ Library/` is empty and
the final test run and both target builds are from the reverted tree.

### Needs a human

- Nothing is device-only here (no haptics, no audio). The remaining gaps are the `ALL` chip tap
  and a real `CLEAN ONLY` / `WHY THESE` tap, both one gesture each on any build.
