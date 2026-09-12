# Chart Lab P4 — implementation notes (DMNC-1503)

Worker notes for the orchestrator. Newest entry on top. Folded into the PR body and
`git rm`'d before merge, per the plan.

---

## Two things the simulator caught that the tests could not

**1. Four out-of-band hours drew four overlapping cards.** A chart `annotation` is roughly six
hours wide at the 24 h zoom, and my 30-day fixture flagged 01:00, 02:00, 10:00 and 13:00 — the
cards covered the trace they were describing, and the artboard shows exactly one card.
`PatternBandBuilder` now marks each marker `showsCard`: biggest |delta| first, then anything at
least `cardSpacingHours` (6) from an already-carded hour, ties breaking on the earlier hour so
the same day never renders two different sets. Every departure keeps its axis tick and its dot,
and the drill still reaches any hour by holding it. Pinned by `cardSpacing` / `cardsWhenSpread`.

**2. With the 7d chip the drill promised more days than it had.** The card read
`HOLD AN HOUR → SAME HOUR · 14 D` while its own line honestly said `0 OF 7 DAYS` — the drill
reuses the band's `readings`, so a 7-day band can only ever reach seven days back.
`PatternCopy.drillWindowDays(lookbackDays:)` caps the drill at the loaded evidence and both the
hint and the held header name that number (30d and 90d still read `14 D`). Pinned by
`drillWindowDays`.

## The drill gesture: P0's scrub IS "hold an hour" (plan decision, taken)

The plan's Task 4 offered three options and asked me to say which. **Chosen: neither a new
long-press nor a chip — the drill listens to P0's existing scrub cursor.**

P0's vocabulary is: plain drag = scroll, press ~0.5 s then drag = scrub, second press > 12 pt
away = A→B, quick tap = clear. A `LongPressGesture` for the drill would be the *same* gesture as
the scrub on the *same* plot, and a two-finger long-press is not something SwiftUI exposes
(`LongPressGesture` has no touch count; only magnify/rotate are multi-touch).

So `LabChartView` gained one optional closure, `onCursorChange: ((Date?) -> Void)? = nil`, fired
alongside the existing detent hook. `LabPatternsView` mirrors it into `@State` and drills into
`Calendar.component(.hour, from:)` of that cursor. The prototype's copy
(`HOLD AN HOUR → SAME HOUR · 14 D`) is then literally true: you hold the chart, the cursor lands
on an hour, the card follows it. Nothing new competes for the touch, and the A→B measurement
still works (the drill follows `cursors.cursor`, which is the A end of a range).

The `×` sets `dismissedDrill = cursorDate` rather than clearing the chart's cursor: closing a
card should not destroy a measurement the user placed. Verified on-simulator — after `×` the
readout still read `13:03  G 196`. Moving the cursor re-arms the drill.

## Deviations from the plan

1. **`LabChartView` is touched (3 small additions), not only the files the plan listed.** The
   plan's sibling/merge note said I touch `LabOverlayMarks` (one arm), `LabChartSeries` (one
   field), `ChartView` (one line), `ClinicReport` (additive), state files, both `App.swift`
   arrays and new files. Three things could not be done from outside the chart:
   - `unitRowLabel: String? = nil` — the `▒ YOUR 30-DAY BAND` chip lives on the unit row
     (artboard 5), and `unitRow` is private to `LabChartView`. Rendering it above the chart would
     have put it above the day pager.
   - `onCursorChange` — see the gesture note above.
   - `yMax` now also feeds `series.patternBand?.maxValue` into `LabChartMath.yMax`. This is the
     P0 errata's explicit instruction ("any overlay that adds y values must feed the same floor
     computation; do not add a second `.chartYScale`"). Without it a p95 above today's maximum
     would be clipped at the top of the plot.
   Both new parameters have defaults, so `LabMealsView` (and every sibling's call site) compiles
   unchanged. Merge cost for P1/P2/P3/P5: three small hunks in one shared file.

2. **`OutOfBandHour` carries `hourStart: Date`** (the plan's struct had only `hour`). The lab
   chart's domain is the rolling 24 h window, which spans two calendar days — an hour-of-day
   alone cannot say *where* to draw the tick. `hourStart` is the actual hour occurrence in the
   plotted window, so a window covering 11:00 twice flags the right one.

3. **`SameHourDrill.traces` is `[SameHourTrace]`, not `[[SensorGlucose]]`.** The mini chart needs
   each reading's offset from the hour's centre and each day's "is this today"; deriving both in
   the view would have re-implemented the slicing the test pins. `SameHourTrace` carries `day`,
   `isToday` and `[SameHourPoint(offsetMinutes:value:)]`, so the view plots and decides nothing.

4. **`OutOfBandMarker` carries its rendered `cardText`.** The plan had the chart arm formatting
   `HH:00 · +38 VS USUAL · n=27`, but `LabOverlayMarks.marks(for:series:yMax:)` is P0's shared
   signature (every sibling arm goes through it) and has no `GlucoseUnit`. Widening it would have
   forced a change on every sibling branch. The builder knows the unit, so the copy is built
   there — which also puts it under test.

5. **`LabChartInputs.patternBand` is a `PatternBandInput` (24 hourly rows + the look-back), not
   `[HourlyPattern]`.** Same one field, but it carries the `days` label the band needs and,
   critically, it is NOT `LabPatternEvidence`: the evidence holds up to 90 days of readings, and
   `LabChartInputs` is `Equatable` and compared on every render. The readings stay in Redux state
   and are read only by the drill.

6. **The view does not dispatch on `.onChange(of: statisticsDays)`.** The plan asked for both
   that *and* a `.setStatisticsDays` arm in the middleware — which would fire two identical reads
   per chip tap. The middleware arm is the one that shipped (gated on
   `selectedReportType == .labPatterns`, so the shared TIR/STATISTICS chips do not trigger it
   from other tabs). The view dispatches `.onAppear` only. Verified: the chips reload the band
   and its label (`▒ YOUR 7-DAY BAND`, every `n=7`).

7. **The drill is recomputed on a cheap `drillIdentity` string, not inside `body`.**
   `PatternAnalysis.drill` sorts and filters up to 90 days of readings; doing that per render
   would have been a visible cost. `.onChange(of: drillIdentity)` (hour | reading count | period
   end) recomputes only when the inputs actually move.

8. **`patternHourSpan` is the LAST occurrence of the hour inside the domain.** On a rolling
   window that covers the same hour twice the dashed box belongs on today's, not yesterday's.
   Pinned by a test with a domain that spans midnight.

9. **Band edge points are emitted once per SPAN, not once per day.** The plan said "plus `00:00`
   and `24:00` edge points from hours 0 and 23". Emitting them per day would put two points at
   each interior midnight (hour 23's values and hour 0's at the same x), which an `AreaMark`
   renders as a vertical discontinuity. Interior midnights are already continuous through the
   `hour:30` points, so only the span's outer edges get one.

## Plan claims that were correct

- Every anchor resolved: `ClinicReport.swift`'s `HourlyPattern` / `hourlyPatterns` / `percentile`,
  `ClinicReportStore.getClinicReportData(days:)` (one `asyncRead`, no writes), the `ratioEvidence`
  3-file transient template, `RatioLabMiddleware`'s `.catch` → fallback → `.setFailureType` shape,
  both `App.swift` arrays, `DaysZoom.allDays == 9999`, and the `ChartLabTests.swift` pbxproj rows
  at 71/168/342/568.
- `HourlyPattern` had **no** direct constructor call outside `ClinicReport.swift` (only
  `ClinicReportPage.rangeText(_:)` reads it), so the compatibility initializer was cheap insurance
  rather than a necessity — kept and pinned anyway, because the next person to add a field will
  not re-check.
- P0's errata were all load-bearing: `Optional: ChartContent` makes the `if let band` arm legal,
  the annotation `overflowResolution` must be `y: .fit(to: .chart)`, and `Int.asGlucose` is
  correct here precisely because these are RAW mg/dL values (the double-conversion trap only
  applies to values a datapoint builder already converted).

## Findings for the orchestrator (not bugs in this branch)

- **`LAB: PATTERNS` cannot change its own plot window.** P0 gave the tab `usesDayWindow == true`,
  so its chip row is 7d/30d/90d/ALL (the band's look-back) and the *chart's* visible hours stay on
  whatever `chartZoomLevel` the GLUCOSE/MEALS tab last set. On a 3 h window you see a slice of the
  band and have to scroll to reach a flagged hour. Everything works; a 24 h default (or pinning
  this tab's visible domain to the day) would suit the surface better. Not changed here — it is
  P0's platform decision and would touch `LabChartView` further.
- **The chip names the requested window, not the evidence.** With 30 days of data and the 90d chip
  selected the chip reads `▒ YOUR 90-DAY BAND` while every number carries `n=30`. That is
  consistent with "every number ships with its n", but the orchestrator may prefer the chip to
  name the evidence instead.
- **The drill panel compresses the chart.** Opening the drill shrinks the plot toward P0's 140 pt
  floor (the `GeometryReader` yields the space). It snaps back on `×`. Acceptable, but a taller
  phone makes it look better than a small one.

## Known nits (not fixed, deliberately)

- A flagged hour's card can still overlap the trace directly under it (the anti-collision rule
  spaces cards from EACH OTHER, not from the line). The prototype has the same property.
- `PatternAnalysis` carries the `// P-later: split by DayCohort` seam comment the plan asked for.

## On-simulator verification (iPhone 17 Pro Max, iOS 26.4, `id=F4D018BE-…`)

Fixture: 30 days of 5-minute readings seeded into the app's GRDB file with a repeatable daily
shape (dawn rise, lunch and dinner bumps, a deliberately wide hour, per-day jitter) plus a
+85 mg/dL hour today so an hour genuinely leaves the band.

| # | Step | Result |
|---|---|---|
| 1 | Lab on → `LAB: PATTERNS` draws today's chart with the band behind it; unit row `▒ YOUR 30-DAY BAND`; day chips reload the band and the label | **PASS** — 7d reloads to `▒ YOUR 7-DAY BAND` with every figure at `n=7` |
| 2 | < 5 days of data: no flags, no `PATTERN HOUR`; held hour says `n<5 DAYS · KEEP WEARING` | **PASS** — DB trimmed to 3 days: band still drawn, no ticks/cards/box, card read `30-DAY BAND · n=830 READINGS`, and holding 07:00 gave `07:00 ±2 H · LAST 14 D` / `n<5 DAYS · KEEP WEARING` with the four traces still drawn |
| 3 | ≥ 5 days: dashed `PATTERN HOUR · n=…` on the widest hour; an out-of-band hour shows the tick and the `HH:00 · +Δ VS USUAL · n=…` card | **PASS** — `PATTERN HOUR · n=30` box on 10:00, `13:00 · +85 VS USUAL · n=30`, four ticks, two cards after the anti-collision fix |
| 4 | Hold an hour → 14 faint traces ±2 h with today's bright and `k OF N DAYS > 180 HERE · n=…`; `×` returns | **PASS** — `13:00 ±2 H · LAST 14 D` / `1 OF 14 DAYS > 180 HERE · n=686`, threshold rule drawn, today's trace bright; `×` restored the hint AND left the chart cursor intact |
| 5 | Settings → Glucose & Display → Clinic Report still generates a PDF | **PASS** — `dosbts-clinic-report`, PDF Document · 17 KB, share sheet presented |
| 6 | mmol/L: band, cards and drill line convert | **PASS** — `13:00 · +4,7 VS USUAL · n=30`, `01:00 · +0,4 VS USUAL · n=30`, `10:00 · 1 OF 14 DAYS > 10 HERE · n=686`, axis 3–18, band converted |
| 7 | GLUCOSE tab unchanged; lab off → nothing renders | **PASS** — row back to `GLUCOSE · TIME IN RANGE · STATISTICS`, selection snapped to GLUCOSE, shipping chart + hour chips, no band/cards/drill/legend |

Nothing in this branch needs a human to confirm by feel — there are no haptics, sounds or
timing-sensitive behaviours in P4. The only judgement calls a person may want to re-look at are
the three "findings for the orchestrator" above, which are about taste, not correctness.
