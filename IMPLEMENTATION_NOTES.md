# Chart Lab P0 — implementation notes (DMNC-1504)

Worker notes for the orchestrator. Newest entry on top. Folded into the PR body and
`git rm`'d before merge, per the plan.

---

## Charts API — the exact signatures that compiled

All verified against
`$(xcrun --sdk iphonesimulator --show-sdk-path)/System/Library/Frameworks/Charts.framework/Modules/Charts.swiftmodule/arm64-apple-ios-simulator.swiftinterface`
**before** writing the view, then confirmed by a clean first compile:

```swift
func chartXScale(domain: ClosedRange<Date>) -> some View
func chartYScale(domain: ClosedRange<Double>) -> some View
func chartScrollableAxes(_ axes: Axis.Set) -> some View
func chartXVisibleDomain<P>(length: P) -> some View where P: Plottable, P: Numeric   // TimeInterval on a Date axis
func chartScrollPosition(x: Binding<some Plottable>) -> some View                    // LEADING edge of the visible window
func chartScrollTargetBehavior(_ behavior: some ChartScrollTargetBehavior) -> some View
static func valueAligned(matching: DateComponents,
                         majorAlignment: MajorValueAlignment<Date>? = nil,
                         limitBehavior: ValueAlignedLimitBehavior = .automatic) -> ValueAlignedChartScrollTargetBehavior
func chartXSelection<P>(value: Binding<P?>) -> some View where P: Plottable
func chartXSelection<P>(range: Binding<ClosedRange<P>?>) -> some View where P: Plottable & Comparable
func chartGesture(_ gesture: @escaping (ChartProxy) -> some Gesture) -> some View    // available, NOT used — see below
ChartProxy.selectXValue(at: CGFloat) / .selectXRange(from: CGFloat, to: CGFloat)     // available, NOT used
func annotation<C>(position:alignment:spacing:overflowResolution: AnnotationOverflowResolution,
                   @ViewBuilder content: () -> C) -> some ChartContent
func chartPlotStyle(content: (ChartPlotContent) -> some View) -> some View
extension Optional: ChartContent where Wrapped: ChartContent                        // makes a bare `if let` arm legal
```

**`EmptyChartContent` does not exist** (grep of the whole swiftinterface: no hit). The plan
offered the fallback and it was needed: `LabOverlayMarks.noMarks` is an empty
`ForEach([Int](), id: \.self) { _ in RuleMark(...) }`. `ChartContentBuilder.buildBlock()`
(zero args) does exist, so a literally empty builder arm would probably also compile — the
empty `ForEach` was chosen because it is unambiguous and needs no `case` with an empty body.

## The gesture arbitration that shipped

Final behaviour on the lab chart:

| gesture | result |
|---|---|
| plain drag | native scroll, hour-snapped on release |
| press ~0.5 s then drag | scrub cursor follows the finger |
| release | cursor **stays** (the sticky copy renders; the live binding resetting to nil is expected) |
| second press elsewhere (> 5 min away) | the standing cursor becomes **A**, the new one **B**; dragging in that session moves B |
| third press | back to a single cursor (the cycle repeats) |
| quick tap (< 0.35 s, < 10 pt movement) | clears both |

Both `chartXSelection(value:)` and `chartXSelection(range:)` are attached. The **value**
binding is what fires in practice on a scrollable chart; the range binding is wired
(`handleLiveRange`) so that if the platform ever hands us a range gesture it lands in the
same sticky state. The A→B promotion does **not** depend on it — it is built from two
successive sticky cursors, which is exactly the interaction the plan's verification step 5
describes ("long-press, release, long-press elsewhere").

`.chartGesture` was **not** needed. The built-in selection gesture worked as soon as it was
allowed to reach the plot — see the deviation below.

**DEVIATION (plan said): tap-to-clear as "a `.chartOverlay` `TapGesture`".**
**What happened:** a `Rectangle().fill(.clear).contentShape(Rectangle()).onTapGesture { }`
inside `.chartOverlay` is hit-testable across the whole plot and **swallowed every touch** —
neither the scroll nor the selection gesture fired at all (verified on the simulator: a
press-drag did nothing, and a plain drag did not scroll).
**What shipped:** the overlay is gone. The FOLLOW nub moved to `.overlay(alignment: .topTrailing)`
on the chart's frame (it only claims the 44 pt it actually occupies), and clear-on-tap is a
`.simultaneousGesture(DragGesture(minimumDistance: 0))` that measures the press: a press
shorter than `Config.tapMaxDuration` (0.35 s) with < 10 pt of movement clears. Simultaneous
gestures do not starve the scroll or the selection, and the duration test means the
press-and-hold that STARTS a scrub is never mistaken for a clear (a plain `TapGesture` would
have been, since SwiftUI taps have no maximum duration).

## Measured rebuild time

`LabChartSeriesBuilder.build` over the full 24-hour fixture (324 readings, 1453 IOB samples,
5 event rows): **2–3 ms**, 9 builds in one session, every sample 2 ms or 3 ms. Measured with a
temporary `DirectLog.info` in `rebuild()`, read out of the app's own
`Documents/Logs/AllLogs.log`, and removed afterwards. Only 9 rebuilds across ~15 minutes of
interaction confirms the `Equatable` `LabChartInputs` gate is doing its job — the shipping
chart's nine `.onChange` handlers are replaced by one.

## Deviations from the plan

1. **`chartHeight(available:)` does not subtract `readoutHeight`.** The plan said
   `max(minHeight, min(maxHeight, geo.size.height - Config.readoutHeight))`. The readout strip
   is a *sibling* of the `GeometryReader` with a pinned frame, so the geometry already excludes
   it — subtracting again would have shrunk the chart by 64 pt for nothing. Shipped
   `max(minHeight, min(maxHeight, available))`.

2. **`scrollPosition` is set to the leading edge, not `domainEnd`.** The plan said
   `scrollPosition = built.domainEnd`. `chartScrollPosition(x:)` binds the **leading** edge of
   the visible window, so `domainEnd` only works by relying on Charts clamping it. Shipped
   `max(domainStart, domainEnd - visibleDuration)`, which is exact, and the follow predicate
   reads against the same edge.

3. **`yMax` is a floor, not a fixed domain.** The plan said `.chartYScale(domain: 0...yMax)`
   with `yMax` = 300 mg/dL / 18 mmol/L. A fixed 300 ceiling would **clip** any reading above it
   (`SensorGlucose.glucoseValue` clamps at 501, not 300). Shipped
   `max(chartMinimum, plotted.max().rounded(.up))` — the shipping chart's invisible
   `RuleMark(y: chartMinimum)` behaves the same way (a floor that the data can push past), so
   this is parity, not a new rule. The explicit scale requirement is still met.

4. **Cursor-label `overflowResolution` is `y: .fit(to: .chart)`, not `y: .disabled`.** With
   `.disabled` the `A HH:mm` / `B HH:mm` labels were drawn above the plot and clipped away
   (verified on-simulator: no label visible). The first fix attempt —
   `chartPlotStyle { $0.padding(.top, 18) }` — pushed the x-axis labels out of the bottom of the
   fixed-height chart instead. `.fit(to: .chart)` puts the labels just inside the plot's top
   edge, which is also where the prototype artboard draws them (`<text y="18">` inside a plot
   that starts at `y=8`).

5. **IOB / insulin units use `String(format: "%.1fU")`, not `Double.asInsulin()`.**
   `asInsulin()` is a 2-decimal, locale-aware formatter — it rendered `IOB 4,83U` in the readout
   while the hero two inches above said `IOB 2.8U`. The readout now uses the same helper shape
   as `GlucoseView.formatIOB` (`GlucoseView.swift:240-242`) so the two surfaces can never
   disagree.

6. **Glucose values in the readout are formatted, never converted.** The plan said
   "unit-formatted via `Int.asGlucose(glucoseUnit:)`". The datapoint builders already convert to
   the display unit, so `asGlucose` would have converted a second time. The strip runs the
   already-converted `Double` through the same `GlucoseFormatters.mgdLFormatter` /
   `.mmolLFormatter` that `asGlucose` uses internally. Verified on-simulator in both units.

7. **`LabChartSeries` carries a flat `glucose: [GlucoseDatapoint]`** in addition to the
   segments and the minute lookup the plan listed. `segmentGlucoseSeries` deliberately
   duplicates boundary points, so counting readings from the segments would have inflated the
   readout's `n` — and `n` is the one number the lab is not allowed to get wrong.
   `readingCount` derives from it (the plan's `rebuild()` already assumed such a property).

8. **`LabChartInputs.smoothThreshold` is floored to the minute.** `state.smoothThreshold` is
   `Date() - n`, i.e. a different value on every read, which would have made the `Equatable`
   inputs unequal on every render and rebuilt the series continuously. Flooring bounds the
   churn to once a minute.

9. **`ChartView.swift`'s four arms are one line each** (`case .labMeals: LabMealsView()`)
   rather than the file's usual two-line style, to keep the diff inside the plan's "≤ 6 lines"
   budget. `git diff --stat main -- App/Views/Overview/ChartView.swift` = 4 insertions.

10. **`LabMealsView`'s legend shows a static `● FOLLOW`**, not the prototype's
    `● FOLLOW OFF · 3 NEW`. The legend is a sibling of `LabChartView`, so it has no access to
    the chart's local follow state, and hoisting that state out of the view for a legend label
    was not worth it in P0 — the `◂ N NEW` nub already carries the detached-FOLLOW signal where
    the user is looking. P1+ can promote it if it proves useful.

11. **`plotSideInset` (10 pt) was added** via `chartPlotStyle`, which the plan did not mention,
    to give the edge hour labels room. It helps but does not fully solve it — see "known nits".

## Plan claims that were correct

- Every `file:line` anchor in the plan resolved on this branch (`ChartView.swift:20-27`,
  `:725-755`, `:895-916`, `ChartToolbar.swift:45-59`/`:83-88`, `DirectState.swift:121-122`,
  `AppState.swift:145`/`:300`, `UserDefaults.swift:82`/`:1100-1108`, `DirectAction.swift:204`,
  `DirectReducer.swift:506-508`, `DirectReducerTests.swift:15-22`/`:28-34`, and the four
  `DictationDisplayModelTests` pbxproj rows at 70/166/339/564). One imprecision:
  `GlucoseDisplayCategoryView.swift:71-79` is the "Keep screen awake" toggle+caption, not an HR
  toggle — the shape the plan wanted was there, just at `:73-78`.
- The "chart models are not Sendable" call was right, and the `calculationQueue` snapshot
  pattern compiled without a single concurrency warning (the target is Swift 5 language mode).
- "The `value`/`range` bindings reset to nil on release" — confirmed; the sticky mirror is
  load-bearing.
- "Changing `chartXVisibleDomain` re-anchors scroll unless `chartScrollPosition` is co-set" —
  the zoom chips need `reanchorAfterZoom()`; without it the view jumps.

## Known nits (not fixed, deliberately)

- **Edge hour labels can clip.** When the snapped leading edge lands exactly on an hour tick,
  that tick's label is centred on the plot boundary and loses about half its glyphs (`10` reads
  as `0`). Middle labels are always correct. The shipping chart avoids this by living inside a
  wider-than-screen `ScrollView`; a real fix means anchoring the first/last label differently,
  which changes every label's position. Left for P1+ to decide.
- **Settings list, sticky header overlap.** While the Glucose & Display list is over-scrolled,
  the pinned `DISPLAY` header draws over the "Chart event markers" row. Pre-existing, visible
  on `main`, unrelated to this branch.

## Not verifiable on the simulator

- **Detent haptics (verification step 11).** The simulator produces no haptics at all, so
  neither the ticks nor their night-profile suppression can be confirmed by feel. The code path
  is `fireDetentIfNeeded()` → `store.state.activeAlarmProfile != .night` →
  `DirectNotifications.shared.hapticFeedback(.light/.medium)`, mirroring the celebration
  toast's night gate. **Needs a human on a device.**
- **Split-IOB two-colour stack** was confirmed (a fresh 3 U basal made the `iobBasal` layer
  appear under the `iobBolus` layer), but only after logging basal by hand — worth one more
  look on real data.

## Harness note (not an app finding)

Synthetic instantaneous clicks (mouse-down and mouse-up in the same event) do **not** activate
a SwiftUI `Toggle` in a `List`; a ~0.2 s press does. Two apparently-failed "turn the lab off"
attempts were this, not the app. Anyone re-running this script by automation should hold the
button.
