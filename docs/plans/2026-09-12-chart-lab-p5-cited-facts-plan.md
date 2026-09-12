# Chart Lab P5 — Cited facts: offline highlights, Black Box hypo card, feature sheet — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven-development). Checkbox steps. Read the file at each anchor before editing; shipping-code anchors were verified on `main` @ `3a288d3d`; lab-platform anchors (`App/Views/Overview/Lab/*`) refer to the merged P0 PR — open those files first. Record every deviation in `IMPLEMENTATION_NOTES.md`.

**Issue:** DMNC-1505 (P5) · **Branch:** `feat/chart-lab-p5-facts` · **Worktree:** `../DOSBTS-wt-lab-p5` · **Base:** `main` after P0 (DMNC-1504) merged · **Tier:** Opus · **Simulator:** `-destination 'id=ACB4E809-739A-47D4-AF24-EF51BAB88214'` (iPhone 17, iOS 26.4; always by `id=`) · **pbxproj object IDs:** file ref `C1AB15050000000100A00001`, build file `C1AB15050000000100A00002`.

**Visual spec:** artboard **7 (Facts)** — https://claude.ai/code/artifact/0f40d578-b3a3-460c-a651-aff0f3240dfb (`…/screens/Facts.dc.html`). Copy: numbered amber pins ①②③ on the curve with a red dashed onset rule at the hypo; feature-sheet line `24H · N=288 · MEDIAN 138 · P95 214 · 1 HYPO · 4 MEALS · 3 CLEAN`; card 1 (red border) `BLACK BOX · HYPO 02:30 · 50 MIN` / `T-0 62 · IOB 1.8U · COB 0g` / `LAST BOLUS T-4h10 7U · EXERCISE T-9h 30m RUN` / `HR 71→96 · TAG —`; card 2 `LUNCH 60g → +54 · PEAK 50 MIN` / `1 OF 6 SIMILAR MEALS · CLEAN · n=24 RDG`; legend `● CITED FACT · ■ HYPO ONSET`. **No NARRATE button in this build.**

**Intent (Dom, verbatim):** "maybe place helpful AI interactions more within the app, make it more integrated" — this PR ships the deterministic half: the facts the app can state itself, offline, so the later AI leg can only ever narrate what is already cited.

**Goal:** A pure highlights engine turns the visible window into a ranked list of id-carrying facts (each with its N), rendered as numbered pins on the lab chart, a feature-sheet line, and staged-reveal cards — the Black Box card at every hypo onset first. The same sheet becomes the chart's accessibility description.

## Architecture (verified findings)

- **Platform seam (P0):** `.factPins` is declared in `ChartLabOverlay` and included in `.labMeals`'s overlay set; `LabOverlayMarks.marks(for: .factPins, series:, yMax:)` is your arm. `LabChartSeries` exposes `glucoseSegments`, `glucoseByMinute`, `nearestGlucose(at:)`, `iob: [IOBSample]`, `insulin`, `meals`, `exercise`, `heartRate`, `domainStart/End`. `LabMealsView` composes `LabChartView` + legend + footer — add the sheet line and the card list under the chart there.
- **Detectors that exist:** `Library/Content/ClinicReport.swift:145-171` — `static func hypoEpisodes(from readings: [SensorGlucose]) -> Int`: filters `< hypoThresholdMgDL`, splits runs by `hypoSeparationMinutes`, counts runs `≥ hypoMinDurationMinutes`; **it tracks `episodeStart` / `previousLow` and discards the boundaries** (`closeEpisode(end:)` only increments). `ClinicReportData.hypoEpisodeCount` (`:69`) and `ClinicReportTests` pin the count. `ClinicReportBuilder.percentile(_:_:)` (`:177-188`, type-7). `MealOverlayLogic.swift:18-22` tiers, `:31-67` delta, `:78-103` confounders. `App/Modules/TightControlStreak/TightControlStreakDetector.swift` — pure detector precedent (band 80–120, 2 h continuous). IOB at any instant: `computeIOB(deliveries:bolusModel:basalModel:at:)` (`Library/Content/IOBCalculator.swift:121`) — P0's `LabChartSeries.iob` already samples it per minute; read the nearest sample.
- **Safety discipline:** `RatioLabView.swift:23-26` — every number ships with N/spread, two fixed disclaimers, no imperative dosing language. `ClaudeService.swift:322-326` rules ("Never invent data not present in the input", "Never give medical advice") apply to card copy even though no AI runs here.
- **Staged reveal:** `stagedReveal` cascade in `App/DesignSystem/Modifiers/DOSModifiers.swift` (used by `DigestView` and `WhatsNewView`) — reuse it for the card list; respect Reduce Motion via `AnimationTokens.adapted(animation:)`.
- **Accessibility:** no `AXChartDescriptor` / `accessibilityChartDescriptor` exists in the repo yet (grep verified) — you introduce the first one; Swift Charts exposes `.accessibilityChartDescriptor(_:)` taking an `AXChartDescriptorRepresentable`.

## Errata from P0 (read before touching the lab chart — PR #117 proved these)

- **`EmptyChartContent` does not exist.** An empty `LabOverlayMarks` arm is `LabOverlayMarks.noMarks` (an empty `ForEach([Int](), id: \.self) { … }`); `Optional: ChartContent` makes a bare `if let` arm legal.
- **Never hit-test the whole plot from `.chartOverlay`.** A `Rectangle().contentShape(...)` there swallows every touch and kills both scrolling and the built-in selection. Use `.simultaneousGesture(...)` on the chart (P0's tap-to-clear measures press duration < 0.35 s and movement < 10 pt) or put tappable things in `.annotation` views / `.overlay(alignment:)` siblings that only claim their own frame.
- **Gesture vocabulary already taken by P0:** plain drag = scroll; press ~0.5 s then drag = scrub; a second press > 5 min away promotes the standing cursor to A and sets B; quick tap clears. A long-press for a drill (P4) **must not** compete with the scrub — use a chip/toggle or a two-finger gesture and say which in the notes.
- **`chartScrollPosition(x:)` binds the LEADING edge**; "scroll to now" is `max(domainStart, domainEnd − visibleDuration)`; a zoom-chip change needs P0's `reanchorAfterZoom()`.
- **The y domain is a floor, not a fixed ceiling:** `max(chartMinimum, plotted.max().rounded(.up))` — readings above 300 are not clipped. Any overlay that adds y values must feed the same floor computation (extend it; do not add a second `.chartYScale`).
- **Annotations at the plot top use `overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))`** — `y: .disabled` draws above the plot and is clipped.
- **Units:** datapoint values are already in the display unit — format with `GlucoseFormatters.mgdLFormatter / .mmolLFormatter`, never `Int.asGlucose` on a converted value; insulin uses the `GlucoseView.formatIOB` shape (`"%.1fU"`), not `Double.asInsulin()` (2-decimal, locale comma).
- **Counts come from `LabChartSeries.glucose`** (flat, deduplicated) — `glucoseSegments` duplicate boundary points and would inflate `n`.
- **`LabChartInputs.smoothThreshold` is floored to the minute** so `Equatable` inputs do not churn every render; any field you add must be render-stable the same way (no raw `Date()`).
- `chartHeight(available:)` does not subtract the readout strip (it is a sibling of the `GeometryReader`); edge hour labels can clip when the snapped edge lands on a tick — known nit, do not "fix" it inside your arm.

## Global constraints

Kickoff constraints verbatim (StyleGuard; no glow in `Chart{}`; explicit domains; UserDefaults-isolated tests; pbxproj IDs + lint + list check). Plus:
- **`LabFigure` cannot be constructed without its `n`** (the only initializer requires it); every card line and the sheet line render through `LabCaption`, never a bare interpolated number.
- Cards are descriptive: numbers, times, counts. Banned in any string you add: `take`, `inject`, `dose`, `units to`, `you should`, `bolus now`, `correct with`. Add a source-scan test (`ChartLabFactsTests.rule_noDosingLanguageInFactCopy`) that reads `App/Views/Overview/Lab/*Facts*.swift` and fails on those tokens (case-insensitive, whole-line comments skipped) — same shape as `StyleGuardTests`.
- `hypoEpisodes(from:) -> Int` keeps its behaviour (pinned) — it becomes `hypoEpisodeIntervals(from:).count`.
- Offline only. No network, no consent gate, no changelog entry (gated lab surface).

---

### Task 0 — Test scaffold

- [ ] `DOSBTSTests/ChartLabFactsTests.swift` with pbxproj rows after the `ChartLabTests.swift` rows (IDs above); `plutil -lint` + `-list | grep` clean; file-private `makeState()`/`reduce()` copied from `DirectReducerTests.swift:28-34`.

### Task 1 — `hypoEpisodeIntervals` (behaviour-preserving refactor)

- [ ] `ClinicReport.swift`: add `static func hypoEpisodeIntervals(from readings: [SensorGlucose]) -> [DateInterval]` with the same walk (threshold, separation, min duration) returning `[DateInterval(start: episodeStart, end: previousLow)]` for qualifying runs; `hypoEpisodes(from:)` becomes `hypoEpisodeIntervals(from:).count`.
- [ ] Tests: existing `ClinicReportTests` untouched and green; new `@Suite("Hypo episode intervals")` — one 50-min run → one interval with the right bounds; two runs 40 min apart → two; a 10-min dip → none; count equals the legacy function on a shared fixture.

### Task 2 — `LabFigure` + `LabCaption` (new `Library/Content/LabFigure.swift`, `App/Views/Overview/Lab/LabCaption.swift`)

```swift
/// A number the lab may show. It cannot exist without its sample size.
struct LabFigure: Equatable, Codable {
    enum Kind: String, Codable { case delta, peakMinutes, glucose, iob, cob, count, median, percentile, duration }
    let kind: Kind; let value: Double; let unit: String; let n: Int
    let spread: ClosedRange<Double>?; let window: DateInterval?
    init(kind: Kind, value: Double, unit: String, n: Int, spread: ClosedRange<Double>? = nil, window: DateInterval? = nil)
}
struct LabCaption: View { let figure: LabFigure; … }   // "Δ +42 mg/dL · n=7" · "PEAK 50 MIN" · unit conversion via glucoseUnit for .glucose/.delta/.median/.percentile
```
- [ ] Tests: `LabFigure` has no `n`-less initializer (compile-time; document in a comment); `LabCaption.text(for:unit:)` (a pure formatter the view uses) renders `+42 mg/dL · n=7`, `4.2 mmol/L · n=7`, `PEAK 50 MIN`, `n=0` figures render `—`.

### Task 3 — `ChartHighlights` engine (new `Library/Content/ChartHighlights.swift`, pure)

```swift
struct ChartFact: Identifiable, Equatable {
    enum Kind: Equatable { case hypoOnset, mealResponse, stackedBolus, exerciseDrop, tightControlRun, bandExit /* P4 feeds this */ , regimeOverlap /* P2 feeds this */ }
    let id: String            // stable: "hypo-<start ISO>", "meal-<uuid>", …
    let kind: Kind
    let anchor: Date; let end: Date?
    let title: String         // "BLACK BOX · HYPO 02:30 · 50 MIN"
    let lines: [[LabFigure]]  // rendered by LabCaption, joined with " · "
    let severity: Int         // 3 hypo, 2 stacked bolus / large delta, 1 informational
}
struct ChartFeatureSheet: Equatable { let window: DateInterval; let readings: Int; let median: LabFigure; let p95: LabFigure; let hypoEpisodes: Int; let meals: Int; let cleanMeals: Int; let notes: Int }
enum ChartHighlights {
    static func facts(readings:deliveries:meals:exercise:notes:iob:heartRate:mealResponses:now:) -> [ChartFact]   // ranked by severity then recency, capped at 5
    static func sheet(readings:meals:mealResponses:notes:window:) -> ChartFeatureSheet
}
```
Detectors: hypo onset (from Task 1; Black Box lines: `T-0 <glucose>` · `IOB <at onset>` · `COB 0g` placeholder until W2 (label `COB —`) · `LAST BOLUS T-<h>h<m> <U>U` · `EXERCISE T-<h>h <min>m <type>` or `—` · `HR <first>→<last>` from the hour around onset or `—` · `TAG <tag>` or `—`); meal response `≥ 60` delta (from P2's `mealResponses` when present — if P2 has not merged when you branch, compute via `computeMealOverlayDelta` and note it; the train reconciles); two boluses within DIA (`stackedBolus`, both units + minutes apart); exercise-adjacent drop (≥ 30 mg/dL fall within 60 min after an exercise start); tight-control run (≥ 2 h inside 80–120; reuse the detector's band constants).
- [ ] Tests `@Suite("Chart highlights")`: hypo fixture → a `hypoOnset` fact ranked first with `T-0` equal to the onset reading and `n` = readings in the episode; a 60 g +54 meal → `mealResponse` with `n` and `PEAK`; two boluses 90 min apart → `stackedBolus`; ranking cap 5; ids stable across two calls; sheet counts match the fixture.

### Task 4 — Pins, sheet line, cards, accessibility

- [ ] `.factPins` arm: per fact — `RuleMark(x: anchor, yStart: nearestGlucose.value + 10, yEnd: yMax)` in `amber` 1 pt, a `PointMark` at `yMax` with `symbolSize` 200 filled `amber` and the index as a black `.annotation` glyph (`DOSTypography.microLabel`, `inkOnAmber`); hypo facts add a red dashed `RuleMark(x: onset)` full height. Pins never overlap: shift the label horizontally by index when two anchors fall within 20 min.
- [ ] `LabMealsView`: under the chart, the sheet line (`DOSTypography.micro`, `amberDark`, single line, `lineLimit(1)` + `minimumScaleFactor(0.85)`), then the card list — `ForEach(facts)` of `.dosCard(.toast, stroke: fact.kind == .hypoOnset ? AmberTheme.cgaRed : AmberTheme.amber)` with an index chip (16×16, `amber`/`cgaRed` fill, `inkOnAmber` digit) + title in `DOSTypography.label` and lines via `LabCaption`; `stagedReveal` cascade; tapping a card scrolls the chart to its anchor (`scrollPosition = anchor − visibleDomain/2` — P0's binding) and sets the sticky cursor there.
- [ ] Accessibility: `LabChartView` gets an optional `chartDescriptor: AXChartDescriptorRepresentable?`; `LabMealsView` supplies one built from the sheet + facts (summary string = the sheet line; series = glucose values per minute; annotations = facts). VoiceOver reads `"Lab chart. 24 hours, 288 readings, median 138, …"`.
- [ ] Legend items `● CITED FACT · ■ HYPO ONSET` appended to `LabMealsView`'s legend.

### Task 5 — Suites, build

- [ ] Green: `ChartLabFactsTests`, `ClinicReportTests`, `ChartLabTests`, `StyleGuardTests`, `TightControlStreakDetectorTests`; then the full suite (log to file, grep the result line). Both targets build.

## Verification (simulator, virtual sensor; force a hypo: set the virtual sensor to 62 for 50 min around 02:30 with a 7 U bolus at 22:20 and a run at 17:30 the day before)

1. `LAB: MEALS` shows the sheet line with the right N and counts; pins numbered in severity order; the hypo has a red dashed onset rule.
2. Card 1 is the Black Box for the hypo with `T-0 62`, an IOB matching the hero's IOB history at that time, `LAST BOLUS T-4h10 7U`, `EXERCISE T-9h 30m RUN`, `HR …` or `—`, `TAG —`; card lines end with `· n=…` wherever a derived figure appears.
3. Log a 60 g meal that peaks +54 → a meal card with `PEAK` and `n=… RDG`.
4. Tap a card → the chart scrolls to the anchor and the cursor lands on it; the readout strip shows the same numbers as the card.
5. VoiceOver on: the chart announces the sheet summary; swiping through announces facts.
6. Reduce Motion on: cards appear without the cascade.
7. GLUCOSE tab unchanged; lab off → nothing renders. No network calls (Charles/Console: none).

## Out of scope

NARRATE / any Claude call (wave 5); band-exit and regime-overlap facts beyond the enum cases (P4/P2 feed them later); COB values (placeholder `COB —` until W2); changelog; the marker lane.

## Sibling / merge notes

Parallel with P1–P4 off the merged P0. You touch `LabOverlayMarks.swift` (one arm), `LabMealsView.swift` (sheet + cards + legend), `ClinicReport.swift` (additive), new files. P2 rewrites `MealOverlayLogic.swift` internals (you only call it) — the train merges you first. Never rebase onto or merge sibling work. Fold `IMPLEMENTATION_NOTES.md` into the PR body and `git rm` it.
