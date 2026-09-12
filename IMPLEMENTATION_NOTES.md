# Chart Lab P4 — implementation notes (DMNC-1503)

Worker notes for the orchestrator. Newest entry on top. Folded into the PR body and
`git rm`'d before merge, per the plan.

---

## The drill gesture: P0's scrub IS "hold an hour" (plan decision, taken)

The plan's Task 4 offered three options and asked me to say which. **Chosen: neither a new
long-press nor a chip — the drill listens to P0's existing scrub cursor.**

P0's vocabulary is: plain drag = scroll, press ~0.5 s then drag = scrub, second press > 12 pt
away = A→B, quick tap = clear. A `LongPressGesture` for the drill would be the *same* gesture
as the scrub on the *same* plot, and a two-finger long-press is not something SwiftUI exposes
(`LongPressGesture` has no touch count; only magnify/rotate are multi-touch).

So `LabChartView` gained one optional closure, `onCursorChange: ((Date?) -> Void)? = nil`,
fired alongside the existing detent hook. `LabPatternsView` mirrors it into `@State` and drills
into `Calendar.component(.hour, from:)` of that cursor. The prototype's copy
(`HOLD AN HOUR → SAME HOUR · 14 D`) is then literally true: you hold the chart, the cursor
lands on an hour, the card follows it. Nothing new competes for the touch, and the A→B
measurement still works (the drill follows `cursors.cursor`, which is the A end of a range).

The `×` sets `dismissedDrill = cursorDate` rather than clearing the chart's cursor: closing a
card should not destroy a measurement the user placed. Moving the cursor re-arms the drill.

## Deviations from the plan

1. **`LabChartView` is touched (3 small additions), not only the four files the plan listed.**
   The plan's "sibling / merge notes" said I touch `LabOverlayMarks` (one arm),
   `LabChartSeries` (one field), `ChartView` (one line), `ClinicReport` (additive), state files,
   both `App.swift` arrays and new files. Three things could not be done from outside the chart:
   - `unitRowLabel: String? = nil` — the `▒ YOUR 30-DAY BAND` chip lives on the unit row
     (artboard 5), and `unitRow` is private to `LabChartView`. Rendering it above the chart
     would have put it above the day pager.
   - `onCursorChange` — see the gesture note above.
   - `yMax` now also feeds `series.patternBand?.maxValue` into `LabChartMath.yMax`. This is the
     P0 errata's explicit instruction ("any overlay that adds y values must feed the same floor
     computation; do not add a second `.chartYScale`"). Without it a p95 above today's maximum
     would have been clipped at the top of the plot.
   Both new parameters have defaults, so `LabMealsView` (and every sibling's call site) compiles
   unchanged. Merge cost for P1/P2/P3/P5: three small hunks in one shared file.

2. **`OutOfBandHour` carries `hourStart: Date`** (the plan's struct had only `hour`). The lab
   chart's domain is the rolling 24 h window, which spans two calendar days — an hour-of-day
   alone cannot say *where* to draw the tick. `hourStart` is the actual hour occurrence in the
   plotted window, so a window covering 11:00 twice flags the right one.

3. **`SameHourDrill.traces` is `[SameHourTrace]`, not `[[SensorGlucose]]`.** The mini chart
   needs each reading's offset from the hour's centre and each day's "is this today"; deriving
   both in the view would have re-implemented the slicing that the test pins. `SameHourTrace`
   carries `day`, `isToday` and `[SameHourPoint(offsetMinutes:value:)]`, so the view plots and
   decides nothing.

4. **`OutOfBandMarker` carries its rendered `cardText`.** The plan had the chart arm formatting
   `HH:00 · +38 VS USUAL · n=27`, but `LabOverlayMarks.marks(for:series:yMax:)` is P0's shared
   signature (every sibling arm goes through it) and has no `GlucoseUnit`. Widening it would
   have forced a change on every sibling branch. The builder knows the unit, so the copy is
   built there — which also puts it under test.

5. **`LabChartInputs.patternBand` is a `PatternBandInput` (24 hourly rows + the look-back), not
   `[HourlyPattern]`.** Same one field, but it carries the `days` label the band needs and,
   critically, it is NOT `LabPatternEvidence`: the evidence holds up to 90 days of readings, and
   `LabChartInputs` is `Equatable` and compared on every render. The readings stay in Redux
   state and are read only by the drill.

6. **The view does not dispatch on `.onChange(of: statisticsDays)`.** The plan asked for both
   that *and* a `.setStatisticsDays` arm in the middleware — which would fire two identical
   reads per chip tap. The middleware arm is the one that shipped (it is gated on
   `selectedReportType == .labPatterns`, so the shared TIR/STATISTICS chips do not trigger it
   from other tabs). The view dispatches `.onAppear` only.

7. **The drill is recomputed on a cheap `drillIdentity` string, not inside `body`.**
   `PatternAnalysis.drill` sorts and filters up to 90 days of readings; doing that per render
   would have been a visible cost. `.onChange(of: drillIdentity)` (hour | reading count |
   period end) recomputes only when the inputs actually move.

8. **`patternHourSpan` is the LAST occurrence of the hour inside the domain.** On a rolling
   window that covers the same hour twice the dashed box belongs on today's, not yesterday's.
   Pinned by a test with a domain that spans midnight.

9. **Band edge points are emitted once per SPAN, not once per day.** The plan said "plus `00:00`
   and `24:00` edge points from hours 0 and 23". Emitting them per day would put two points at
   each interior midnight (hour 23's values and hour 0's values at the same x), which an
   `AreaMark` renders as a vertical discontinuity. Interior midnights are already continuous
   through the `hour:30` points, so only the span's outer edges get one.

## Plan claims that were correct

- Every anchor resolved: `ClinicReport.swift`'s `HourlyPattern` / `hourlyPatterns` /
  `percentile`, `ClinicReportStore.getClinicReportData(days:)` (one `asyncRead`, no writes),
  the `ratioEvidence` 3-file transient template, `RatioLabMiddleware`'s `.catch` → fallback →
  `.setFailureType` shape, both `App.swift` arrays, `DaysZoom.allDays == 9999`, and the
  `ChartLabTests.swift` pbxproj rows at 71/168/342/568.
- `HourlyPattern` had **no** direct constructor call outside `ClinicReport.swift` (only
  `ClinicReportPage.rangeText(_:)` reads it), so the compatibility initializer was cheap
  insurance rather than a necessity — it is kept and pinned anyway, because the next person to
  add a field will not re-check.
- P0's errata were all load-bearing: `Optional: ChartContent` makes the `if let band` arm legal,
  the annotation `overflowResolution` must be `y: .fit(to: .chart)`, and `Int.asGlucose` is
  correct here precisely because these are RAW mg/dL values (the double-conversion trap only
  applies to values a datapoint builder already converted).

## Known nits (not fixed, deliberately)

- The out-of-band card is a chart `annotation`, so two flagged hours close together can overlap.
  The prototype shows one card; in practice a day rarely leaves the band in two adjacent hours.
  Consolidation (the marker lane's `consolidateByOverlap` shape) is the fix if it ever bites.
- `PatternAnalysis` leaves the `// P-later: split by DayCohort` seam comment the plan asked for.
