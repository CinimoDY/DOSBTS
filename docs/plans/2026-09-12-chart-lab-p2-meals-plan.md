# Chart Lab P2 — `LAB: MEALS`: response kernel, graded live ribbon, residual, regimes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven-development). Checkbox steps. Read the file at each anchor before editing; anchors for shipping code were verified on `main` @ `3a288d3d`; anchors into the lab platform (`App/Views/Overview/Lab/*`) refer to the merged P0 PR — open those files first and re-verify every signature. Record every deviation in `IMPLEMENTATION_NOTES.md`.

**Issue:** DMNC-1501 (P2) · **Branch:** `feat/chart-lab-p2-meals` · **Worktree:** `../DOSBTS-wt-lab-p2` · **Base:** `main` after P0 (DMNC-1504) merged · **Tier:** Opus · **Simulator:** `-destination 'id=653F1D37-862C-4829-A384-C4403636B338'` (iPhone 17, iOS 26.5; always by `id=`) · **pbxproj object IDs:** file ref `C1AB15010000000200A00001`, build file `C1AB15010000000200A00002` (siblings hold `C1AB1503…`, `C1AB1504…`, `C1AB1505…`).

**Visual spec:** artboards **3 (Ribbon)** and **6 (Regimes)** — https://claude.ai/code/artifact/0f40d578-b3a3-460c-a651-aff0f3240dfb (sources `.context/compound-engineering/ce-prototype/2026-09-12-chart-lab-directions/01-chart-lab-directions/screens/Ribbon.dc.html`, `Regimes.dc.html`; `open <path>`). Copy: carb-sized green dots on the curve; ribbons `+28 · PEAK 52m · 24 RDG` (green), `+54 · PEAK 50m · 24 RDG` (amber), hatched `NO BOLUS`, live `+47 · 38 MIN · 7 RDG` with a dotted stub to +2 h; brackets `60g ⟷ 5U`; residual `?` + `UNEXPLAINED +45 · 15 RDG · TAP TO NOTE`; hatched `STRESSED 15→19` band; `STILL STRESSED? Y / N` row; legend `● SIZE = CARBS · ▮ 2H RESPONSE · ▨ EXCLUDED · TAG = WHY` and `▨ REGIME (TAG WITH DURATION) · ? NO LOGGED CAUSE`.

**Intent (Dom, verbatim):** "i want to explore some ideas and options around better visualizing the data … things like making the amount of carbs distinguishable by size" · "make tangible to users the connection everything has to show … stress level, other factors in life".

**Goal:** On `LAB: MEALS` the day chart shows every meal as a carb-sized dot on the curve, each followed by a two-hour response ribbon that grows live, hardens at window close, is tinted by the delta tier, and names its confounder or Ratio Lab exclusion instead of blaming the plate; an unexplained excursion becomes a `?` that opens the journal-note sheet pre-filled at its start; a tagged note opens a regime band with a duration, closable by `STILL <TAG>? Y/N`. All of it is computed by one anchor-agnostic `ResponseWindow` kernel that later serves exercise and sleep.

## Architecture (verified findings)

- **Platform seam (P0):** `LabChartView(overlays:)` renders `LabOverlayMarks.marks(for:series:yMax:)` for each overlay in `ReportType.labOverlays`; `.labMeals` already declares `[.carbSizedMeals, .mealResponseRibbons, .residualMarks, .regimeBands, .factPins]` (`App/Views/Overview/Lab/ChartLabOverlay.swift`). `LabChartSeries` carries `meals: [MealDatapoint]`, `glucoseByMinute`, `nearestGlucose(at:)`, `insulin`, `exercise`; `LabChartInputs` snapshots `store.state` (`App/Views/Overview/Lab/LabChartSeries.swift`). Fill your four arms; do not touch `.nightContext`, `.ghostBand`, `.factPins`.
- **The math you generalise, not copy:** `App/Views/Overview/MealOverlayLogic.swift:31-67` — `computeMealOverlayDelta(meal:isInProgress:sensorGlucoseValues:)`: `windowEnd = isInProgress ? Date() : meal.timestamp + 2 h` (`:36`), baseline = last reading in `[t−15 min, t)` (`:46-49`), peak = max in window (`:60`), `isLowConfidence = readings.count < 4` (`:64`); `detectMealConfounders(meal:insulinDeliveryValues:exerciseEntryValues:mealEntryValues:)` (`:78-103`) — correction bolus in `[t, t+2h]`, exercise overlapping, stacked meal. Both are store-free free functions (`:5-6`). `mealImpactDeltaColor(delta:)` (`:18-22`; green < 30, amber 30–59, red ≥ 60) is pinned by `MealImpactTests.swift:286-312` — keep it as the single tier source.
- **In-progress predicate** the tap sheet uses: `Date().timeIntervalSince(meal.timestamp) < 2 * 60 * 60` (`App/Views/RootSheetContent.swift:217`).
- **Ratio Lab pairing + exclusions to reuse:** `Library/Content/RatioEstimator.swift:52` "Sum of meal/snack boluses within ±15 min of `meal.timestamp` (correction boluses excluded)" — the pure helper `pairedBolusUnits(mealTimestamp:deliveries:)`; `MealExclusionReason` (`:80-112`: `.confounded, .noBolus, .noBaseline, .baselineOutOfRange, .smallMeal, .tinyBolus, .didNotReturnToBaseline(deltaMgDL:), .hypoInWindow, .implausibleRatio, .insufficientData`) — "the exclusion reason *is* the lesson"; `RatioLabView` renders them as tags (`NO BOLUS`, `ENDED +54`, `HYPO`, `LOW START`, `SMALL MEAL`) — reuse its tag-string mapping (grep `MealExclusionReason` in `App/Views/Settings/RatioLabView.swift`) rather than inventing new strings.
- **Journal notes:** `Library/Content/JournalNote.swift` — `timestamp` rounded to the minute, `tag: JournalNoteTag?` (`.sick, .stressed, .sluggish, .other`, `:12-16`), free `text`, no end field, "V1 is add + delete only; there is no edit path". State `journalNoteValues: [JournalNote]` (`DirectState.swift:61`), loaded for the selected day by `JournalNoteStore.swift:37-46` (`.loadJournalNoteValues` → `getJournalNoteValues(selectedDate:)`; re-fetched on `.setSelectedDate`, `:32-35`) and inserted via `.addJournalNote(journalNoteValues:)` (`:18-25`). **Regimes are derived from notes at render time — never a stored model.**
- **The note sheet:** `SheetCoordinator.ActiveSheet.journalNote` (`App/Views/SheetCoordinator.swift:22`, id `"journalNote"` `:41`), presented by `sheets.present(.journalNote)`; hosted in `RootSheetContent.swift:59-64` which builds `AddJournalNoteView(addCallback:)` and dispatches `.addJournalNote`. `AddJournalNoteView` (`App/Views/AddViews/AddJournalNoteView.swift`) has `@State var timestamp: Date = .init()` (`:17`) and `@State private var tag` (`:110`); the tag row toggles at `:59-60`. **Nested sheets are banned** (CLAUDE.md) — the note sheet is presented from the Overview through the coordinator exactly as the Log tab does.
- **Haptics / animation:** `DirectNotifications.shared.hapticFeedback(_:)` (`Library/DirectNotifications.swift:28`); `AnimationTokens` only (StyleGuard rule 7).
- **Do not touch:** the marker lane files; `ChartView.swift` (P0 already added the arms); `MealImpactStore` and the `★` scoring path (`App/Modules/MealImpact/`).

## Global constraints

The kickoff's constraint list applies verbatim (StyleGuard rules 1–10; no glow in `Chart{}`; explicit domains; `Double.map` for non-glucose values; UserDefaults-isolated tests; Redux 4-file lockstep for any new persisted state — this plan adds none; distinct pbxproj IDs + `plutil -lint` + the `-list | grep` check). Plus:
- **Every ribbon carries its reading count** (`· 24 RDG`, `· 7 RDG`); every residual carries `· N RDG`. No dosing language; the bracket is a *pairing* (`60g ⟷ 5U`), never a ratio, never "should".
- `mealImpactDeltaColor` remains the only tier source; `computeMealOverlayDelta` keeps its signature and behaviour (the tap sheet and `MealImpactStore` depend on it) — it becomes a thin wrapper over the kernel, pinned by a new equality test.
- No changelog entry (gated lab surface). No new middleware; regimes and residuals are pure functions of state already loaded.
- The lab is off by default; nothing here renders on the GLUCOSE tab.

---

### Task 0 — Test scaffold

- [ ] `DOSBTSTests/ChartLabMealsTests.swift` — pbxproj rows after the `ChartLabTests.swift` rows P0 added (PBXBuildFile / PBXFileReference / group / Sources phase), IDs `C1AB15010000000200A00001` (file ref) / `…00002` (build file). `plutil -lint` + `xcodebuild -list | grep -i "malformed\|multiple groups"` empty. Imports + the file-private `makeState()` / `reduce()` copied from `DirectReducerTests.swift:28-34`.

### Task 1 — `ResponseWindow` kernel (new file `Library/Content/ResponseWindow.swift`, pure, no SwiftUI)

```swift
/// Anchor-agnostic cause→effect window. Meals: `.max` over 2 h; exercise: `.min` over 3 h
/// (P-later); sleep: `.dawnRise`; a regime: `.slope` over its band.
struct ResponseWindow: Equatable {
    enum Summary: Equatable { case extremum(Extremum), slope }
    enum Extremum: Equatable { case max, min }
    let anchor: Date
    let lead: TimeInterval      // baseline lookback, meals 15 min
    let lag: TimeInterval       // window length, meals 2 h
    let summary: Summary
    static func meal(at anchor: Date) -> ResponseWindow { .init(anchor: anchor, lead: 15 * 60, lag: 2 * 60 * 60, summary: .extremum(.max)) }
}

struct ResponseSummary: Equatable {
    let baseline: Int?          // last reading in [anchor − lead, anchor)
    let extremum: Int?          // max/min in [anchor, end]
    let delta: Int?             // extremum − baseline (or first-in-window when no baseline)
    let timeToExtremumMinutes: Int?
    let n: Int                  // readings in [anchor, end]
    let isLowConfidence: Bool   // n < 4
    let isInProgress: Bool      // now − anchor < lag
    let end: Date               // min(anchor + lag, now)
}

enum ResponseKernel {
    static func summarize(_ window: ResponseWindow, readings: [SensorGlucose], now: Date = Date()) -> ResponseSummary
}
```
- [ ] Port `MealOverlayLogic.swift:36-66` into `summarize` (same baseline rule, same peak rule, same `n < 4`), then make `computeMealOverlayDelta` call `ResponseKernel.summarize(.meal(at: meal.timestamp), readings: sensorGlucoseValues, now: isInProgress ? Date() : meal.timestamp + 2 h)` and map to `MealOverlayDelta(delta:isLowConfidence:)`. **Behaviour must be identical** — pin it.
- [ ] Tests `@Suite("ResponseWindow kernel")`: fixtures `SensorGlucose(timestamp:rawGlucoseValue:intGlucoseValue:)` (`GlucoseStatisticsTests.swift:75`) — baseline = last reading before anchor within lead; delta = peak − baseline; no baseline → first-in-window; `n` counts only in-window readings; `isLowConfidence` at 3, not at 4; in-progress `end == now`; completed `end == anchor + lag`; **equality test:** for 20 randomised fixtures `computeMealOverlayDelta(…)` returns the same `delta`/`isLowConfidence` before and after the refactor (compute expected with the old algorithm inlined in the test).

### Task 2 — `MealResponseDatapoint` + builder (new file `App/Views/Overview/Lab/MealResponseDatapoint.swift`)

```swift
struct MealResponseDatapoint: Identifiable, Equatable {
    let id: String              // MealEntry.id.uuidString
    let mealTime: Date
    let windowEnd: Date         // min(mealTime + 2 h, domainEnd)
    let stubEnd: Date?          // mealTime + 2 h when in progress (dotted remainder), clamped
    let carbs: Double?
    let summary: ResponseSummary
    let pairedBolusUnits: Double            // RatioEstimator.pairedBolusUnits(mealTimestamp:deliveries:)
    let exclusion: MealExclusionReason?     // nil = clean; from the Ratio Lab taxonomy
    let confounders: MealConfounders         // detectMealConfounders(...)
}

func buildMealResponses(meals: [MealEntry], readings: [SensorGlucose], deliveries: [InsulinDelivery],
                        exercise: [ExerciseEntry], domainStart: Date, domainEnd: Date, now: Date = Date()) -> [MealResponseDatapoint]
```
Rules: skip meals outside `[domainStart − 2 h, domainEnd]`; `exclusion` via the same criteria Ratio Lab applies (`noBolus` when `pairedBolusUnits == 0`, `smallMeal` < 15 g, `hypoInWindow` when the window min < 70, `didNotReturnToBaseline` when completed and `|end − baseline| > 30`, `confounded` when `!confounders.isClean`) — implement as a pure `MealExclusionReason.classify(...)` helper if `RatioEstimator` has no reusable entry point (grep first; if it has one, call it).
- [ ] Extend `LabChartSeries` with `mealResponses: [MealResponseDatapoint]` and `regimes: [RegimeBand]` / `residuals: [ResidualSegment]` (Tasks 3–4); build them in `LabChartSeriesBuilder.build` only when the relevant overlay is in `inputs.overlays`. Add `journalNotes: [JournalNote]` to `LabChartInputs` (from `state.journalNoteValues`).
- [ ] Tests `@Suite("Meal response builder")`: clamp at `domainEnd`; stub only when in progress; `noBolus` when no paired bolus; `smallMeal` at 10 g; `confounded` when a correction bolus sits in the window; a clean 60 g meal with +54 → no exclusion.

### Task 3 — Residual segments (unexplained excursions)

```swift
struct ResidualSegment: Identifiable, Equatable {
    let id: String; let start: Date; let end: Date; let deltaMgDL: Int; let n: Int
}
enum ResidualDetector {
    /// A rise or fall of ≥ 40 mg/dL within ≤ 90 min with NO anchor (meal, bolus, exercise start/end,
    /// note, regime) inside [start − 30 min, end]. Sensor-noise guard: ≥ 4 readings and no single 5-min
    /// jump > 25 mg/dL (compression lows). Merges overlapping candidates.
    static func detect(readings: [SensorGlucose], anchors: [Date], regimes: [RegimeBand]) -> [ResidualSegment]
}
```
- [ ] Tests `@Suite("Residual detector")`: a +45 over 60 min with no anchor → one segment with `n`; the same rise with a meal 20 min before → none; a single 30-point jump → none (noise guard); two overlapping candidates → one merged.

### Task 4 — Regime bands (tags with duration, derived)

```swift
struct RegimeBand: Identifiable, Equatable {
    let id: String; let tag: JournalNoteTag; let start: Date; let end: Date; let isOpen: Bool
}
enum RegimeDeriver {
    /// Default durations: .sick → until the next note or 24 h; .stressed → 4 h; .sluggish → rest of the day;
    /// .other → no band. Closed early by the next tagged note or a note whose text is exactly "BACK TO NORMAL".
    static func derive(notes: [JournalNote], now: Date, dayEnd: Date) -> [RegimeBand]
}
```
- [ ] Tests `@Suite("Regime deriver")`: STRESSED at 15:00 → band 15:00–19:00; SICK at 09:00 with no later note → 24 h and `isOpen`; a later tagged note closes the earlier band; "BACK TO NORMAL" closes; `.other` yields nothing.

### Task 5 — The four overlay arms in `LabOverlayMarks.swift`

- [ ] `.mealResponseRibbons` (under-layer): per response — `RectangleMark(xStart: mealTime, xEnd: windowEnd, yStart: 0, yEnd: yMax)`; fill = `exclusion != nil ? hatched amberDark` (implement hatch as a second `RectangleMark` with `.foregroundStyle(.linearGradient(...))` is NOT available — use `AmberTheme.amberDark.opacity(0.10)` plus the label; a true hatch is optional via `.annotation(.overlay)` `Canvas` — only if it stays inside the 16 ms budget) `: mealImpactDeltaColor(delta).opacity(isLowConfidence ? 0.05 : 0.12)`; dotted stub `RectangleMark` stroke when in progress; label via `.annotation(position: .overlay, alignment: .topLeading)` in `DOSTypography.micro`, text = exclusion tag (`NO BOLUS`, `SMALL MEAL`, `CORR`, `STACKED`, `HYPO`, `ENDED +54`) or `+Δ · PEAK Nm · n RDG` or live `+Δ · M MIN · n RDG`; stagger label rows when ribbons overlap (prototype's 12-pt row offsets).
- [ ] `.carbSizedMeals` (over-layer): `PointMark(x: time, y: nearestGlucose(at:)?.value ?? 0)`, `symbolSize` from `ChartLabSizing.mealSymbolSize(carbs:)` — add that to `ChartLabOverlay.swift` if P0 did not (area 40…400 pt², ceiling 100 g; pin nil→40, 10→76, 100→400); `EventMarkerType.meal.color.opacity(carbs == nil ? 0.35 : 0.6)`; bracket under the dot when `pairedBolusUnits > 0`: a short `RuleMark` + `.annotation` `"\(Int(carbs))g ⟷ \(units)U"` in `amberDark` micro, flipped leftward for the last meal so it never enters the axis (prototype rule: `x > plotWidth − 70`).
- [ ] `.residualMarks`: hatched-amber `RectangleMark` over `[start, end]` at opacity 0.5 of `amber.opacity(0.10)`, a `?` glyph `PointMark`-annotation at the midpoint (black disc, amber `?`, `DOSTypography.mono(size: 13, weight: .bold)`), and a `.dosCard(.toast)` annotation `UNEXPLAINED +45 · 15 RDG · TAP TO NOTE`. Tap: `.chartOverlay` hit-test (a 44-pt target around the `?`) → `sheets.dismissThenPresent`? No — the Overview has no sheet up: `sheets.present(.journalNote)` after setting a **prefill**: add `case journalNote(prefill: JournalNotePrefill?)` … **no** — `ActiveSheet.journalNote` is a payload-less case whose id string is load-bearing for de-dupe. Add an optional associated value with the SAME id (`case journalNote(prefill: JournalNotePrefill? = nil)`; `id` stays `"journalNote"`), update the two existing call sites (Log tab, Digest) to `.journalNote()`, and have `RootSheetContent.swift:59-64` pass `prefill?.timestamp` into `AddJournalNoteView(timestamp:…)` (make `timestamp` an init parameter with a default of `.init()`) and pre-select `prefill?.tag`. Pin with `SheetCoordinatorTests`: `.journalNote()` and `.journalNote(prefill: …)` de-dupe as the same sheet.
- [ ] `.regimeBands` (under-layer): hatched `surfaceTint` `RectangleMark` over `[start, end]` with a black strip + label `STRESSED 15→19` (`amberLight` micro) placed BELOW the top exercise strip (prototype: 16 pt down); open bands extend to `domainEnd`.
- [ ] `STILL <TAG>? Y / N` row: in `LabMealsView`, when any regime `isOpen` and `now ≥ start + default duration − 30 min` (or on the next app activation after wake — keep V1 to the time rule), show a `.dosCard(.panel)` row under the chart: `STILL STRESSED?` + two 44×44 ghost buttons; **Y** → `sheets.present(.journalNote(prefill: .init(timestamp: now, tag: .stressed, text: "")))`; **N** → dispatch `.addJournalNote(journalNoteValues: [JournalNote(timestamp: now, text: "BACK TO NORMAL", tag: nil)])` (this is the close marker the deriver recognises). Pin the row's visibility rule in a pure `RegimePrompt.shouldShow(bands:now:)` test.
- [ ] Extend `LabMealsView`'s legend to the prototype's items; keep the footer.

### Task 6 — Suites, build

- [ ] Green: `ChartLabMealsTests`, `ChartLabTests`, `MealImpactTests` (delta tiers untouched), `SheetCoordinatorTests`, `StyleGuardTests`, `MarkerConsolidationTests`, `EventMarkerTypeTests`; then the full suite (log to file, grep the result line; known-flaky `AppGroupMiddlewareDispatchTests/startupSeedsKeys()`). Both targets build.

## Verification (simulator, virtual sensor; log: 35 g + 3 U at −11 h, 60 g + 5 U at −7 h, 10 g no bolus at −4.5 h, a 30-min run at −2 h, 80 g + 7 U at −38 min, a STRESSED note at −4.7 h)

1. `LAB: MEALS`: four dots sized 35 < 60 < 80 with 10 g smallest; brackets `35g ⟷ 3U`, `60g ⟷ 5U`, `80g ⟷ 7U` (last one flipped left); no bracket on the 10 g.
2. Ribbons: green `+Δ · PEAK Nm · n RDG` after the 35 g; amber after the 60 g (delta 30–59 with your fixture); hatched `NO BOLUS` after the 10 g; the 80 g ribbon grows with each virtual reading and shows `+Δ · M MIN · n RDG` with a dotted stub to +2 h; at +2 h it hardens and the label switches to `PEAK`.
3. The STRESSED note draws a hatched band 4 h long with its label under the top strip; after the band's end minus 30 min the `STILL STRESSED? Y / N` row appears; **N** logs `BACK TO NORMAL` and the band closes; **Y** opens the note sheet pre-tagged STRESSED at now.
4. Delete the 60 g meal's bolus in the Log tab → its ribbon turns hatched `NO BOLUS` on return.
5. A +45 rise with nothing logged (raise the virtual sensor 45 over an hour with no entries) → hatched segment with `?` and `UNEXPLAINED +45 · n RDG · TAP TO NOTE`; tap → the note sheet opens with the time picker at the excursion start; add a note → the `?` disappears (the note is now an anchor).
6. GLUCOSE tab: unchanged. Lab off → nothing of this renders.
7. mmol/L: labels convert; sizes unchanged.

## Out of scope

Exercise/sleep response windows (the kernel supports them; the factors wave draws them); the marker lane; stored regimes or a note edit path; changelog; NIGHT/SWEEP/PATTERNS/FACTS arms; COB; AI.

## Sibling / merge notes

Parallel with P1/P3/P4/P5 off the merged P0. You touch `LabOverlayMarks.swift` (four arms), `LabChartSeries.swift` (new fields), `ChartLabOverlay.swift` (sizing helper if absent), `SheetCoordinator.swift` + `RootSheetContent.swift` (prefill), `MealOverlayLogic.swift` (delegation) — P5 reads `MealOverlayLogic.swift` too; the train merges P5 before you. Never rebase onto or merge sibling work. Fold `IMPLEMENTATION_NOTES.md` into the PR body and `git rm` it before the train.
