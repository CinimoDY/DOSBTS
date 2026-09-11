# Chart Lab — exploration dossier

**Date:** 2026-09-11
**Tree:** `main` @ `18c9be1b` (Build 136)
**Purpose:** Complete map of the DOSBTS chart layer, written so a planning session and its workers can navigate by anchors instead of re-exploring. Every path and line number below resolves in the tree above.

**Read this before writing any Chart Lab plan. Do not re-explore the chart layer.**

---

## 1. Composition chain

`App/Views/OverviewView.swift:12-43`

```
GlucoseView()            // hero number + IOB label
SensorLineView()         // connection status row (not a chart)
TreatmentBannerView()    // conditional
ChartReportTypeRow()     // GLUCOSE | TIME IN RANGE | STATISTICS
ChartView(selectedReportType:onTapMarkerGroup:)   // .frame(maxHeight: .infinity)
ChartZoomRow()           // 3h/6h/12h/24h  or  7d/30d/90d/ALL
GlucoseStatusBar()       // safeAreaInset
```

`onTapMarkerGroup` routes to `sheets.present(.entryGroupReadOverlay(group))` at `OverviewView.swift:28-30`.

`App/Views/Overview/ChartView.swift` is **1055 lines and the only file in the repo that imports Charts**. Everything else that looks chart-like (widgets, the Digest timeline) is hand-drawn `Path` / `Canvas`.

### Seams inside ChartView

| Seam | Lines |
|---|---|
| `struct ChartView` properties | 11-16 |
| `body` — `switch selectedReportType` | 18-29 |
| `GlucoseChartContent` (private computed var) | 33-169 |
| ‣ day pager | 35-77 |
| ‣ HR legend + unit label row | 79-100 |
| ‣ `GeometryReader { chartAreaGeo in` | 102 |
| ‣ `ScrollViewReader` + horizontal `ScrollView` | 104-153 |
| ‣ `EventMarkerLaneView` (top position) | 107-117 |
| ‣ `glucoseChart.frame(width:height:)` | 119-120 |
| ‣ `EventMarkerLaneView` (bottom position) | 140-150 |
| ‣ `ChartSelectionTooltip` overlay | 155-164 |
| **`var glucoseChart` — the `Chart { }` body** | **171-590** |
| `private enum Config` | 594-621 |
| `@State` series storage | 623-651 |
| `debounceSeriesMetadata()` (100ms) | 653-658 |
| `chartHeight(available:)` | 660-667 |
| `screenWidth` / `yAxisSteps` / `zoomLevel` / `labelEvery` | 669-699 |
| `chartMinimum` / `alarmLow` / `alarmHigh` / `scaledHR` | 701-723 |
| `startMarker` / `endMarker` / `firstTimestamp` / `lastTimestamp` | 725-755 |
| `updateSeriesMetadata()` → `seriesWidth` | 794-809 |
| `updateSensorSeries()` (background queue) | 811-857 |
| `updateInsulinSeries()` → `insulinSeries` + `iobSeries` | 880-923 |
| `updateMealSeries()` | 925-928 |
| `updateExerciseSeries()` | 930-933 |
| `updateMarkerGroups()` | 935-988 |
| `updateSmoothedMinuteChange()` | 990-999 |

---

## 2. Every mark in the chart body, in z-order

`ChartView.swift:171-416`

| Lines | Mark | Purpose |
|---|---|---|
| 173-174 | `RuleMark(y: chartMinimum)` `.foregroundStyle(.clear)` | **invisible y-domain forcer** |
| 176-180 | `RectangleMark(yStart: alarmLow, yEnd: alarmHigh)` | in-range band, `cgaGreen.opacity(0.08)` |
| 182-188 | `RuleMark` ×2 | low/high limits, `cgaRed`, 1pt dash `[2]` |
| 190-201 | `LineMark` per `GlucoseSegment.points` | glucose trace, `.monotone`, 3.5pt round cap |
| 214-228 | `LineMark` ×2, `series: "prediction"` | 20-min dashed projection, `dash: [5,3]` |
| 238-245 | `PointMark(.cross, symbolSize: 80)` | predicted `alarmLow` crossing, `cgaRed` |
| 250-257 | `PointMark` | manual blood glucose, `symbolSize: 20`, `cgaRed` |
| 259-276 | `RectangleMark` + `.annotation(.overlay)` | basal bars, units mapped `0...20 → 0...alarmLow` |
| 290-320 | `AreaMark` (1 or 2 stacked layers) | IOB decay curve |
| 324-332 | `RectangleMark` | exercise band, thin strip at plot top, `cgaCyan.opacity(0.3)` |
| 337-359 | `LineMark` + `PointMark` + annotation | heart rate, `cgaMagenta`, `dash: [4,3]` |
| 365-387 | `LineMark` | raw/unsmoothed trace, double-tap toggle at `:136-138` |
| 390-409 | `PointMark` ×3 | drag-selection highlights, `symbolSize: 100` |
| 411-415 | `RuleMark(x: endMarker)` `.clear` | **invisible x-domain extender** |

### The domain trick — read this before adding any mark

**There is no `.chartXScale` and no `.chartYScale` anywhere.** Both domains are forced by the two clear marks at `:173` and `:411`.

Consequence: an overlay whose values exceed the current domain — a COB curve in grams, say — **silently rescales the entire glucose axis**. Every non-glucose overlay already in the chart avoids this by projecting onto the glucose axis with `Double.map(from:to:)` (`Library/Extensions/Double.swift:8`):

- IOB: `point.total.map(from: 0...iobCeiling, to: 0...Double(alarmLow))` — `:306`, `:316`
- Basal: `value.map(from: 0...20, to: 0...Double(alarmLow))` — `:264`
- Heart rate: `scaledHR()` runs BPM through `convertToRequired` so 80 bpm sits at 80 mg/dL — `:717-723`

**Reuse this pattern, or add an explicit `.chartYScale(domain:)`. There is no third option.**

### Axes

- X: `AxisMarks(values: .stride(by: .hour, count: labelEvery))` — `:417-424`, `labelEvery` from `zoomLevel`
- Y: `AxisMarks(position: .trailing, values: .stride(by: yAxisSteps))` — `:425-436`; `yAxisSteps` is 3 (mmol/L) or 50 (mg/dL) at `:677-683`

### Height and zoom

```swift
// ChartView.swift:660-667
private func chartHeight(available: CGFloat) -> CGFloat {
    let forChart = available - Config.markerLaneHeight
    return max(Config.minChartHeight, min(Config.chartHeight, forChart))
}
```

`Config` at `:594-621`: `chartHeight = 250`, `minChartHeight = 140`, `markerLaneHeight = 60`. It subtracts the lane height unconditionally, regardless of `markerLanePosition`. `available` comes from the `GeometryReader` at `:102`.

**Zoom is content width, not a scale domain.** `updateSeriesMetadata()` at `:794-809` computes `minuteWidth = screenWidth / (visibleHours * 60)` then `seriesWidth = minuteWidth * chartMinutes`, and the chart sits in a horizontal `ScrollView` at `width: max(0, screenWidth, seriesWidth)`. `ZoomLevel` is defined at `App/Views/Overview/ChartDatapoints.swift:14-19`; the four levels are in `Config.zoomLevels` at `:614-619`.

The day pager dispatches `.setSelectedDate` at `:765-770`. `selectedDate == nil` means "last 24h" (`DirectConfig.lastChartHours = 24`).

---

## 3. The report-type selector — the Chart Lab's mounting point

`Library/Content/ReportType.swift` is 21 lines:

```swift
enum ReportType: String, CaseIterable {
    // Raw values are UserDefaults persistence keys — keep them stable even if
    // the on-screen labels change, or saved selections silently reset.
    case glucose
    case timeInRange
    case statistics

    /// On-screen label, deliberately separate from the persisted rawValue.
    var label: String { ... }
}
```

`App/Views/Overview/ChartToolbar.swift`:

- `ChartReportTypeRow` at `:42-70` iterates **`ReportType.allCases`** at `:47` and dispatches `.setSelectedReportType`. Adding a case lights it up in the row and persists the selection with no further work.
- `normaliseDaysIfNeeded()` at `:64-69` bumps `statisticsDays` to 30 when a non-glucose type is selected with a `statisticsDays` value that no day chip exposes. **Any new multi-day lab case must be considered here** or the day chips will show nothing selected.
- `ChartZoomRow` at `:78-117` switches on `selectedReportType` at `:83` — `.glucose` gets the hours row, `.timeInRange`/`.statistics` get the days row. The switch is exhaustive, so the compiler finds every new case.
- `HoursZoom` at `:121-134`, `DaysZoom` at `:138-161` (`allDays = 9999` sentinel).

State: `DirectState.swift:180`, `AppState.swift:342`, persisted via `didSet`.

Report views live in `App/Views/Overview/ChartReportViews.swift` — `TimeInRangeReportView` `:14-48`, `StatisticsReportView` `:52-107`, `ChartSelectionTooltip` `:113-179`. Both reports read `store.state.glucoseStatistics` only.

**Adding a report type = a case in `ReportType`, a view, a `switch` arm at `ChartView.swift:20`, and a `ChartZoomRow` arm.** That is the whole cost.

**Layout warning:** the row is a plain `HStack` with `DOSSpacing.md` gaps and already carries `TIME IN RANGE`. Three or four more entries will overflow at phone width. Lab mode needs the row to become horizontally scrollable.

---

## 4. Event marker lane

### `Library/Content/EventMarker.swift` (273 lines)

```swift
enum EventMarkerType: Hashable { case meal, bolus, correction, basal, exercise }   // :13
    var icon: String   // :20   apple.logo / syringe.fill / syringe.fill / syringe / figure.run
    var color: Color   // :30   cgaGreen / amber / amberLight / amberDark / cgaCyan

struct EventMarker: Identifiable {        // :43
    let id: String
    let time: Date
    let type: EventMarkerType
    let label: String        // display string, e.g. "45g", "2.5U", "30m"
    let rawValue: Double     // carb GRAMS, insulin UNITS, or exercise MINUTES
    let sourceID: UUID       // FK to MealEntry.id / InsulinDelivery.id / ExerciseEntry.id
}

struct ConsolidatedMarkerGroup: Identifiable {   // :54
    let id: String           // "group-<first marker id>" — survives merges
    let time: Date           // median time of members after a merge
    let markers: [EventMarker]
    var isSingle: Bool { markers.count == 1 }
}
```

**Carb grams and insulin units are already on the marker**, in `rawValue` (untyped `Double`, semantics inferred from `type`). There is no protein/fat/fibre/calorie data on the marker and no `MealEntry` reference beyond `sourceID`.

`Equatable` at `:62-72` compares **`id` and `markers.count` only**. A changed `rawValue` will not trigger a re-render — so a visual driven by marker contents will not refresh when a value is edited in place. Pinned by `MarkerConsolidationTests.swift:162-174`.

### `chipRows(isScored:)` — `:115-163`

Locked three-lane order **insulin → meal → exercise**. All insulin sub-types collapse into one row as coloured `MarkerChipSegment`s, which is what guarantees the chip can never exceed three rows.

```swift
let meals = markers.filter { $0.type == .meal }
if !meals.isEmpty {
    let total = meals.reduce(0.0) { $0 + $1.rawValue }
    let prefix = isScored ? "★" : ""
    rows.append(MarkerChipRow(leadType: .meal,
        segments: [MarkerChipSegment(type: .meal, label: "\(prefix)\(Int(total))g")]))
}
```

Suffixes: `U` bolus, `Uc` correction, `Ub` basal, `g` carbs, `m` exercise minutes. `formatMarkerUnits` at `:268-273` drops a trailing `.0`.

### Chip width estimation — `:182-202`

```swift
static let chipMonoCharWidth: CGFloat = 7      // 11pt SF Mono semibold advance
static let chipIconWidth: CGFloat = 14
static let chipIconTextGap: CGFloat = 4
static let chipHorizontalPadding: CGFloat = 5
```

`estimatedChipWidth(isScored:)` takes the widest row (`icon + segments.count * gap + Σ chars * 7`) and adds 10. `★` counts as two characters.

**All four constants and specific computed widths are pinned** in `DOSBTSTests/MarkerConsolidationTests.swift:218-272` — `5U` is 42pt, a triple stack is 99pt. This is deliberate: the estimate must mirror `FlagView`'s real geometry, because consolidation depends on it.

### `consolidateByOverlap` — `:228-263`

The single consolidation authority (DMNC-1415). Walks groups left to right and merges when

```swift
groupX - lastX < max((w(last) + w(group)) / 2 + minGap, minMergeDistance /* 64 */)
```

A merged group keeps the earlier id, concatenates markers, and re-anchors to the median time. `minMergeDistance = 64` at `:226` is a floor justified by the 88pt touch target.

Stage one (`ChartView.updateMarkerGroups`, `:935-988`) emits **exactly one group per marker**. All grouping happens in the lane.

### `App/Views/Overview/EventMarkerLaneView.swift` (140 lines)

```swift
private let laneHeight: CGFloat = 60          // :18  duplicated from ChartView.Config.markerLaneHeight
private let touchTargetWidth: CGFloat = 88    // :19
private let touchTargetHeight: CGFloat = 48   // :20
private let yAxisPadding: CGFloat = 30        // :21
private let minChipGap: CGFloat = 4           // :23
```

- `body` `:25-54` calls `consolidateByOverlap` **inside the view body on every render** (`:30-35`) — O(n), not memoised. Adding per-group work here costs on every scroll frame.
- `xPosition(for:)` `:75-81` is `(offset / totalDuration) * (totalWidth - yAxisPadding)` — a **linear approximation** of the Charts plot area, not the real `plotFrame`. New lane content must use the same mapping or it drifts from the chart. The real `plotFrame` is available in `.chartOverlay` at `ChartView.swift:548-556` if exact alignment is needed.
- `isGroupScored` `:56-60` — true if any meal marker's `sourceID` is in `scoredMealEntryIds`.
- `FlagView` `:91-140` — `VStack(spacing: 1)` of rows; each row is an `HStack(spacing: 4)` of an 11pt icon and `Text` segments in `DOSTypography.mono(size: 11, weight: .semibold)`; `.padding(.horizontal, 5).padding(.vertical, 3)`; background `dosBlack.opacity(0.92)`; 1pt `Rectangle().stroke` border, `amber` when scored else `amberDark`.

**Budget arithmetic:** 3 rows × (11pt text + 1pt spacing) + 6pt vertical padding ≈ 45pt, inside a 48pt touch target, inside a 60pt lane. A fourth row, or taller rows, overflows and is clipped. The invariant is documented at `EventMarker.swift:106-113` and pinned at `EventMarkerTypeTests.swift:113-124`.

**Lane height is hard-coded in two places** — `ChartView.Config.markerLaneHeight = 60` at `:620` and `EventMarkerLaneView.laneHeight = 60` at `:18`. Changing one without the other silently clips.

---

## 5. Data models

| Model | File | Fields relevant to visualization |
|---|---|---|
| `MealEntry` | `Library/Content/MealEntry.swift:10-59` | `id`, `timestamp` (rounded to 1 min), `mealDescription`, **`carbsGrams: Double?`**, `proteinGrams?`, `fatGrams?`, `calories?`, `fiberGrams?`, `timegroup` (15-min bucket), `analysisSessionId?` |
| `InsulinDelivery` | `Library/Content/InsulinDelivery.swift:36-75` | `id`, `starts`, `ends`, **`units: Double`**, `type: InsulinType`, `timegroup` |
| `InsulinType` | same file `:10-34` | `.mealBolus`, `.snackBolus`, `.correctionBolus`, `.basal`; `shortLabel` at `:92` |
| `SensorGlucose` | `Library/Content/SensorGlucose.swift:53-133` | `timestamp`, `rawGlucoseValue`, `intGlucoseValue`, `smoothGlucoseValue?`, `minuteChange?`, computed `glucoseValue` (clamped 39…501), `trend`, `type` |
| `ExerciseEntry` | `Library/Content/ExerciseEntry.swift:10-53` | `startTime`, `endTime`, `activityType`, `durationMinutes`, `activeCalories?`, `source?` |
| `GlucoseStatistics` | `SensorGlucose.swift:14-41` | `readings`, `gmi`, `avg`, `tbr`, `tar`, `variance`, `days`; computed `tir`/`tor`/`stdev`/`cv` |
| `MealImpact` | `Library/Content/MealImpact.swift:10-49` | `mealEntryId`, `baselineGlucose?`, `peakGlucose`, `deltaMgDL`, `timeToPeakMinutes`, `isClean` |

### Chart-local plotting models — `App/Views/Overview/ChartDatapoints.swift`

`ZoomLevel` `:14`, `GlucoseDatapoint` `:31`, `GlucoseSegment` `:49` with `segmentGlucoseSeries()` `:70` (splits by colour level with overlapping boundary points), `InsulinDatapoint` `:108`, **`MealDatapoint` `:119` (`id, time, label, carbs: Double?`)**, `ExerciseDatapoint` `:139`, plus `toDatapoint` extensions `:126-270`.

### Dead code that is ready to use

- **`mealSeries` is computed every render and rendered nowhere.** `@State` at `ChartView.swift:631`, filled by `updateMealSeries()` at `:925-928`, referenced nowhere in the `Chart { }` body. `MealDatapoint.carbs` is an already-wired carrier for a carb-sized meal mark — only the marks are missing.
- **Vestigial `Config` constants from an earlier value-sized-symbol implementation, currently unused:** `insulinSize: MarkDimension = 10` `:598`, `mealSymbolSize: CGFloat = 120` `:601`, `insulinSymbolSizeRange: 30...160` `:602`, `spacerWidth` `:603`, `cornerRadius`/`rangeCornerRadius` `:596-597`, `lineStyle`/`gridStyle`/`dayStyle` `:606, 610-611`.
- **`chartShowLines`** is declared at `DirectState.swift:37`, persisted at `AppState.swift:240`, and read by no view.

### State properties feeding the chart

Protocol in `Library/DirectState.swift`, concrete in `App/AppState.swift`.

| Property | DirectState | AppState | Persisted |
|---|---|---|---|
| `sensorGlucoseValues` | :81 | :196 | no (DB) |
| `bloodGlucoseValues` | :36 | — | no |
| `mealEntryValues` | :60 | :181 | no |
| `insulinDeliveryValues` | :57 | :175 | no |
| `exerciseEntryValues` | :54 | :172 | no |
| `iobDeliveries` | :131 | :309 | no |
| `heartRateSeries: [(Date, Double)]` | :55 | :173 | no |
| `scoredMealEntryIds: Set<UUID>` | :134 | :312 | no |
| `chartZoomLevel` | :38 | :241 | yes |
| `selectedReportType` | :180 | :342 | yes |
| `markerLanePosition` | :125 | :303 | yes |
| `showSplitIOB` | :130 | :308 | yes |
| `showHeartRateOverlay` | :122 | :300 | yes |
| `showSmoothedGlucose` | :88 | — | yes |
| `selectedDate` / `minSelectedDate` | :77-78 | — | — |
| `glucoseStatistics` / `statisticsDays` | :84-85 | — | — |

### Middlewares and their load windows

| Data | Middleware | Window |
|---|---|---|
| meals | `App/Modules/DataStore/MealStore.swift:10-71`, query `:224-253` | `selectedDate`'s day, else last `DirectConfig.lastChartHours` (24) h |
| insulin | `App/Modules/DataStore/InsulinDeliveryStore.swift:211` | same shape |
| exercise | `App/Modules/DataStore/ExerciseStore.swift:169` | same shape |
| IOB deliveries | `App/Modules/IOB/IOBMiddleware.swift:41-51` → `InsulinDeliveryStore.swift:244-264` | `starts >= now - max(bolusDIA, basalDIA)` — **independent of the chart window** |
| scored meal ids | `App/Modules/MealImpact/MealImpactStore.swift:52-59` | all scored |

All reload on `.setAppState(.active)` and on their own add/update/delete actions. Actions at `DirectAction.swift:89, 93, 96, 120, 213, 218`; reducer at `DirectReducer.swift:218, 221, 248, 524, 539`.

**The chart's data window is one day maximum.** Multi-day pattern views must go through a different read path (see §7).

### Re-derivation

Series are rebuilt in `.onChange` handlers at `ChartView.swift:439-547`, with a 100ms debounce for width metadata. Heavy work goes to `calculationQueue` (`:649`) after a main-actor snapshot of state (see the comment at `:814-817` — required for Swift 6 strict concurrency).

**A new data source needs both an `.onChange` arm and a call in the `onAppear` block at `:535-547`**, or it stays empty on first render.

---

## 6. Existing overlays — toggles and styling

| Overlay | Location | Toggle | Styling |
|---|---|---|---|
| **IOB area** | `ChartView.swift:278-322` | `showSplitIOB` for split vs single; drawn whenever `iobSeries` is non-empty | Split: basal `iobBasal.opacity(0.85)` (`series: "Basal"`), bolus stacked above at `iobBolus.opacity(0.7)` (`series: "Bolus"`). Single: `iobBolus.opacity(0.4)`. `.interpolationMethod(.monotone)`. Setting at `App/Views/Settings/InsulinSettingsView.swift:105`. **The `series:` label is load-bearing** — the comment at `:286-289` records that without it the two `ForEach` loops auto-group into one stack and only one renders. |
| **Predictive projection + cross** | `ChartView.swift:203-248` | **not gated by `showPredictiveLowAlarm`** — only by latest reading under 5 min old, `selectedDate == nil`, and `smoothedMinuteChange != nil` | 20-min horizon, `dash: [5,3]`, lineWidth 2, colour from `AmberTheme.glucoseColor(forValue:)`. Crossing marker `PointMark(.cross)` `symbolSize 80` `cgaRed`, only when `minuteChange < 0` and the crossing lands within 20 min. Slope is the mean of the last three non-nil `minuteChange` (`:990-999`). |
| **Heart rate** | `:334-361`, legend `:81-96` | `showHeartRateOverlay` (`App/Views/Settings/AppleExportSettingsView.swift:51`) | `cgaMagenta.opacity(0.3)`, `dash: [4,3]`, lineWidth 1; latest point `symbolSize 30` with a trailing BPM annotation. Plotted on the glucose axis via `scaledHR` `:717-723`. |
| **Exercise band** | `:324-332` | always, when entries exist | `cgaCyan.opacity(0.3)`, thin strip at plot top |
| **Basal bars** | `:259-276` | always | `amberDark` at 0.25 opacity, overlay annotation on a `dosBlack.opacity(0.5)` chip |
| **Raw trace** | `:363-388` | **double-tap the chart** (`showUnsmoothedValues` `:136-138`) and `showSmoothedGlucose` | `amberDark` at 0.5 opacity |
| **Meal impact** | not on the chart — `★` prefix on the chip (`EventMarker.swift:151`) plus the tap sheet `App/Views/Overview/EntryGroupListOverlay.swift` (453 lines) | `scoredMealEntryIds` | Helpers in `App/Views/Overview/MealOverlayLogic.swift`: `mealImpactDeltaColor(delta:)` `:18` (green under 30, amber 30–59, red 60+ mg/dL), `computeMealOverlayDelta` `:31` (2-hour window, −15 min baseline), `detectMealConfounders` `:78` |
| **TIR / Statistics** | `ChartReportViews.swift:14` / `:52` | `selectedReportType` | `HeroStatView`, `StackedTIRBar`, `StatCard` from `Library/DesignSystem/Components/StatsComponents.swift` |
| **Drag tooltip** | `ChartReportViews.swift:113-179`, driven by `.chartOverlay` at `ChartView.swift:548-589` | while dragging | 0.75 opacity, coloured chips per source |

Marker lane position (above or below the chart) is `markerLanePosition`, picker at `App/Views/Settings/GlucoseDisplayCategoryView.swift:83`.

---

## 7. Carb absorption — nothing exists

`grep -i "COB\|carbsOnBoard\|absorption"` across `Library/`, `App/`, `Widgets/` and `DOSBTSTests/` returns **zero hits** for carb absorption. The only "absorb" matches are an unrelated comment in `TightControlStreakDetector.swift:38` and a test name in `IOBCalculatorTests.swift:23`.

What does exist that touches carbs numerically:

- **`Library/Content/RatioEstimator.swift`** (484 lines) — `fiveHundredRuleICR = 500/TDD` `:167, :240`, `empiricalICR` as the median of carbs ÷ bolus over clean meals `:247-254`, P25–P75 spread, exclusion-reason enum `:80`. Surfaced by `App/Views/Settings/RatioLabView.swift` (572 lines).
- **`Library/Content/MealImpact.swift`** — observed post-meal delta, peak and time-to-peak. Observation, not a model.
- **`App/Views/Overview/MealOverlayLogic.swift:31-67`** — the peak-minus-baseline computation.
- **`Library/Content/InsulinImpact.swift`** — the insulin-side mirror; `InsulinConfounder.mealInWindow` `:14` is the only place a meal's carb presence enters an impact calculation.
- **`App/Modules/MissedBolusNudge/MissedBolusDetector.swift`** — carb-bearing meal without a bolus.

### The template for a COB model

`Library/Content/IOBCalculator.swift` (173 lines) — pure, no SwiftUI, unit-tested:

```
ExponentialInsulinModel          :44
  percentEffectRemaining(at:)    :74
IOBResult                        :112
computeIOB(deliveries:bolusModel:basalModel:at:)   :121   // free function
```

A `COBCalculator` of the same shape drops straight into the 60-second sampling loop that already feeds the IOB area at `ChartView.swift:895-922`.

**Safety constraint:** Ratio Lab's discipline applies without exception — no imperative dosing language, no carbs-in/units-out field, every number ships with its sample size. A COB curve is a teaching aid, never a bolus calculator. See the Ratio Lab bullet in `CLAUDE.md` and `docs/plans/2026-07-03-ratio-lab-plan.md`.

---

## 8. Multi-day data — the clinic-report seam

For pattern views, the work is largely done.

**`Library/Content/ClinicReport.swift`:**

```
HourlyPattern                         :41    // hour, median, p25, p75, readings
ClinicReportRaw                       :53
ClinicReportData                      :63
  hourlyPatterns: [HourlyPattern]     :65    // ALWAYS 24 entries, hour 0...23
ClinicReportBuilder.hourlyPatterns(from:calendar:)   :119
```

`hourlyPatterns` already returns **median, p25 and p75 per hour across the whole period**, and it is unit-tested. That is most of an AGP panel already in the repo, used by no on-screen view. Adding the 5th and 95th percentiles is a small extension of an existing tested function.

`ClinicReportStore.getClinicReportData(days:)` is **one `asyncRead`, no writes**, over a selectable 14/30/90-day period. `clinicReportMiddleware` lives in `App/Modules/Report/` and is registered in **both** `App.swift` middleware arrays.

Related conventions from `CLAUDE.md`: the clinic report deliberately uses the consensus 70–180 TIR band rather than the user's alarm profile, and `getSensorGlucoseStatistics` is fileprivate, exposed module-wide through the thin `clinicGlucoseStatistics` wrapper in `SensorGlucoseStore.swift`.

**GRDB rule:** never call `dbQueue.write` inside a `dbQueue.asyncRead` callback — it deadlocks. See `docs/solutions/logic-errors/grdb-write-inside-asyncread-deadlock-20260420.md`.

---

## 9. Tests that pin chart and marker behaviour

| File | Pins |
|---|---|
| `DOSBTSTests/MarkerConsolidationTests.swift` (273) | `consolidateByOverlap` separation and merge, id/order/median preservation, transitive chains, zoom-split regression `:108`, `minMergeDistance == 64` `:140`, narrow-chip floor `:145`, Equatable-includes-count `:162`, averaged-width threshold `:178`. Second suite `ChipWidthEstimateTests` `:205` — the four layout constants `:218`, `5U == 42pt` `:226`, triple stack `== 99pt` `:234`, monotonicity `:257`, `★ == +2 chars` `:265` |
| `DOSBTSTests/EventMarkerTypeTests.swift` (219) | `InsulinType.markerType` mapping `:11`, marker colours `:46`, colour distinctness `:72`, **`MarkerChipRowTests` `:100` with the 3-row invariant at `:113`**, segment ordering, suffixes, per-type summing, `★` prefix, fractional units |
| `DOSBTSTests/StyleGuardTests.swift` (280) | the ten source-scan design-system rules — see §10 |
| `DOSBTSTests/DesignTokenPinTests.swift` (439) | `iobBolus == #8CBF40` `:142`, `iobBasal == #5DD0F3` `:152`, `glucoseHero` font `:281`, derived glucose buffer colours `:437` |
| `DOSBTSTests/EntryGroupListOverlayTests.swift` | marker-tap sheet sublines, `rowTime`, `isEditable`, `deleteKind` |
| `DOSBTSTests/IOBCalculatorTests.swift` | the IOB decay math feeding the area mark |
| `DOSBTSTests/MealImpactTests.swift` (359) | impact scoring behind the `★` chips |
| `DOSBTSTests/GlucoseStatisticsTests.swift` | TIR and statistics numbers |
| `DOSBTSTests/ClinicReportRenderSeamTests.swift` | asserts a valid non-empty `%PDF` |

Tests are UserDefaults-isolated: `AppState(defaults:)` takes an injected store and `makeTestDefaults()` (in `DirectReducerTests.swift`) hands each test a fresh suite. **Never construct `AppState()` bare in a test.**

**New test files are not auto-synced.** Each needs a manual entry in the `DOSBTSTests` group and `PBXSourcesBuildPhase` in `project.pbxproj`, and each plan must be handed a **distinct object-ID pair** up front. Two workers both taking "the next free pair" produces duplicate ids that `plutil -lint` reports as OK while Xcode silently drops one test file from the target. Follow with:

```bash
xcodebuild -project DOSBTS.xcodeproj -list 2>&1 | grep -i "malformed\|multiple groups"   # must be empty
```

---

## 10. Design-system constraints

**`StyleGuardTests` reads `.swift` files off disk and fails `Cmd+U` on ten rules** (whole-line comments are skipped):

1. No `.font(.system(` or `.font(Font.system(` — use `DOSTypography` — `:140`
2. No system Dynamic Type styles (`.body`, `.caption`, `.headline`, …) — `:148`
3. No `Color.black` or `(.black)` fills — use `AmberTheme.inkOnAmber` / `dosBlack` — `:158`
4. No `.foregroundColor()` — use `.foregroundStyle()` — `:169`
5. **No `cornerRadius:` or `.cornerRadius(` — sharp corners only** — `:175`
6. No bare `ProgressView()` in `App/Views` — use `FiguresLoadingView` — `:185`
7. No inline animation curves — use `AnimationTokens`; `Library/DesignSystem/` is exempt — `:196`
8. No raw `Color(red:`, `white:`, `hue:` outside `AmberTheme.swift` — `:207`
9. Section headers must use `.dosHeader()` — `:228`
10. `DigestColorRoutingGuardTests` `:262` — Digest timeline colours must route through `EventMarkerType.color`, never a raw `AmberTheme` token. **`EventMarkerType.color` is the canonical marker palette for both surfaces.**

**From `docs/design-system.md`:**

- `:127` — **no glow shadows inside a `Chart { }` body or a `ForEach` list row** (performance)
- `:48-49` — `iobBolus #8CBF40` and `iobBasal #5DD0F3` are registered tokens
- `:88` — `caption` (12pt mono) is the chart-axis type role
- `:262` — dense or net-new screens, explicitly naming "chart, marker lane", go through a Figma frame first

Surface chrome: `.dosCard(_ variant:stroke:padding:)` and `.dosHeader(_ color:)` in `Library/DesignSystem/Modifiers/DOSSurfaces.swift` are the only sanctioned way to build card panels and section headers. Never hand-roll `overlay(Rectangle().stroke(...)) + background`.

---

## 11. Summary of open seams

| Want | Seam | State |
|---|---|---|
| Carb-sized meal marks | `mealSeries` + `MealDatapoint.carbs` | computed every render, rendered nowhere |
| Symbol-size range for value-scaled marks | `Config.mealSymbolSize`, `Config.insulinSymbolSizeRange` | declared, unused, left from an earlier implementation |
| Meal cause-and-effect shading | `computeMealOverlayDelta`, `mealImpactDeltaColor` | written and tested, used only in the tap sheet |
| A second graph line for carbs | none — model absent | mirror `IOBCalculator.swift` |
| AGP percentile curve | `ClinicReportBuilder.hourlyPatterns` (median/p25/p75 × 24h) | written and tested, no on-screen consumer |
| Multi-day reads | `ClinicReportStore.getClinicReportData(days:)` | one `asyncRead`, 14/30/90 days |
| New top-row tabs | `ReportType` + `ChartReportTypeRow` iterating `allCases` | adding a case is the whole cost |
| Line-visibility toggle | `chartShowLines` | declared and persisted, read by nothing |
