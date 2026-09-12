# Chart Lab P5 — implementation notes (DMNC-1505)

Worker notes for the orchestrator. Newest entry on top. Folded into the PR body and
`git rm`'d before merge, per the plan.

---

## Deviations from the plan

### 1. `ChartHighlights` lives in `App/Views/Overview/Lab/`, not `Library/Content/`

**Plan said:** "new `Library/Content/ChartHighlights.swift`, pure".

**What I found:** the plan's own detector list requires `computeMealOverlayDelta` and
`detectMealConfounders`, which live in `App/Views/Overview/MealOverlayLogic.swift` — an
App-only file that `import`s SwiftUI. `Library` cannot see App symbols, so the engine
could not both live in `Library` and call the two functions the plan tells it to call.
The IOB and heart-rate sample types (`IOBSample`, `HeartRateSample`) are likewise
declared in P0's App-level `LabChartSeries.swift`.

**What I did:** put the engine under `App/Views/Overview/Lab/`, following
`TightControlStreakDetector` — the precedent the plan itself cites: an App-only, pure,
`Date()`-free detector reached from tests via `@testable import DOSBTSApp`. `LabFigure`
still ships in `Library/Content/` as planned (it has no App dependencies). Nothing about
purity or testability is lost; the only thing given up is availability to the widget
target, which has no use for it.

### 2. `ChartFact.title` is `[LabFactItem]`, not `String`

**Plan said:** `let title: String   // "BLACK BOX · HYPO 02:30 · 50 MIN"`.

**What I found:** the artboard's own title copy contains glucose numbers — `LUNCH 60g →
+54`. A `String` title is baked at build time in mg/dL, so a **mmol/L user would have
been shown a mg/dL number in the card's most prominent line**. The plan's unit rule
("every card line renders through `LabCaption`") stops at the title, which is exactly
where the biggest number is.

**What I did:** titles are items like lines, rendered by `LabCaption`, so every number in
a card converts to the display unit. Pinned by `ChartHighlightsTests.hypoTitle` /
`mealResponse`.

### 3. `LabFigure` carries `label` and `citesSampleSize`; `LabFactItem` adds `.observation`

**Plan said:** `LabFigure { kind, value, unit, n, spread, window }`, and "every card line
renders through `LabCaption`".

**What I found:** the artboard's lines are not all numbers — `TAG SICK`, `EXERCISE T-9h
30m RUN`, `HR 71→96`, `CLEAN` — and the numbers carry prefixes (`T-0`, `IOB`, `LAST BOLUS
T-4h10`). With the planned shape those would have had to be hand-interpolated strings,
which is the hole the rule exists to close.

**What I did:**
- `label` (printed before the number) and `citesSampleSize` (whether the text ends
  `· n=N`) on `LabFigure`. The `n`-required initializer is untouched — still the only
  one, still no default.
- `LabFactItem` is `.figure(LabFigure)` or `.observation(label:value:n:)`. **Numbers can
  only enter through `.figure`**; an observation restates a record verbatim and carries
  the number of records it restates, so "no record" (`n == 0`) renders `—` rather than
  vanishing. Kinds `.count`/`.sampleCount` print at `n == 0` because a count of zero is
  itself a fact (`0 HYPO`), which the plan's flat "n=0 → —" rule would have suppressed.

### 4. The Black Box IOB is computed from the chart's deliveries, not `series.iob`

**Plan/errata said:** "P0's `LabChartSeries.iob` already samples it per minute; read the
nearest sample."

**What I found on the simulator:** the Black Box read `IOB 0.0U` for a hypo eight hours
back that genuinely had 0.4 U on board. `series.iob` is built from `state.iobDeliveries`,
and `getIOBDeliveries` is a `datetime('now', '-DIA minutes')` query — what is on board
NOW. It is structurally zero at any instant older than the DIA, and in a 24-hour window
most hypos are. The samples cover the domain in TIME but not in DATA.

**What I did:** IOB at an onset is computed with `computeIOB(...at:)` from the chart's own
24-hour delivery set — and only when the full DIA before the onset is inside the window,
so an earlier dose cannot be silently missing. When it isn't, no sample is emitted and the
card prints `IOB —`. Verified on the simulator: 7 U rapid-acting at T-4h10 now reads
`IOB 0.4U`, which matches the Maksimovic curve computed by hand (5.85 % of 7 U). A user
with a 24-hour basal DIA will see `IOB —` for most onsets — deliberate: the lab would
rather say nothing than an understatement.

### 5. The dosing-language scan reads string literals, and their STATIC text

**Plan said:** read `App/Views/Overview/Lab/*Facts*.swift` and fail on the banned tokens,
"case-insensitive, whole-line comments skipped".

**What I found:** a whole-line scan fails on code, not copy — `let dose = boluses[index]`,
`LabInsulinDose`, and P0's own sanctioned footer `NOT DOSE ADVICE` all trip `\bdose\b`.
Scoping to `*Facts*.swift` would also have missed `ChartHighlights.swift`, where every
card title and line is actually built.

**What I did:** the rule scans **every** `.swift` under `App/Views/Overview/Lab/` plus
`Library/Content/LabFigure.swift`, matches only inside string literals, and judges a
literal's *static* text — `"stack-\(dose.id)"` is an identity string, not copy. The safety
footer is exempted by exact text. A companion test
(`rule_scanDetectsRealCopy`) proves the scan still catches `"Take \(units)U now"` and
`"You should correct with 2U"`, so the narrowing cannot have gutted it. A second guard,
`rule_everyFigureShipsWithN`, parses every `LabFigure(` argument list in the lab and fails
if it has no `n:`.

### 6. Meal facts are emitted for every completed meal; `≥ 60` is a severity threshold

**Plan said:** "meal response `≥ 60` delta".

**What I found:** the artboard's own meal card is `+54` — below the threshold that would
have excluded it.

**What I did:** a meal fact is emitted for every meal whose two-hour window has closed and
whose delta is computable; `|delta| ≥ 60` raises its severity from 1 to 2. The five-fact
cap keeps a busy day from turning into a feed.

### 7. `LabChartView` gained two defaulted inputs rather than exposing its state

**Brief said:** "P0's `LabChartView` now exposes a scroll position and sticky cursor state
you use for 'tap a card → jump' — read how before designing the hook."

**What I found:** it does not. `scrollPosition` and `cursors` are both `@State private`;
the only thing P0 hoists is `followStatus`.

**What I did:** followed P0's own pattern instead. `LabChartView` takes
`factsBinding: Binding<LabFactsSnapshot>?` (the chart pushes the computed facts up, so
the pins and the cards can never be built from two different computations) and
`focusRequest: LabFocusRequest?` (a tapped card asks the chart to centre an anchor and
place a cursor). **Both are optional with defaults**, so P1–P4's `LabChartView(overlays:
followStatus:)` call sites compile unchanged. `LabCursorState.place(at:)` is the one
additive method in a P0 file.

### 8. Cosmetic: the meal title reads `LUNCH 60g · +54 · PEAK 50 MIN`

The artboard has `LUNCH 60g → +54 · PEAK 50 MIN`. Items join with the DOS separator, so
the arrow would have rendered as `· → +54`. Dropped the arrow; the delta's sign already
says which way it went.

### 9. Facts are computed only for a tab that asked for `.factPins`

Not in the plan either way. `LabChartSeriesBuilder` runs the detectors only when the
overlay set contains `.factPins`, so P1's NIGHT tab does not pay for cards it does not
draw.

### 10. The facts region is capped at 120 pt and scrolls

With five cards and the chart at its 140 pt floor the tab overflowed and the mandatory
`LAB · EXPERIMENTAL · NOT DOSE ADVICE` footer was clipped off the bottom (observed on the
simulator at 190 pt). The sheet line + cards now live in a height-capped `ScrollView`.

---

## Plan claims that were correct

- `ClinicReport.swift:145-171` — `hypoEpisodes(from:)` tracks `episodeStart`/`previousLow`
  and discards them exactly as described; the refactor to `hypoEpisodeIntervals` is
  behaviour-preserving and `ClinicReportTests` stayed green untouched.
- `ClinicReportBuilder.percentile` (type-7) is the right tool for MEDIAN/P95.
- P0's errata were all load-bearing and all true: `noMarks` (not `EmptyChartContent`), the
  y domain as a floor, `overflowResolution` needing `y: .fit(to: .chart)`, formatting
  rather than re-converting units, counting from `series.glucose` rather than the
  segments, and "never hit-test the plot" (the pins are marks; the cards are ordinary
  views under the chart and claim only their own frames).
- `RatioEstimator.correctionStackLookbackMinutes` (180) was the right existing constant
  for the stacked-bolus window — no new threshold invented.
- `.accessibilityChartDescriptor(_:)` exists on iOS 26 and `AXChartDescriptor` is genuinely
  new to this repo (first use).

---

## On-simulator verification (iPhone 17, iOS 26.4, `id=ACB4E809-…`)

Fixture seeded directly into the app's GRDB file: 24 h of 5-minute readings, a 50-minute
hypo at 62 mg/dL eight hours back, a 7 U meal bolus 4 h 10 min before that onset, a
30-minute RUN nine hours before it, a SICK journal note an hour before it, and a 60 g
LUNCH five hours back that peaks +54 at 50 minutes.

| # | Step | Result |
|---|---|---|
| 1 | Sheet line, numbered pins in severity order, red dashed onset rule | **PASS** — `24H · n=287 · MEDIAN 136 · P95 151 · 1 HYPO · 1 MEALS · 1 CLEAN · 1 NOTES`; pins ① (hypo) and ② (meal) with amber stems down to the curve, ① carrying a full-height red dashed rule. Pins sit clear of the exercise strip. |
| 2 | Card 1 is the Black Box | **PASS** — `BLACK BOX · HYPO 13:39 · 50 MIN` / `T-0 62 · IOB 0.4U · COB —` / `LAST BOLUS T-4h10 7.0U · EXERCISE T-9h 30m RUN` / `HR — · TAG SICK`. `IOB 0.4U` matches the Maksimovic curve by hand; `HR —` is correct (no HealthKit data on the simulator). |
| 3 | A 60 g meal that peaks +54 → a meal card with PEAK and n | **PASS** — `LUNCH 60g · +54 · PEAK 50 MIN` / `1 OF 1 SIMILAR MEALS · CLEAN · n=25 RDG`. |
| 4 | Tap a card → chart moves, cursor lands on the anchor, readout agrees | **PASS** — tapping the Black Box put the sticky cursor on 13:39 and the readout strip read `13:39  G 62`, the same number the card states as `T-0 62`. |
| 5 | VoiceOver announces the sheet summary | **NEEDS A HUMAN** — the summary string is unit-tested (`LabChartAccessibilityTests`) and the descriptor is attached to the chart, but VoiceOver speech cannot be captured headlessly. |
| 6 | Reduce Motion → cards appear without the cascade | **PARTIAL** — with `ReduceMotionEnabled` set on the device the cards render at full opacity (the guard path is not stranding them invisible). Whether the cascade is *absent* is a by-eye judgement over ~240 ms; **needs a human**. |
| 7 | Lab off → nothing renders; GLUCOSE tab unchanged | **PASS** — with the gate off the shipping chart is byte-for-byte the old one: marker lane chips (`30m`, `7U`, `6U`+`★60g`), no pins, no sheet line, no cards, no lab legend. |
| 7b | No network | **PASS (static)** — no `URLSession`/`URLRequest`/URL literal in any file this PR adds or touches; the engine is pure and offline by construction. No runtime capture was run. |

Screenshots: `$TMPDIR/p5-shots/` (01 cards, 03 after the IOB fix, 04 pins at 24 h, 05 the
tap-to-focus cursor, 06 lab off, 07 reduce motion).

### Harness notes (not app findings)

- Three sibling workers' simulators were open on the same Mac. A `Return` keypress meant
  for my device's notification alert landed in a **sibling's** simulator and typed a
  single `A` into an open journal-note field (their fixture, unsaved, Cancel available).
  Flagging it so it is not mistaken for a bug in their branch.
- A **Wispr Flow** overlay window covers part of the screen and silently intercepts clicks
  in that region; two verification clicks failed until the target was moved outside it.

---

## Not verified

- VoiceOver speech and the Reduce-Motion cascade (above) — both need a human.
- The `regimeOverlap` / `bandExit` fact kinds are declared (P2/P4 feed them later) but
  nothing emits them yet, so they are untested beyond the enum.
- `mealResponses` from P2 is not on `main`; meal facts are computed by calling
  `computeMealOverlayDelta` / `detectMealConfounders` directly, as the plan allows. When
  P2 lands, `ChartHighlights.mealFacts` is the single place to swap the source.
