# Chart Lab P1 — implementation notes (DMNC-1506)

Worker notes for the orchestrator. Newest entry on top. Folded into the PR body and
`git rm`'d before merge, per the plan.

---

## Deviations from the plan

### 1. `LabChartView` does NOT draw heart rate from the `.nightContext` arm

**Plan said:** the `.nightContext` arm draws "the HR `LineMark` (copy `ChartView.swift:334-361`),
gated by nothing — NIGHT always shows HR when present."

**What I found:** `LabChartView` already draws heart rate, gated by
`store.state.showHeartRateOverlay`. Drawing it again from the overlay arm would put **two**
dashed magenta lines on the plot for any user who has the overlay toggle on — and the arm has
no access to `glucoseUnit`, so it could not reproduce `scaledHR()`'s mg/dL↔mmol/L axis mapping
without duplicating that too.

**What I did:** the gate moved onto the series — `LabChartSeries.showsHeartRate`, set from
`LabChartInputs.showHeartRate`, which the day path takes from the setting and the **window path
forces to `true`**. One line, one source of truth, and NIGHT still always shows HR when present.
`LabChartView.swift` changes by one condition; the arm draws everything else.

### 2. A sibling HealthKit service, not an export from `AppleHealthImport`

**Plan said:** "Expose both through whatever service object the middleware can reach (mirror how
`queryHeartRate` `:201` is invoked)."

**What I found:** `AppleHealthImportService` is a **`private class`** constructed inside
`appleHealthImportMiddleware`'s own `LazyService`. There is no instance any other middleware can
reach, and no shared/static accessor — so "expose it" would have meant de-privatising the class
*and* inventing a singleton for it, changing that module's lifecycle for a lab feature.

**What I did:** `App/Modules/ChartLab/LabHealthKitService.swift` — its own `HKHealthStore`
(supported and cheap), reached through its own `LazyService`, exactly mirroring the
AppleHealthImport pattern rather than reaching into it. `fetchHourlyHeartRate(in interval:)`
generalises the day-scoped query (a day anchor cannot answer a window that crosses midnight);
the shipping day version is untouched, so the GLUCOSE tab's HR overlay is byte-for-byte what it
was. Sleep **was** added to `AppleHealthImport.readPermissions` as the plan asked, so enabling
Apple Health import asks for it in the same prompt.

### 3. The awake gaps are a flat wash, not a 45° hatch

**Prototype has:** `<pattern id="sleepHatch" patternTransform="rotate(45)">` over the awake gaps.

**What I found:** Swift Charts has no pattern fill for a `RectangleMark` — `foregroundStyle`
takes a `ShapeStyle`, and an `ImagePaint`/`Canvas`-drawn hatch cannot be applied to a mark
without dropping to a `chartOverlay`, which P0's errata forbids for anything that hit-tests, and
which would also need its own x-scale mapping.

**What I did:** `cgaCyan.opacity(0.25)` rectangles over `cgaCyan.opacity(0.05)` band — exactly
the two values the plan names, and the gap still reads as "carved out of the sleep". The legend
still says `▒ AWAKE`.

### 4. NIGHT has no zoom chips (`ChartToolbar.swift`, one new switch arm)

**Plan said:** nothing about the zoom row; P0 gave NIGHT the hour chips (3h/6h/12h/24h).

**What I found:** `chartZoomLevel` defaults to **3**, so NIGHT would have opened showing a
three-hour sliver of a fourteen-hour window — not the artboard, and not a window you can read a
night off. The chips also have no meaning here: the night window is *fixed* at 20:00 → 10:00, so
there is nothing for them to choose.

**What I did:** `ChartZoomRow` gets a `case .labNight: EmptyView()` arm, and the window path
sets `chartXVisibleDomain` to the whole interval. The tab draws its own `NIGHT · DAY · WK` row in
that space, which is what the artboard shows there. Verification step 1 ("hour labels 8p … 10a")
only passes this way.

### 5. `LabChartMath.labelEvery` gained a fallback rule

P0's `zoomLabelEvery` maps only 3/6/12/24. A 14-hour window fell through to `1` — fourteen hour
labels at phone width. The fallback is now "about seven labels across the plot"
(`ceil(hours / 7)`), which reproduces every mapped value's intent and gives 14 h a 2-hour stride
(the artboard's `8p 10p 12a 2a 4a 6a 8a 10a`). **P0's pinned `labelEvery(7) == 1` still holds** —
`ChartLabTests` is green, unmodified.

### 6. `NSHealthShareUsageDescription` rewritten

**Plan said:** "extend its copy to mention sleep if it lists data types; otherwise leave it."

**What I found:** it does not list data types, so the plan's literal instruction was "leave it" —
but the copy reads *"Access to Apple Health is required if glucose data should be exported."*
That is the **export** story, and it is the string iOS shows on the **read** prompt this branch
now triggers for Sleep. A tester running verification step 2 would be asked for sleep data by a
dialog talking about exporting glucose.

**What I did:** changed the share key only (the identical `NSHealthUpdateUsageDescription` string
is left alone) to name what we actually read. Deliberate, small, and user-visible-correct.

### 7. `HeartRateSample` moved from the App target to `Library/`

P0 declared it in `App/Views/Overview/Lab/LabChartSeries.swift`. `LabWindowSnapshot` lives in
`Library/Content/` (pure, both targets), and it carries heart rate — so the type had to be
shared. Moved verbatim into `Library/Content/LabWindow.swift`, `Codable` added; every existing
reference compiles unchanged. **The widget now compiles it**, which is why `LabWindow.swift`,
`NightSummary.swift` and `LabFigure.swift` import nothing but `Foundation`.

### 8. `LabFigure` is created here AND by P5 — expected merge conflict

The plan's `NightSummary` is typed in terms of `LabFigure`, but `LabFigure` is **P5's** Task 2
(`Library/Content/LabFigure.swift`). P5 runs in parallel, so both branches create that file.

I wrote it to **P5's spec verbatim** (`Kind` with all nine cases, `value`/`unit`/`n`/`spread`/
`window`, and the single `n`-requiring initializer), so the merge should be a whole-file conflict
resolvable by keeping either copy. **Orchestrator: check this at merge time** — if P5's copy
differs, keep P5's and recompile `NightSummary.swift` against it.

### 9. The dinner ribbon is drawn by `.nightContext`, not `.mealResponseRibbons`

As the plan anticipated: P2 has not merged, so `.mealResponseRibbons` is still `noMarks`. The
ribbon (`+38 · 24 RDG`) is built in `LabChartSeriesBuilder.mealRibbons` from the **shipping**
`computeMealOverlayDelta`, so the lab and the meal-impact overlay can never disagree about a
delta, and drawn from the `.nightContext` arm. When P2 lands, its arm can take the ribbons over
and `LabChartSeries.mealRibbons` can move behind that overlay's flag — a mechanical reconcile.

### 10. The P0 readout strip stays between the chart and the sleep lane

The artboard has no instrument readout. `LabReadoutStrip` is part of `LabChartView` (P0's
platform), so NIGHT gets it, and the layout is header → chart → **readout** → sleep lane → POST
strip → NIGHT·DAY·WK → legend → footer. Kept deliberately: the cursors are the lab's instrument
and dropping them on one tab would be a worse inconsistency than one extra row.

### 11. My own test's IOB coverage contract was wrong, and the red run caught it

`grdbCoverageReachesWindow` originally asserted every GRDB stream's coverage **spans** the
requested window. It failed on `.iob` — correctly: IOB deliveries reach **back** a full DIA
before the window and are not expected to reach its end. The test now states the two contracts
separately (window-spanning streams span it; `.iob` starts before it) and asserts that every
`.grdb` case is classified by one of them, so a stream added later cannot be silently skipped.

### 12. Coverage percentage is clamped to 100%

`GLU 103%` (possible with a duplicated row) reads as a bug rather than as honesty. Clamped to
`0...100`, and pinned by `glucosePercentClamped`.

A second test of mine was also wrong and the suite caught it: `zeroInterval` asserted that a
nonsensical `sensorInterval` should read `100%`. It should not — `sensorInterval` defaults to
**1 minute**, so clamping to `max(1, …)` is the honest floor and 100 readings across a 14-hour
window of once-a-minute slots is `12%`. The test now pins that, for `0` and for a negative.

## Design notes the orchestrator may want to challenge

- **`.setSelectedDate` reload lives in the middleware**, per the plan, guarded on
  `state.selectedReportType == .labNight`. The view therefore loads only in `.onAppear`. The
  drawn domain is always `snapshot.interval` (never `selectedDate`), so paging keeps the previous
  night on screen until the new one lands instead of flashing an empty axis — the `ratioEvidence`
  loading model, applied to a window.
- **The lab never opens a new consent.** `requestAccessIfNeeded()` only runs when
  `state.appleHealthImport` is already on: the lab *completes* a grant the user gave, it does not
  introduce a HealthKit prompt from an experimental tab. With Apple Health off, the strip reads
  `HR n/a · SLEEP n/a`, underlined, and tapping deep-links to Settings → Integrations.
- **`n/a` is only ever "we have never asked."** `authorizationStatus(for:)` reports the *share*
  status; for a read-only type it is `.notDetermined` before the prompt and `.sharingDenied`
  after it whether the user granted the read or refused. HealthKit never reveals a read denial,
  so after the prompt an empty result is reported as `—`. This is documented in
  `LabHealthKitService`'s header, because the alternative — inferring denial — would be a lie.
