# Chart Lab P4 — `LAB: PATTERNS`: your own band under today — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven-development). Checkbox steps. Read the file at each anchor before editing; shipping-code anchors were verified on `main` @ `3a288d3d`; lab-platform anchors refer to the merged P0 PR — open `App/Views/Overview/Lab/*` first. Record every deviation in `IMPLEMENTATION_NOTES.md`.

**Issue:** DMNC-1503 (P4 half) · **Branch:** `feat/chart-lab-p4-patterns` · **Worktree:** `../DOSBTS-wt-lab-p4` · **Base:** `main` after P0 (DMNC-1504) merged · **Tier:** Opus for Tasks 1–3 (seam), Sonnet-able for Task 4 · **Simulator:** `-destination 'id=F4D018BE-52B6-409E-AF86-C07A1710831F'` (iPhone 17 Pro Max, iOS 26.4; always by `id=`) · **pbxproj object IDs:** file ref `C1AB15030000000200A00001`, build file `C1AB15030000000200A00002` (P3 holds `…0100…`).

**Visual spec:** artboard **5 (GhostBand)** — https://claude.ai/code/artifact/0f40d578-b3a3-460c-a651-aff0f3240dfb (`…/screens/GhostBand.dc.html`). Copy: the unit row chip `▒ YOUR 30-DAY BAND`; the p5–p95 wash (amber 0.07) under the p25–p75 wash (0.16) with a faint median line, spanning the whole 24 h; the dashed `PATTERN HOUR · n=27` box; the out-of-band tick on the x-axis with a `.dosCard(.toast)` card `11:45 · +38 VS USUAL · n=27`; the drill card `HOLD AN HOUR → SAME HOUR · 14 D` / `9 OF 14 DAYS > 180 HERE · n=612`; chips `7d · 30d · 90d · ALL`; legend `▒ P25–P75 · ░ P5–P95 · ▎ OUT OF BAND`.

**Intent (Dom, verbatim):** "there's no pattern view (one day at a time only, so a recurring dawn rise never surfaces)" — answered on the surface he already looks at: is today unusual for me, and where.

**Goal:** `LAB: PATTERNS` shows today's day chart with the user's own 30-day (7/90) hourly percentile band ghosted behind it; hours where today leaves the band get an axis tick and a card with N; the widest hour is tagged `PATTERN HOUR`; a long-press on an hour drills into the same ±2 h across the last 14 days with a `k OF N DAYS > 180 HERE · n=` line.

## Architecture (verified findings)

- **Platform seam (P0):** `ReportType.labPatterns` exists with `usesDayWindow == true` (day chips drive `statisticsDays`); `ChartView.swift` routes `.labPatterns` to `LabPlaceholderView(tab: .labPatterns)` — you replace that line. `.ghostBand` is declared in `ChartLabOverlay` and is the only overlay in `.labPatterns.labOverlays`; `LabOverlayMarks.marks(for: .ghostBand, series:, yMax:)` is your arm. `LabChartView(overlays:)` draws today's day window (P0's `LabChartInputs(state:overlays:)`); you feed it the band through a new field on `LabChartInputs` (Task 3).
- **The percentile seam:** `Library/Content/ClinicReport.swift:38-46` `HourlyPattern { hour, median, p25, p75, readings }` (Equatable); `:117-138` `hourlyPatterns(from:calendar:)` — ALWAYS 24 entries, `nil` quantiles for empty hours, `readings` = that hour's sample count; `:177-188` `percentile(_:_:)` type-7. `ClinicReportData.hourlyPatterns` (`:65`) and `ClinicReportPage` (PDF) consume it; `ClinicReportTests` pins the median/p25/p75 values — keep them.
- **The multi-day read:** `App/Modules/DataStore/ClinicReportStore.swift:22-70` `getClinicReportData(days:) -> Future<ClinicReportRaw, DirectError>` — ONE `asyncRead`, readings `>= cutoff`, deliveries, meal count, `period`; NO writes. Reuse it as-is; `ClinicReportRaw.readings` is exactly what the band and the drill need.
- **Transient-state template:** `ratioEvidence` (3-file) + `RatioLabMiddleware.swift:30-50` (`.catch` → fallback, `.setFailureType`); register in BOTH `App.swift` arrays; `DaysZoom.allDays = 9999` (`ChartToolbar.swift:142`) → cap at 90.
- **Day/night threshold caveat** (learning `widgetkit-timeline-time-of-day-boundary-entries-20260503.md` + dossier): the band is glucose-only; the "> 180" drill line uses the **consensus 180**, not the active alarm profile, and says so in its label (`> 180`), matching the clinic report's discipline.
- **Design system:** `AmberTheme.amber` alphas for the washes (in-chart precedent), `borderSubtle` for the dashed box, `.dosCard(.toast)` for the card, `DOSTypography.micro`/`microLabel`.

## Global constraints

Kickoff constraints verbatim (StyleGuard; explicit domains — the band lives in glucose units on P0's y-scale; UserDefaults-isolated tests; pbxproj IDs + lint + list check; no `dbQueue.write` in `asyncRead`). Plus: every card/line carries N (`n=27` = days with data for that hour; `n=612` = readings in the drill); no changelog entry; the lab is off by default.

---

### Task 0 — Test scaffold

- [ ] `DOSBTSTests/ChartLabPatternsTests.swift`; pbxproj rows after `ChartLabTests.swift`'s (IDs above); `plutil -lint` + `-list | grep` clean; file-private helpers from `DirectReducerTests.swift:28-34`.

### Task 1 — p5/p95 on `HourlyPattern` (additive)

- [ ] `ClinicReport.swift`: add `let p5: Int?` and `let p95: Int?` and `let days: Int` (distinct calendar days contributing to the hour) to `HourlyPattern` with a **compatibility initializer** `init(hour:median:p25:p75:readings:)` defaulting the new fields (`p5: nil, p95: nil, days: 0`) so `ClinicReportTests` and `ClinicReportPage` compile unchanged; compute all three in `hourlyPatterns(from:calendar:)` (`percentile(values, 0.05)` / `0.95`; `days` via a `Set` of `calendar.startOfDay(for:)`).
- [ ] Tests: `ClinicReportTests` green untouched; new `@Suite("Hourly p5/p95")` — a 40-value hour: p5/p95 match hand-computed type-7 values; single value → p5 == p95 == value; empty hour → nils and `days == 0`; `days` counts distinct days.

### Task 2 — Read + transient state + middleware

- [ ] `DirectAction.swift`: `case loadLabPatterns(days: Int)` + `case setLabPatterns(evidence: LabPatternEvidence?)`; transient `var labPatterns: LabPatternEvidence?` (3-file) where `struct LabPatternEvidence: Equatable { let days: Int; let hourly: [HourlyPattern]; let readings: [SensorGlucose]; let period: DateInterval }` (`Library/Content/LabPatternEvidence.swift`).
- [ ] `App/Modules/ChartLab/LabPatternsMiddleware.swift`: on `.loadLabPatterns` (guard `.active`, days capped at 90) → `DataStore.shared.getClinicReportData(days:)` → build `hourly` via `ClinicReportBuilder.hourlyPatterns(from:)` on the `calculationQueue` pattern → `.setLabPatterns`; `.catch` → `.setLabPatterns(evidence: LabPatternEvidence(days:, hourly: ClinicReportBuilder.hourlyPatterns(from: []), readings: [], period:))`; re-trigger on `.setStatisticsDays` while `selectedReportType == .labPatterns`. Register in BOTH `App.swift` arrays.
- [ ] Tests: reducer set/clear; days cap.

### Task 3 — Pure pattern analysis (new `Library/Content/PatternAnalysis.swift`)

```swift
struct OutOfBandHour: Equatable { let hour: Int; let todayMedian: Int; let usualMedian: Int; let deltaVsUsual: Int; let days: Int }
struct PatternHour: Equatable { let hour: Int; let spread: Int; let days: Int }          // widest p25–p75
struct SameHourDrill: Equatable { let hour: Int; let traces: [[SensorGlucose]]; let daysAbove180: Int; let days: Int; let n: Int }
enum PatternAnalysis {
    static func outOfBand(today: [SensorGlucose], hourly: [HourlyPattern], calendar: Calendar = .current) -> [OutOfBandHour]   // today's hourly median above p75 or below p25; days ≥ 5
    static func patternHour(_ hourly: [HourlyPattern]) -> PatternHour?
    static func drill(hour: Int, readings: [SensorGlucose], days: Int, calendar: Calendar = .current) -> SameHourDrill   // ±2 h around hour:30 per day, last `days` days
}
```
- [ ] Tests `@Suite("Pattern analysis")`: today above p75 at 11:00 → one `OutOfBandHour` with `deltaVsUsual == todayMedian − usualMedian`; hours with `days < 5` never flagged; `patternHour` picks the max spread; `drill` slices ±2 h per day, counts days whose max > 180, `n` = readings.

### Task 4 — `LabPatternsView` + the `.ghostBand` arm + drill

- [ ] `LabChartInputs`: add `let patternBand: [HourlyPattern]?` (from `state.labPatterns?.hourly`, nil while loading) and carry it into `LabChartSeries.patternBand`; P0's `init(state:overlays:)` picks it up.
- [ ] `.ghostBand` arm: points at `hour:30` for hours with data, plus `00:00` and `24:00` edge points from hours 0 and 23; `AreaMark(x:, yStart: p5, yEnd: p95)` amber 0.07 and `AreaMark(yStart: p25, yEnd: p75)` amber 0.16 with `.interpolationMethod(.monotone)`, median `LineMark` amber 0.5 1 pt; the `PATTERN HOUR` dashed `RectangleMark` (`borderSubtle`, `[3,3]`) with a micro label `PATTERN HOUR · n=<days>`; for each `OutOfBandHour`: a 3 pt amber `RuleMark` tick on the x-axis (`yStart: 0, yEnd: 4` in display units → use a fixed-height `RectangleMark` at the axis) and a `.dosCard(.toast)` annotation `HH:00 · +38 VS USUAL · n=27` anchored to today's reading at that hour (`overflowResolution: .init(x: .fit(to: .chart), y: .disabled)`); values converted for mmol/L.
- [ ] `LabPatternsView` (`App/Views/Overview/Lab/LabPatternsView.swift`): `.onAppear` / `.onChange(of: statisticsDays)` dispatch `.loadLabPatterns(days:)`; unit row extra chip `▒ YOUR <N>-DAY BAND`; `LabChartView(overlays: [.ghostBand])`; drill card under the chart: default text `HOLD AN HOUR → SAME HOUR · 14 D`; on a long-press over the plot (a `.chartOverlay` `LongPressGesture` that resolves the hour via `proxy.value(atX:)` — coordinate with P0's gesture arbitration: the lab chart's long-press is the scrub; use a **two-finger long-press** or a `DRILL` chip toggle if they conflict, and note the choice) → replace the card content with a mini `Chart` (height 120) of the 14 day-traces ±2 h (amberDark 1 pt) with today's in amber 2 pt and the line `9 OF 14 DAYS > 180 HERE · n=612`; a `×` returns. `labPatterns == nil` → `FiguresLoadingView.inline` in place of the card; the day chart still renders.
- [ ] Legend `▒ P25–P75 · ░ P5–P95 · ▎ OUT OF BAND` + `LabFooter`; `ChartView.swift`: `case .labPatterns: LabPatternsView()` — the only line you touch there.
- [ ] Tests: band point builder (edge points at 0 and 24 h; hours with `nil` quantiles skipped); the card string formatter; the drill line formatter.

### Task 5 — Suites, build

- [ ] Green: `ChartLabPatternsTests`, `ClinicReportTests`, `ClinicReportRenderSeamTests` (the PDF still renders), `ChartLabTests`, `StyleGuardTests`; full suite (log to file, grep the result line). Both targets build.

## Verification (simulator, virtual sensor running long enough for ≥ 5 days of history — or seed via the debug menu if one exists; otherwise verify the empty state)

1. Lab on → `LAB: PATTERNS` shows today's chart with the band behind it once the read lands; the unit row shows `▒ YOUR 30-DAY BAND`; day chips 7d/30d/90d/ALL reload the band and the chip label.
2. With < 5 days of data: no out-of-band flags, no `PATTERN HOUR`; the drill card says `HOLD AN HOUR → SAME HOUR · 14 D` and, when held, `n<5 DAYS · KEEP WEARING`.
3. With ≥ 5 days: the dashed `PATTERN HOUR · n=…` box sits on the widest hour; an hour where today sits above p75 shows the axis tick and the `HH:00 · +Δ VS USUAL · n=…` card.
4. Hold an hour → the drill shows 14 faint traces ±2 h with today's bright and `k OF N DAYS > 180 HERE · n=…`; `×` returns.
5. Settings → Glucose & Display → Clinic Report still generates a PDF (the hourly pattern table is unchanged).
6. mmol/L: band, cards and drill line convert.
7. GLUCOSE tab unchanged; lab off → nothing renders.

## Out of scope

The heatmap and day-overlay spaghetti (deferred); condition-split AGP (lands once P2's regimes give days membership — leave a `// P-later: split by DayCohort` seam comment in `PatternAnalysis`); the wake-anchored day; changelog; the marker lane.

## Sibling / merge notes

Parallel with P1/P2/P3/P5 off the merged P0. You touch `LabOverlayMarks.swift` (one arm), `LabChartSeries.swift` (one field), `ChartView.swift` (one line), `ClinicReport.swift` (additive), state files (transient), both `App.swift` arrays, new files. Never rebase onto or merge sibling work. Fold `IMPLEMENTATION_NOTES.md` into the PR body and `git rm` it.
