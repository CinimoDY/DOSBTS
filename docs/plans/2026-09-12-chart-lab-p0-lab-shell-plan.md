# Chart Lab P0 — Lab shell, native lab chart, instrument cursors — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven-development). Checkbox steps. Read the file at each anchor before editing; anchors were verified on `main` @ `3a288d3d` — re-verify each on your branch. Record every deviation in `IMPLEMENTATION_NOTES.md`: plan errors surface as deviations, and the orchestrator reads them as findings about the plan.

**Issue:** "P0 — Lab shell + instrument cursors" (child of DMNC-1500) · **Branch:** `feat/chart-lab-p0-shell` · **Worktree:** `../DOSBTS-wt-lab-p0` · **Tier:** Opus · **Simulator:** `-destination 'id=9A948885-80C7-4A96-A9FB-D2742595AD3B'` (iPhone 17 Pro, iOS 26.5 — always by `id=`; device names repeat across three runtimes) · **pbxproj object IDs:** file ref `C1AB15010000000100A00001`, build file `C1AB15010000000100A00002`. Sibling plans hold `C1AB1501…0002…`, `C1AB1503…`, `C1AB1504…`, `C1AB1505…` — never take "the next `TE01…` pair".

**Visual spec:** artboards **0 (Main)** and **1 (Cursors)** of the prototype canvas — https://claude.ai/code/artifact/0f40d578-b3a3-460c-a651-aff0f3240dfb (sources: `.context/compound-engineering/ce-prototype/2026-09-12-chart-lab-directions/01-chart-lab-directions/screens/Cursors.dc.html`). Copy its states and labels: `A 12:04 → B 13:44 · Δt 1h40`, `G 169→201 (+32) · MIN 152 · MAX 206 · IN 5.0U · CARBS 60g · n=20`, the `◂ 3 NEW` nub, the legend `A→B MEASURES · FOLLOW OFF · 3 NEW`, the footer `LAB · EXPERIMENTAL · NOT DOSE ADVICE`.

**Intent (Dom, verbatim):** "How do we visualize it on the iPhone so it's really engaging and fun, but also very professional? I want to keep it as close as possible to the Apple standards, like the way HealthKit works and the interface. Obviously, give it our colors, but really use the best technology to show these charts and make the info interactive." … "can we just build all and deploy to testflight? that way i can play about, test on device and then give feedback"

**Goal:** Behind a new off-by-default `showChartLab` setting, four lab tabs join the top row (`LAB: MEALS`, `LAB: NIGHT`, `LAB: SWEEP`, `LAB: PATTERNS`). `LAB: MEALS` renders a **new native Swift Charts lab chart** (`LabChartView`) with the shipping chart's baseline marks, Health-style scrolling and hour snapping, and the **instrument cursors**: a scrub cursor that persists after release, an A/B range with a fixed readout strip below the plot, a detached-FOLLOW state with a `◂ N NEW` nub, and detent haptics. The other three lab tabs show a placeholder that P1/P3/P4 replace. The shipping `GLUCOSE` chart body is not edited.

## Architecture (verified findings)

- **Mounting point.** `ReportType` (`Library/Content/ReportType.swift`, 21 lines, 3 cases; raw values are UserDefaults keys) drives `ChartReportTypeRow` (`App/Views/Overview/ChartToolbar.swift:42-70`, iterates `allCases` at `:47`), `ChartZoomRow`'s exhaustive switch (`:83-88`) and `ChartView.body`'s switch (`App/Views/Overview/ChartView.swift:20-27`). `normaliseDaysIfNeeded()` (`:64-69`) guards on `!= .glucose`.
- **Selection persistence.** `DirectState.swift:180`, `AppState.swift:156` (init) / `:342` (didSet), key `UserDefaults.swift:114` (`:1340-1342`, default `.glucose`), reducer `DirectReducer.swift:493-494`, action `DirectAction.swift:193`.
- **4-file Bool precedent** `showHeartRateOverlay`: `DirectState.swift:121-122`, `AppState.swift:145` + `:299-300`, `UserDefaults.swift:82` + `:1100-1108` (default `false`), `DirectAction.swift:203-204`, `DirectReducer.swift:506-508`. Settings shape: `GlucoseDisplayCategoryView.swift:71-79` (toggle + caption) and `:108-113` (binding).
- **Reducer test precedent:** `DOSBTSTests/DirectReducerTests.swift:600-612`. `makeTestDefaults()` (`:15-22`) is target-wide; `makeState()` / `reduce()` (`:28-34`) are file-private — copy them.
- **Series helpers reused unchanged:** `SensorGlucose.toDatapoint(glucoseUnit:alarmLow:alarmHigh:)` / `.toSmoothDatapoint` (`App/Views/Overview/ChartDatapoints.swift:194-230`; call sites `ChartView.swift:1040-1054`); `BloodGlucose.toDatapoint(...)` (`:175-192`); `segmentGlucoseSeries(_:)` (`:70`); `InsulinDelivery.toDatapoint(minDate:maxDate:)` (`:158`); `MealEntry.toDatapoint()` (`:127`); `ExerciseEntry.toDatapoint()` (`:147`); `computeIOB(deliveries:bolusModel:basalModel:at:)` (`Library/Content/IOBCalculator.swift:121`) with `ExponentialInsulinModel.bolus(preset:)` (`:93`) / `.basal(diaMinutes:)` (`:84`); `Double.map(from:to:)` (`Library/Extensions/Double.swift:9`); `DirectNotifications.shared.hapticFeedback(_:)` (`Library/DirectNotifications.swift:28`).
- **Shipping-chart facts to mirror, not touch:** domain (`ChartView.swift:725-755`: start = earliest sensor/blood timestamp; end = latest + 15 min only when `selectedDate == nil`); `chartMinimum` (`:701-707`: 300 mg/dL / 18 mmol/L); `convertToRequired(mgdLValue:)` (`:757-763`); IOB projection `0...iobCeiling → 0...alarmLow` (`:294, :306, :316`); basal `0...20 → 0...alarmLow` (`:264`); exercise strip (`:324-332`); HR via `scaledHR` (`:717-723`); axes (`:417-436`); IOB 60 s sampling loop (`:895-916`); the load-bearing `series:` label on stacked areas (`:286-289`); main-actor snapshot before background work (`:814-817`, `:883-893`); the shipping drag overlay clears every selection on release (`:577-586`) — the lab deliberately does not.
- **Chart models are not `Sendable`** (`SensorGlucose.swift:53`, `MealEntry.swift:10`, `InsulinDelivery.swift:36`, `ExerciseEntry.swift:10`, `BloodGlucose.swift:10`) → off-main work uses the `DispatchQueue` snapshot pattern (`:880-923`), not `Task.detached`. They **are** Equatable (the nine `.onChange(of: store.state.xValues)` sites at `:439-507` compile).
- **Charts APIs.** `chartXSelection(value:)`, `chartXSelection(range:)`, `chartScrollableAxes`, `chartXVisibleDomain(length:)`, `chartScrollPosition(x:)`, `chartScrollTargetBehavior`, `chartGesture` are iOS 17; vectorized `LinePlot`/`AreaPlot` are iOS 18. Target is iOS 26.0. **Function plots need a numeric x-axis — do not use them on the Date axis.** None are used in the repo yet (grep verified), so signatures are confirmed at first compile — record the exact ones in `IMPLEMENTATION_NOTES.md`. Known behaviours to plan around (critic-verified): on a scrollable chart the built-in selection gesture is long-press-then-drag (a plain drag scrolls); the `value`/`range` bindings **reset to nil on release** — a sticky cursor mirrors them into local state; changing `chartXVisibleDomain` re-anchors scroll unless `chartScrollPosition` is co-set.
- **Marker lane: not mounted on lab tabs.** Nothing in `EventMarker.swift`, `EventMarkerLaneView.swift`, `MarkerConsolidationTests.swift`, `EventMarkerTypeTests.swift` changes.

## Global constraints

- **`ChartView.swift` diff is exactly the four added switch arms** in `:20-27` (`git diff --stat main -- App/Views/Overview/ChartView.swift` ≤ 6 lines). GLUCOSE / TIME IN RANGE / STATISTICS behaviour and the row's layout with the lab off are unchanged.
- Persisted keys: new `libre-direct.settings.show-chart-lab`; `ReportType` raw values `labMeals`, `labNight`, `labSweep`, `labPatterns` are persistence keys — never rename.
- `StyleGuardTests` rules 1–10: no `.font(.system(`, no system Dynamic Type, no `Color.black`, no `.foregroundColor`, no `cornerRadius`, no bare `ProgressView()` (use `FiguresLoadingView.inline`), no inline animation curves (use `AnimationTokens`), no raw `Color(red:` outside `AmberTheme`, `header: {` needs `.dosHeader(` within 8 lines, marker colours via `EventMarkerType.color`.
- No glow/shadow inside `Chart { }` (`docs/design-system.md:127`).
- The lab chart sets **explicit** `.chartXScale(domain:)` / `.chartYScale(domain:)`; every non-glucose stream maps into the y domain with `Double.map(from:to:)`.
- In-chart alphas on marks follow the shipping precedent (`:180`, `:297`, `:331`); off-chart chrome uses semantic tiers (`borderSubtle`, `textFaint`) or `.dosCard` — never `.opacity()` on a palette token in a view.
- Readout strip height is **pinned** (branch-height learning: `docs/solutions/ui-bugs/swiftui-viewbuilder-branch-height-mismatch-layout-jump.md`); chart height derives from `GeometryReader`, never `UIScreen` (`docs/solutions/ui-bugs/swiftui-vstack-overflow-sinks-safeareainset.md`).
- No new middleware; no `dbQueue` access. Redux 4-file lockstep for `showChartLab` (reviewed by `redux-state-coherence-reviewer`). Tests: `AppState(defaults: makeTestDefaults())` only.
- Every derived number in the readout carries its `n`; no dosing language anywhere; the footer `LAB · EXPERIMENTAL · NOT DOSE ADVICE` is on every lab tab.
- CHANGELOG: one `[Unreleased] / Added` line for the toggle (gated surfaces need no entry).

---

### Task 0 — Test scaffold (fails first)

**Files:** create `DOSBTSTests/ChartLabTests.swift`; modify `DOSBTS.xcodeproj/project.pbxproj` (four rows).

- [ ] Insert after each `DictationDisplayModelTests.swift` row (on `main`: `:70` PBXBuildFile, `:166` PBXFileReference, `:339` group children, `:564` test Sources phase; 2-tab indent for the first two, 4-tab for the last two):
  ```
  C1AB15010000000100A00002 /* ChartLabTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = C1AB15010000000100A00001 /* ChartLabTests.swift */; };
  C1AB15010000000100A00001 /* ChartLabTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ChartLabTests.swift; sourceTree = "<group>"; };
  C1AB15010000000100A00001 /* ChartLabTests.swift */,
  C1AB15010000000100A00002 /* ChartLabTests.swift in Sources */,
  ```
- [ ] `plutil -lint DOSBTS.xcodeproj/project.pbxproj` → OK **and** `xcodebuild -project DOSBTS.xcodeproj -list 2>&1 | grep -i "malformed\|multiple groups"` → empty.
- [ ] `ChartLabTests.swift`: `import Foundation`, `import SwiftUI`, `import Testing`, `@testable import DOSBTSApp`; copy the file-private `makeState()` / `reduce()` from `DirectReducerTests.swift:28-34`. Add each suite below **before** the code it pins; confirm red, then green.

### Task 1 — `showChartLab` (4-file + action + reducer rule)

- [ ] `Library/DirectState.swift` after `:122`: `// MARK: Chart Lab (DMNC-1500)` + `var showChartLab: Bool { get set }`
- [ ] `App/AppState.swift`: init after `:145` → `self.showChartLab = defaults.showChartLab`; property after `:300` → `var showChartLab: Bool { didSet { defaults.showChartLab = showChartLab } }`
- [ ] `Library/Extensions/UserDefaults.swift`: key after `:82` → `case showChartLab = "libre-direct.settings.show-chart-lab"`; accessor after `:1108` = copy of `:1100-1108`, default `false`.
- [ ] `Library/DirectAction.swift` after `:204`: `// MARK: Chart Lab (DMNC-1500)` + `case setShowChartLab(enabled: Bool)`
- [ ] `Library/DirectReducer.swift` after `:508`:
  ```swift
  // MARK: Chart Lab (DMNC-1500)
  case .setShowChartLab(enabled: let enabled):
      state.showChartLab = enabled
      // Turning the lab off must not strand a persisted lab selection —
      // the row would hide the tab the chart is still rendering.
      if !enabled, state.selectedReportType.isLab {
          state.selectedReportType = .glucose
      }
  ```
- [ ] Tests `@Suite("Chart Lab reducer")`: fresh state → `showChartLab == false`; `setShowChartLab(true)` flips; `false` while `selectedReportType == .labMeals` resets to `.glucose`; `false` while `.timeInRange` leaves it; `true` never changes `selectedReportType`.

### Task 2 — `ReportType` lab cases + visibility

- [ ] `Library/Content/ReportType.swift`:
  ```swift
  enum ReportType: String, CaseIterable {
      // Raw values are UserDefaults persistence keys — keep them stable.
      case glucose
      case timeInRange
      case statistics
      // Chart Lab (DMNC-1500) — experimental, hidden unless `showChartLab`.
      case labMeals
      case labNight
      case labSweep
      case labPatterns

      var label: String {
          switch self {
          case .glucose: return "GLUCOSE"
          case .timeInRange: return "TIME IN RANGE"
          case .statistics: return "STATISTICS"
          case .labMeals: return "LAB: MEALS"
          case .labNight: return "LAB: NIGHT"
          case .labSweep: return "LAB: SWEEP"
          case .labPatterns: return "LAB: PATTERNS"
          }
      }

      /// Experimental surface, gated by `showChartLab`.
      var isLab: Bool {
          switch self {
          case .labMeals, .labNight, .labSweep, .labPatterns: return true
          case .glucose, .timeInRange, .statistics: return false
          }
      }

      /// True when the zoom row is the 7d / 30d / 90d / ALL day window.
      var usesDayWindow: Bool {
          switch self {
          case .timeInRange, .statistics, .labSweep, .labPatterns: return true
          case .glucose, .labMeals, .labNight: return false
          }
      }

      /// Row order, lab cases filtered out when the lab is off.
      static func visible(labEnabled: Bool) -> [ReportType] {
          allCases.filter { labEnabled || !$0.isLab }
      }
  }
  ```
  Exhaustive switches on purpose: the compiler then finds every site.
- [ ] Tests `@Suite("Chart Lab report types")`: `visible(labEnabled: false) == [.glucose, .timeInRange, .statistics]`; `visible(true)` starts with those three and ends with the four lab cases in order; `ReportType(rawValue:)` round-trips all four lab raw values; `isLab` / `usesDayWindow` per case; labels.

### Task 3 — Row iterates `visible`, scrolls when the lab is on; zoom-row arms

`App/Views/Overview/ChartToolbar.swift`

- [ ] `ChartReportTypeRow.body` (`:45-59`): move the `HStack` (`:46-54`) into `private var tabs: some View`, iterating `ReportType.visible(labEnabled: store.state.showChartLab)`, each `ChartTabButton` given `.id(type)`. Body:
  ```swift
  Group {
      if store.state.showChartLab {
          ScrollViewReader { proxy in
              ScrollView(.horizontal, showsIndicators: false) {
                  tabs.padding(.horizontal, DOSSpacing.sm)
              }
              .scrollBounceBehavior(.basedOnSize)
              .onAppear { proxy.scrollTo(store.state.selectedReportType, anchor: .center) }
              .onChange(of: store.state.selectedReportType) { withAnimation(AnimationTokens.snappy) { proxy.scrollTo(store.state.selectedReportType, anchor: .center) } }
          }
      } else {
          tabs   // shipping layout, unchanged
      }
  }
  .padding(.vertical, DOSSpacing.xs)
  .background(AmberTheme.dosBlack)
  .onAppear(perform: normaliseDaysIfNeeded)
  .onChange(of: store.state.selectedReportType) { normaliseDaysIfNeeded() }
  ```
- [ ] `normaliseDaysIfNeeded()` (`:64-69`): `guard store.state.selectedReportType.usesDayWindow else { return }`.
- [ ] `ChartZoomRow` (`:83-88`): `case .glucose, .labMeals, .labNight: hoursRow` · `case .timeInRange, .statistics, .labSweep, .labPatterns: daysRow`. Keep the switch exhaustive.
- [ ] Preview (`:165-176`) still compiles.

### Task 4 — `ChartLabOverlay` seam (new file; arms filled by P1/P2/P4/P5)

`App/Views/Overview/Lab/ChartLabOverlay.swift`

```swift
/// One additive mark-set a lab tab switches on inside `LabChartView`. P0 declares
/// the full set so the parallel PRs each fill exactly one arm of
/// `LabOverlayMarks.marks(for:)` and never fight over this enum.
enum ChartLabOverlay: Hashable, CaseIterable {
    case carbSizedMeals        // P2
    case mealResponseRibbons   // P2
    case residualMarks         // P2
    case regimeBands           // P2
    case nightContext          // P1 (sleep stages, HR, cross-midnight ribbon)
    case ghostBand             // P4
    case factPins              // P5
}

extension ReportType {
    /// Mark-sets a lab tab layers onto the lab chart. Empty for shipping tabs.
    var labOverlays: Set<ChartLabOverlay> {
        switch self {
        case .labMeals: return [.carbSizedMeals, .mealResponseRibbons, .residualMarks, .regimeBands, .factPins]
        case .labNight: return [.nightContext, .mealResponseRibbons]
        case .labPatterns: return [.ghostBand]
        case .labSweep, .glucose, .timeInRange, .statistics: return []
        }
    }
}
```
`App/Views/Overview/Lab/LabOverlayMarks.swift`: `enum LabOverlayMarks { @ChartContentBuilder static func marks(for overlay: ChartLabOverlay, series: LabChartSeries, yMax: Double) -> some ChartContent { switch overlay { case …: EmptyChartContent() } } }` — every arm empty in P0 with a `// P2 fills this arm` comment (`EmptyChartContent` exists in Charts; verify at compile, else return an empty `ForEach([Int]())`).
- [ ] Tests: `labOverlays` empty for the three shipping cases and `.labSweep`; `.labMeals` contains `.carbSizedMeals`; every `ChartLabOverlay` case has an arm (compiles exhaustively).

### Task 5 — `LabChartSeries` + builder (new file)

`App/Views/Overview/Lab/LabChartSeries.swift`

```swift
/// Main-actor snapshot of everything the lab chart draws from. Equatable so
/// one `.onChange(of:)` replaces the shipping chart's nine.
struct LabChartInputs: Equatable {
    let sensorGlucose: [SensorGlucose]
    let bloodGlucose: [BloodGlucose]
    let meals: [MealEntry]
    let insulin: [InsulinDelivery]
    let iobDeliveries: [InsulinDelivery]
    let exercise: [ExerciseEntry]
    let heartRate: [HeartRateSample]          // struct HeartRateSample: Equatable { let time: Date; let bpm: Double } built from state.heartRateSeries tuples
    let glucoseUnit: GlucoseUnit
    let alarmLow: Int
    let alarmHigh: Int
    let bolusPreset: InsulinPreset
    let basalDIAMinutes: Int
    let showSmoothed: Bool                    // DirectConfig.showSmoothedGlucose && state.showSmoothedGlucose
    let smoothThreshold: Date
    let selectedDate: Date?
    let overlays: Set<ChartLabOverlay>
    init(state: DirectState, overlays: Set<ChartLabOverlay>)   // the ONLY place the lab reads store.state for series
    // plus a memberwise init for tests
}

struct IOBSample: Equatable { let date: Date; let total: Double; let mealSnack: Double; let corrBasal: Double }

struct LabChartSeries {
    var domainStart: Date
    var domainEnd: Date
    var glucoseSegments: [GlucoseSegment]
    var glucoseByMinute: [Date: GlucoseDatapoint]   // minute-rounded keys, first wins (ChartView.swift:829-833)
    var bloodGlucose: [GlucoseDatapoint]
    var insulin: [InsulinDatapoint]
    var iob: [IOBSample]
    var meals: [MealDatapoint]
    var exercise: [ExerciseDatapoint]
    var heartRate: [HeartRateSample]
    var isEmpty: Bool { glucoseSegments.isEmpty && bloodGlucose.isEmpty }
    static let empty: LabChartSeries
    /// ±tolerance minute probe, same shape as ChartView.nearestHeartRate (:1011-1024).
    func nearestGlucose(at date: Date, toleranceMinutes: Int = 5) -> GlucoseDatapoint?
    /// Aggregate for the A/B readout — every number carries its n.
    func summary(over range: ClosedRange<Date>) -> LabRangeSummary   // { min, max, first, last, delta, readings n, carbs g, insulin U, hrFirst, hrLast }
}

enum LabChartSeriesBuilder {
    /// Pure; safe off the main actor with a snapshot.
    static func build(_ inputs: LabChartInputs, now: Date = Date()) -> LabChartSeries
}
```
Builder rules: domain = earliest / latest of sensor ∪ blood timestamps, `+15 min` on the end only when `selectedDate == nil` (`:725-755`); glucose via `toSmoothDatapoint` when `showSmoothed && timestamp < smoothThreshold` else `toDatapoint` (`:1046-1054`), then `segmentGlucoseSeries`; `glucoseByMinute` keyed by `time.toRounded(on: 1, .minute)`; insulin via `toDatapoint(minDate:maxDate:)`; IOB sampled every 60 s over the domain when `iobDeliveries` is non-empty (copy `:895-916`); meals / exercise via `toDatapoint()`.
- [ ] Tests `@Suite("Lab chart series builder")`: empty inputs → `.isEmpty`; `domainEnd` = latest + 15 min when `selectedDate == nil`, = latest when set; `glucoseByMinute` keys minute-aligned; `nearestGlucose` finds a reading 3 min away, not 7; IOB sample count == domain minutes + 1 with one delivery, empty with none; `summary(over:)` on a fixture: `n` equals the readings inside the range, `carbs` sums meals inside, `insulin` sums boluses inside, `delta = last − first`.

### Task 6 — `LabChartView` (new file, the platform) — parity marks + instrument cursors

`App/Views/Overview/Lab/LabChartView.swift`

```swift
struct LabChartView: View {
    @EnvironmentObject var store: DirectStore
    let overlays: Set<ChartLabOverlay>

    @State private var series: LabChartSeries = .empty
    @State private var liveSelection: Date? = nil                 // chartXSelection(value:) — resets to nil on release
    @State private var stickyCursor: Date? = nil                  // persists after release
    @State private var liveRange: ClosedRange<Date>? = nil        // chartXSelection(range:)
    @State private var stickyRange: ClosedRange<Date>? = nil
    @State private var scrollPosition: Date = Date()
    @State private var isFollowing = true
    @State private var unseenReadings = 0
    @State private var lastDetentKey: String? = nil
    private let calculationQueue = DispatchQueue(label: "dosbts.lab-chart-calculation", qos: .utility)

    private enum Config {
        static let maxHeight: CGFloat = 310      // shipping 250 + the 60 pt lane budget this chart doesn't need
        static let minHeight: CGFloat = 140
        static let readoutHeight: CGFloat = 64   // PINNED — never jumps between states
        static let selectionSymbolSize: CGFloat = 100
        static let labelEvery: [Int: Int] = [3: 1, 6: 2, 12: 3, 24: 4]   // mirrors ChartView.Config.zoomLevels (:614-619)
    }
}
```

- [ ] **Layout:** `VStack(spacing: 0)` → `LabDayPager` (private copy of `ChartView.swift:35-77`; dispatches `.setSelectedDate`; same glyphs/fonts; haptic as `:765-770`) → unit label row (copy `:97-99`) → `GeometryReader { geo in chart.frame(height: max(Config.minHeight, min(Config.maxHeight, geo.size.height - Config.readoutHeight))) }` → `LabReadoutStrip` (fixed `Config.readoutHeight`). **No marker lane.** Hour chips come from `ChartZoomRow` (`OverviewView.swift:34`); read `store.state.chartZoomLevel` for the visible window.
- [ ] **Inputs → series:** `private var inputs: LabChartInputs { LabChartInputs(state: store.state, overlays: overlays) }`; `.onAppear { rebuild() }` + `.onChange(of: inputs) { rebuild() }`; `rebuild()` guards `store.state.appState == .active` (`:737-739`), snapshots on the main actor, then `calculationQueue.async { let built = LabChartSeriesBuilder.build(snapshot); DispatchQueue.main.async { … } }` — mirror `:880-923`. On the main-actor assign: `series = built`; if `isFollowing` → `scrollPosition = built.domainEnd`; else `unseenReadings += max(0, built.readingCount - series.readingCount)`.
- [ ] **Chart modifiers** (this order; `yMax` = 300 mg/dL / 18 mmol/L per `:701-707`; `visibleHours` from `chartZoomLevel`, default 3):
  ```swift
  .chartXScale(domain: series.domainStart...series.domainEnd)
  .chartYScale(domain: 0...yMax)
  .chartScrollableAxes(.horizontal)
  .chartXVisibleDomain(length: TimeInterval(visibleHours * 3600))
  .chartScrollPosition(x: $scrollPosition)
  .chartScrollTargetBehavior(.valueAligned(matching: DateComponents(minute: 0)))
  .chartXSelection(value: $liveSelection)
  .chartXSelection(range: $liveRange)
  .chartXAxis { /* copy :417-424 */ } .chartYAxis { /* copy :425-436 */ } .chartLegend(.hidden)
  ```
  `.onChange(of: liveSelection) { if let t = liveSelection { stickyCursor = t; stickyRange = nil } }` and `.onChange(of: liveRange) { if let r = liveRange { stickyRange = r } }` — the sticky copies are what render; the live bindings resetting to nil on release is expected. Tapping the plot outside any mark clears both (a `.chartOverlay` `TapGesture` that only fires when no drag occurred). **Zoom chips** keep working: on `chartZoomLevel` change, set `chartXVisibleDomain` AND co-set `scrollPosition` (to the end when following, else keep the current left edge) — otherwise the view re-anchors. When `series.isEmpty`, render `FiguresLoadingView.inline` in place of the chart (StyleGuard rule 6).
  **If the built-in range gesture proves unusable on a scrollable chart** (it is long-press-then-drag and it competes with scroll), replace it with `.chartGesture { proxy in LongPressGesture(minimumDuration: 0.3).sequenced(before: DragGesture(minimumDistance: 0)).onChanged { … proxy.selectXRange(from: a, to: b) } }` and say so in `IMPLEMENTATION_NOTES.md`. Either way: scroll = plain drag; scrub = long-press then drag; A/B = long-press, release, long-press elsewhere (second press sets B while A is sticky). Document the final arbitration in the notes.
- [ ] **Marks, in z-order** (one `// MARK:` per block; parity blocks are copies of the cited shipping ranges with `store.state.x` swapped for `series` / `inputs` fields; `alarmLow`/`alarmHigh` in display units via a private copy of `:757-763`): 1 in-range band (`:176-180`) · 2 `ForEach(overlays.sorted…) { LabOverlayMarks.marks(for:) }` **under-layer** (ribbons/bands; P1/P2/P4 decide their own z) · 3 limit rules (`:182-188`) · 4 glucose trace (`:190-201`) · 5 blood-glucose points (`:250-257`) · 6 basal bars (`:259-276`) · 7 IOB area (`:278-322`, keep both `series:` labels; `showSplitIOB` from the store) · 8 exercise strip (`:324-332`) · 9 heart rate (`:334-361`, gated by `store.state.showHeartRateOverlay`) · 10 **cursors**: if `stickyRange` → `RectangleMark(xStart:xEnd:yStart: 0, yEnd: yMax)` in `AmberTheme.surfaceTint`, two `RuleMark(x:)` in `amberLight` 1 pt dash `[3,3]`, endpoint `PointMark`s at the nearest readings (`symbolSize` 100, `amberLight`, `.opacity(0.75)` per `:390-398`), `A HH:mm` / `B HH:mm` `.annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled))` in `DOSTypography.microLabel`; else if `stickyCursor` → one rule + one point. · 11 **FOLLOW nub**: `.chartOverlay` top-trailing `Button` (44 pt target, visual 16 pt) `◂ N NEW` in `.dosCard(.toast, padding: DOSSpacing.xxs)` shown only when `!isFollowing && unseenReadings > 0`; tap → `scrollPosition = series.domainEnd; isFollowing = true; unseenReadings = 0`. `.onChange(of: scrollPosition)`: `isFollowing = scrollPosition >= series.domainEnd.addingTimeInterval(-TimeInterval(visibleHours * 3600) - 60)`.
- [ ] **`LabReadoutStrip`** (private, same file): `.dosCard(.toast, padding: DOSSpacing.xs)`, height `Config.readoutHeight`, `DOSTypography.label` + `.monospacedDigit()`, three states with **identical height**: (a) no cursor → `TOUCH & HOLD TO MEASURE · DRAG TO SCROLL` in `textFaint`; (b) single cursor → `HH:mm · G 142 · IOB 1.4U · MEAL 60g (−12 MIN) · HR 82`; (c) range → line 1 `A 12:04 → B 13:44` … `Δt 1h40` (trailing, amber), line 2 `G 169→201 (+32) · MIN 152 · MAX 206 · IN 5.0U · CARBS 60g · n=20` (values from `series.summary(over:)`; `n` in `amberDark`). Unit-formatted via `Int.asGlucose(glucoseUnit:)`; mmol/L users see mmol/L.
- [ ] **Detents:** `.onChange(of: stickyCursor)`: compute `detentKey` = nearest event id within ±2 min (meal / bolus / exercise start) or `"low"` / `"high"` when the reading crosses the active alarm bounds; if it differs from `lastDetentKey` → `DirectNotifications.shared.hapticFeedback(.light)` for events, `.medium` for bounds; suppress entirely while the night profile is active (`store.state.activeAlarmProfile == .night` — verify the accessor name in `Library/Content/AlarmProfile.swift`), mirroring the celebration toast's night gate.
- [ ] **Accessibility:** `.accessibilityLabel("Lab chart")`; the readout strip `.accessibilityElement(children: .combine)`; the nub `.accessibilityLabel("Scroll to now, \(unseenReadings) new readings")`.
- [ ] In `IMPLEMENTATION_NOTES.md`: the exact Charts modifier signatures that compiled; the gesture arbitration you shipped; the measured rebuild time for a 24 h window (temporary `Date()` delta log, removed afterwards).

### Task 7 — Lab tab views + the four `ChartView` arms

- [ ] `App/Views/Overview/Lab/LabMealsView.swift`: `VStack(spacing: 0) { LabChartView(overlays: ReportType.labMeals.labOverlays); LabLegendRow(items: [...]); LabFooter() }` — legend for P0: `A→B MEASURES` (amberLight) · `● FOLLOW` (amber); P2 appends its items. `LabFooter` = `Text("LAB · EXPERIMENTAL · NOT DOSE ADVICE").font(DOSTypography.micro).foregroundStyle(AmberTheme.textFaint)`. `LabLegendRow` / `LabLegendItem` in `App/Views/Overview/Lab/LabChrome.swift` (`HStack(spacing: DOSSpacing.sm)` of `DOSTypography.microLabel` glyph + label pairs, `.padding(.vertical, DOSSpacing.xxs)`).
- [ ] `App/Views/Overview/Lab/LabPlaceholderView.swift`: `LabPlaceholderView(tab: ReportType)` → `.dosCard(.info)` with `Text("\(tab.label) — COMING")` in `DOSTypography.bodySmall` cyan and a one-line caption naming the surface (NIGHT: "the night made whole, 20:00 → 10:00"; SWEEP: "every meal aligned at t=0"; PATTERNS: "your own 30-day band under today"), plus `LabFooter()`.
- [ ] `ChartView.swift:20-27`: add `case .labMeals: LabMealsView()` · `case .labNight: LabPlaceholderView(tab: .labNight)` · `case .labSweep: LabPlaceholderView(tab: .labSweep)` · `case .labPatterns: LabPlaceholderView(tab: .labPatterns)`. **Nothing else in the file.**

### Task 8 — Settings toggle

- [ ] `App/Views/Settings/GlucoseDisplayCategoryView.swift`, in `DisplaySettingsSection` after the marker-lane `VStack` (`:81-93`):
  ```swift
  VStack(alignment: .leading, spacing: DOSSpacing.xxs) {
      Toggle("Chart Lab", isOn: showChartLab).toggleStyle(SwitchToggleStyle(tint: AmberTheme.amber))
      Text("Experimental chart views appear as LAB tabs beside GLUCOSE on the Overview. Off by default. Nothing in the lab is dosing advice.")
          .font(DOSTypography.caption)
          .foregroundStyle(AmberTheme.amber)
  }
  .padding(.vertical, 4)
  ```
  Binding after `:127` (copy `:122-127`), dispatching `.setShowChartLab(enabled:)`.

### Task 9 — CHANGELOG, suites, build

- [ ] `CHANGELOG.md` `[Unreleased]` → `### Added`: `- Settings → Glucose & Display → "Chart Lab" toggle (off by default): shows experimental LAB tabs beside GLUCOSE — a natively scrolling chart you can scrub, measure between two points, and scroll back through without new readings pulling the view away — DMNC-1500`
- [ ] Suites green: `ChartLabTests` (all suites), `DirectReducerTests`, `StyleGuardTests`, `MarkerConsolidationTests`, `EventMarkerTypeTests`. Then the full suite (log to a file, grep the result line). Known-flaky under load: `AppGroupMiddlewareDispatchTests/startupSeedsKeys()` — re-run before blaming the branch.
- [ ] Both targets build (`DOSBTSApp`, `DOSBTSWidget`).

## Verification

```bash
LOG="$TMPDIR/p0-tests.log"
xcodebuild test -project DOSBTS.xcodeproj -scheme DOSBTSApp \
  -destination 'id=9A948885-80C7-4A96-A9FB-D2742595AD3B' > "$LOG" 2>&1
grep -E "\*\* TEST (SUCCEEDED|FAILED) \*\*" "$LOG"           # never pipe xcodebuild into tail
git diff --stat main -- App/Views/Overview/ChartView.swift    # ≤ 6 lines
```

**On-simulator (iPhone 17 Pro, iOS 26.5; virtual sensor connection so the chart has data; log a 60 g meal + 5 U bolus about 90 min ago and a 30-min run):**
1. Lab off (fresh install): Overview row reads `GLUCOSE · TIME IN RANGE · STATISTICS`, centred, identical to `main` (screenshot both). GLUCOSE chart, lane, zoom chips, drag tooltip, double-tap raw trace unchanged.
2. Settings → Glucose & Display → **Chart Lab** on. Row becomes scrollable; the four LAB tabs follow STATISTICS; selecting one centres it.
3. `LAB: MEALS`: no marker lane; the chart flicks natively and settles on an hour boundary; 3h/6h/12h/24h chips change the visible window without a reload and without jumping; the newest reading is in view on first render; the readout strip reads `TOUCH & HOLD TO MEASURE · DRAG TO SCROLL`.
4. Touch-and-hold then drag → a cursor follows with a light tick as it crosses the meal and bolus marks; lift the finger → the cursor **stays**; the strip shows `HH:mm · G … · IOB … · MEAL 60g (…) · HR …`.
5. Long-press, release, long-press elsewhere → an A/B band with `A HH:mm` / `B HH:mm`, and the strip shows `Δt`, `G a→b (Δ)`, `MIN/MAX`, `IN 5.0U`, `CARBS 60g`, `n=…`. Tap empty plot → cleared, strip back to state (a); the strip never changes height.
6. Scroll back an hour, then add a virtual reading → the view does **not** move; `◂ 1 NEW` appears top-right; tap it → scrolls to now, nub gone.
7. Parity: in-range band, limits, basal bars, IOB area (split and single via Settings → Insulin), exercise strip and HR line (Settings → Integrations → Apple Health) render as on GLUCOSE; axis ticks identical.
8. Switch unit to mmol/L → axis, band and readout in mmol/L.
9. `LAB: NIGHT` / `SWEEP` / `PATTERNS` show their placeholder cards with the footer; day chips show for SWEEP/PATTERNS, hour chips for NIGHT/MEALS.
10. Lab off while on a lab tab → snaps to GLUCOSE, row back to three; kill + relaunch → still GLUCOSE. Lab on, select `LAB: MEALS`, kill + relaunch → restored.
11. Night profile active (set night window to now in Settings → Alarms): scrubbing produces no haptics.

## Out of scope

Any change to the shipping GLUCOSE / TIME IN RANGE / STATISTICS behaviour or the marker lane (DMNC-1483); every overlay arm (P1/P2/P4/P5 fill them); the multi-day reads (P3/P4); HealthKit sleep (P1); pinch-to-zoom (chips stay); the prediction line and raw-trace toggle on the lab chart; COB; AI; build bump or TestFlight (the controller does that after the train).

## Sibling / merge notes

P0 lands **first, alone**. P1–P5 branch from `main` after it merges and fill their arms in `LabOverlayMarks.swift`, add their views, and replace their placeholders in `ChartView.swift`'s switch; keep every switch exhaustive. Fold `IMPLEMENTATION_NOTES.md` into the PR body and `git rm` it before merge.
