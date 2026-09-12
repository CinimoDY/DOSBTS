# Chart Lab P3 — `LAB: SWEEP`: the event-locked response overlay — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven-development). Checkbox steps. Read the file at each anchor before editing; shipping-code anchors were verified on `main` @ `3a288d3d`; lab-platform anchors refer to the merged P0 PR — open `App/Views/Overview/Lab/*` first. Record every deviation in `IMPLEMENTATION_NOTES.md`.

**Issue:** DMNC-1503 (P3 half) · **Branch:** `feat/chart-lab-p3-sweep` · **Worktree:** `../DOSBTS-wt-lab-p3` · **Base:** `main` after P0 (DMNC-1504) merged · **Tier:** Opus · **Simulator:** `-destination 'id=60D83334-1820-41BC-8056-5D921FD8296B'` (iPhone 17 Pro, iOS 26.4; always by `id=`) · **pbxproj object IDs:** file ref `C1AB15030000000100A00001`, build file `C1AB15030000000100A00002` (P4 holds `…0200…`).

**Visual spec:** artboard **4 (Sweep)** — https://claude.ai/code/artifact/0f40d578-b3a3-460c-a651-aff0f3240dfb (`…/screens/Sweep.dc.html`). Copy: caption `N=23 SWEEPS · 14 CLEAN` and `Δ mg/dL from −15 min`; x-axis `t=0 · +1h … +4h` with a dashed rule at t=0; y-axis `−20 … +100`; sweeps in three age tiers (amber 0.55 / amberDark / textFaint), confounded ones dashed; the p25–p75 wash; the bright median with `MEDIAN · 14 CLEAN`; today's in-progress trace in amberLight with an end dot `TODAY +47`; the LAPS card `LAPS · 80g DINNER … WHY THESE ›` / `TODAY +47 (38 MIN) · TWINS MEDIAN +41 · PEAK 55 MIN (n=4)`; chips `ALL · ≤15 · 16–45 · 46–80 · >80`; legend `— OLDER · FAINTER · ╌ CONFOUNDED · ▬ P25–P75`.

**Intent (Dom, verbatim):** "there's no pattern view" and "can't see meal size" — this is the view that answers "what does a 60 g meal do to *me*" rather than "what does 15:00 look like".

**Goal:** A lab tab whose x-axis is minutes since the meal and whose y-axis is the change from the −15-minute baseline. Every meal in the last 7/30/90 days is one sweep aligned at t=0; older sweeps fade; confounded ones are dashed; a median and a p25–p75 wash emerge from the clean ones; today's in-progress meal is drawn on top; a LAPS card compares it with its closest twins.

## Architecture (verified findings)

- **Platform seam (P0):** `ReportType.labSweep` exists with `usesDayWindow == true` (7d/30d/90d/ALL chips drive `statisticsDays`, `ChartToolbar.swift:106-116`; `normaliseDaysIfNeeded` bumps stale values). `ChartView.swift` currently routes `.labSweep` to `LabPlaceholderView(tab: .labSweep)` — you replace that one line. The sweep is **its own `Chart`** (numeric x); it does not use `LabChartView`. Reuse `LabLegendRow`, `LabFooter`, `.dosCard`, and P0's tab-row style for the chips.
- **Math to reuse:** `App/Views/Overview/MealOverlayLogic.swift:31-67` (baseline = last reading in `[t−15 min, t)`, peak in window, `isLowConfidence = readings.count < 4`); `detectMealConfounders` (`:78-103`); `mealImpactDeltaColor` (`:18-22`). If P2's `ResponseKernel` is on `main` when you branch, call it; otherwise call these and note it. `ClinicReportBuilder.percentile(_:_:)` (`Library/Content/ClinicReport.swift:177-188`, type-7) for the per-bin p25/p50/p75. `MealExclusionReason` (`Library/Content/RatioEstimator.swift:80-112`) for the clean/confounded tag vocabulary; `RatioEstimator.pairedBolusUnits(mealTimestamp:deliveries:)` for the bolus pairing.
- **Persisted impacts stop at 30 days** — `MealImpactStore` writes rows only for meals ≤ 30 d old and ≥ 2 h closed (critic-verified); for 90-day sweeps you recompute from raw readings.
- **The one-read precedent:** `App/Modules/DataStore/ClinicReportStore.swift:22-70` — ONE `asyncRead`, `filter(Column(timestamp) >= cutoff)`, "never per-hour/per-day in a loop", NO writes. Fetch the period's readings ONCE (cutoff − 30 min) and slice per meal in Swift.
- **Transient-state template:** `ratioEvidence` (3-file) + `RatioLabMiddleware.swift:30-50` (`.catch` → fallback, `.setFailureType`); register in BOTH `App.swift` arrays. `DaysZoom.allDays = 9999` (`ChartToolbar.swift:142`) — cap the sweep read at 90 days.
- **Design system:** age tiers are alphas on `AmberTheme.amber` / `amberDark` / `textFaint` (the last two are pre-blended tiers); today = `amberLight`; no glow in `Chart{}`; `DOSTypography.caption` for axis labels.

## Global constraints

Kickoff constraints verbatim (StyleGuard; explicit `.chartXScale`/`.chartYScale` — mandatory here, both numeric; UserDefaults-isolated tests; pbxproj IDs + lint + list check; no `dbQueue.write` in `asyncRead`). Plus: every caption carries N (`N=23 SWEEPS · 14 CLEAN`, `(n=4)`); the LAPS card is descriptive only; performance — cap the drawn sweeps at 120 (newest first) and prefer iOS 18 vectorized `LinePlot` over `ForEach` of `LineMark`s if scrolling the chips drops frames (measure; note the choice); no changelog entry; the lab is off by default.

---

### Task 0 — Test scaffold

- [ ] `DOSBTSTests/ChartLabSweepTests.swift`; pbxproj rows after `ChartLabTests.swift`'s (IDs above); `plutil -lint` + `-list | grep` clean; file-private helpers copied from `DirectReducerTests.swift:28-34`.

### Task 1 — `MealSweep` model + statistics (new `Library/Content/MealSweep.swift`, pure)

```swift
struct SweepPoint: Equatable { let minute: Int; let delta: Int }          // minute ∈ −30…240 in 5-min steps (nearest reading), delta = value − baseline
struct MealSweep: Identifiable, Equatable {
    let id: UUID                    // MealEntry.id
    let mealTime: Date; let carbs: Double?; let ageDays: Int
    let baseline: Int?; let points: [SweepPoint]; let isClean: Bool; let exclusion: MealExclusionReason?
    let isInProgress: Bool; let delta: Int?; let peakMinutes: Int?; let n: Int
    var carbBucket: CarbBucket      // ≤15 / 16–45 / 46–80 / >80 / unknown
}
enum CarbBucket: CaseIterable { case upTo15, from16to45, from46to80, over80, unknown }
struct SweepBin: Equatable { let minute: Int; let p25: Int; let p50: Int; let p75: Int; let n: Int }
enum SweepStatistics {
    static func build(meals: [MealEntry], readings: [SensorGlucose], deliveries: [InsulinDelivery], exercise: [ExerciseEntry], now: Date) -> [MealSweep]
    static func bins(_ sweeps: [MealSweep], cleanOnly: Bool) -> [SweepBin]     // per 5-min bin over sweeps that have a point there; n per bin
    static func filter(_ sweeps: [MealSweep], bucket: CarbBucket?, cleanOnly: Bool) -> [MealSweep]
}
```
- [ ] Tests `@Suite("Sweep statistics")` with `SensorGlucose(timestamp:rawGlucoseValue:intGlucoseValue:)` / `MealEntry(timestamp:mealDescription:carbsGrams:)` fixtures: points at 5-min steps with the nearest reading; no baseline → uses first-in-window and marks `isLowConfidence` when < 4; `bins` p50 of three known sweeps; `cleanOnly` excludes confounded; bucket edges (15, 16, 45, 46, 80, 81); in-progress sweep ends at `now`.

### Task 2 — `TwinFinder` (pure)

```swift
enum TwinFinder {
    /// 3–5 clean sweeps in the same carb bucket (±25 % of carbs) and within ±90 min of the same time of day, newest first.
    static func twins(for meal: MealSweep, in sweeps: [MealSweep], max: Int = 5) -> [MealSweep]
    static func summary(of twins: [MealSweep]) -> (medianDelta: Int, medianPeakMinutes: Int, n: Int)?
}
```
- [ ] Tests: ±25 % carbs and ±90 min time-of-day filters; excludes the meal itself and confounded meals; returns at most 5, newest first; `summary` nil under 3 twins.

### Task 3 — Read + transient state + middleware

- [ ] `DirectAction.swift`: `case loadLabSweeps(days: Int)` + `case setLabSweeps(evidence: LabSweepEvidence?)`; transient `var labSweeps: LabSweepEvidence?` (3-file) where `struct LabSweepEvidence: Equatable { let days: Int; let sweeps: [MealSweep]; let loadedAt: Date }`.
- [ ] `App/Modules/DataStore/LabSweepStore.swift`: `DataStore.getLabSweepRaw(days:) -> Future<LabSweepRaw, DirectError>` — ONE `asyncRead`: meals with `timestamp >= cutoff`, readings with `timestamp >= cutoff − 30 min`, deliveries and exercise with the same cutoff; NO writes; days capped at 90.
- [ ] `App/Modules/ChartLab/LabSweepMiddleware.swift`: on `.loadLabSweeps` (guard `.active`) → read → `SweepStatistics.build` on a background queue (`calculationQueue` pattern; ≤ 90 d × ~4 meals is small) → `.setLabSweeps`; `.catch` → `.setLabSweeps(evidence: LabSweepEvidence(days:, sweeps: [], loadedAt:))`; re-trigger on `.setStatisticsDays` while `selectedReportType == .labSweep`, and on `.addMealEntry` / `.deleteMealEntry` while the tab is selected. Register in BOTH `App.swift` arrays.
- [ ] Tests: reducer set/clear; days cap 90 (pure `LabSweepStore.effectiveDays(_:)`).

### Task 4 — `LabSweepView` (new `App/Views/Overview/Lab/LabSweepView.swift`)

- [ ] Layout: caption row (`N=23 SWEEPS · 14 CLEAN` left in `caption`/amber, `Δ mg/dL from −15 min` right in amberLight — unit-aware: `Δ mmol/L` for mmol users with converted deltas) → the `Chart` (height from `GeometryReader`, 220–270) → LAPS card → chips row (`ALL · ≤15 · 16–45 · 46–80 · >80`, local `@State bucket: CarbBucket?`) → a `CLEAN ONLY` toggle chip → `LabLegendRow` + `LabFooter`. `labSweeps == nil` → `FiguresLoadingView.inline`; empty sweeps → `.dosCard(.info)` `NO MEALS IN THE LAST N DAYS · n=0`.
- [ ] Chart: `.chartXScale(domain: -30...240)`, `.chartYScale(domain: yMin...yMax)` where `yMin = −20`, `yMax = max(100, ceil(maxDelta/20)*20)` (display units); x labels `t=0`, `+1h`…`+4h`; dashed `RuleMark(x: 0)` amberLight; **draw order:** p25–p75 `AreaMark` (amber 0.14) from `bins(cleanOnly: true)` → sweeps oldest first (`series: id`, 1.2 pt, dashed `[2,3]` when `!isClean`, alpha tier by `ageDays`: ≤10 amber 0.55, ≤20 amberDark, else textFaint) → median `LineMark` (amber, 2.5 pt) with `MEDIAN · n CLEAN` annotation → today's in-progress sweep (amberLight 3 pt, end `PointMark` + `TODAY +Δ` annotation). Cap at 120 drawn sweeps; if `ForEach` marks jank on the 90 d chip, switch the sweeps to `LinePlot(data, x:, y:, series:)` (iOS 18) and note it.
- [ ] LAPS card (`.dosCard(.stat)`): for the newest meal (in progress or last completed): `LAPS · 80g DINNER` … `WHY THESE ›`; second line `TODAY +47 (38 MIN) · TWINS MEDIAN +41 · PEAK 55 MIN (n=4)`; tap `WHY THESE ›` expands (in place, `withAnimation(AnimationTokens.snappy)`) a list of the twins — date, carbs, delta, clean tag — no new sheet. Under 3 twins → `TWINS n<3 · KEEP LOGGING`.
- [ ] `ChartView.swift`: `case .labSweep: LabSweepView()` — the only line you touch there.
- [ ] Tests: y-domain helper; bucket chip filtering via `SweepStatistics.filter`; LAPS line formatter (pure) renders the artboard string from a fixture.

### Task 5 — Suites, build

- [ ] Green: `ChartLabSweepTests`, `ChartLabTests`, `MealImpactTests`, `StyleGuardTests`; full suite (log to file, grep the result line). Both targets build (`Library/Content/MealSweep.swift` has no SwiftUI import).

## Verification (simulator, virtual sensor; seed ≥ 8 meals across 3 days with boluses, one with a correction bolus 30 min after, one 10 g with no bolus)

1. Lab on → `LAB: SWEEP` loads, caption shows the right `N=… SWEEPS · … CLEAN`; the axis reads `t=0 … +4h`; sweeps align at 0 with the baseline at Δ0.
2. The corrected meal is dashed; older meals fade; the median and wash exist once ≥ 3 clean sweeps.
3. Chips filter by bucket; `CLEAN ONLY` hides dashed sweeps and recomputes the wash; caption N updates.
4. Log a meal now → after a few readings it appears as the amberLight in-progress trace with `TODAY +Δ`; the LAPS card names it and its twins; `WHY THESE ›` expands the list.
5. 7d/30d/90d chips reload; `ALL` behaves as 90 d.
6. mmol/L users see `Δ mmol/L` and converted values.
7. GLUCOSE tab unchanged; lab off → nothing renders.

## Out of scope

Exercise sweeps (kernel-ready later); tapping a sweep to jump to its day; the shot-chart grid and the outcome ledger (sub-modes deferred); changelog; the marker lane.

## Sibling / merge notes

Parallel with P1/P2/P4/P5 off the merged P0. You touch `ChartView.swift` (one line), state files (transient), both `App.swift` arrays, new files only. P2 rewrites `MealOverlayLogic.swift` internals (you only call it). Never rebase onto or merge sibling work. Fold `IMPLEMENTATION_NOTES.md` into the PR body and `git rm` it.
