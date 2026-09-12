# Chart Lab P2 — implementation notes (DMNC-1501)

Worker notes for the orchestrator. Newest entry on top. Folded into the PR body and
`git rm`'d before merge, per the plan.

---

## Deviations from the plan

### 1. The residual `?` is NOT tappable inside the chart — the affordance moved to a sibling row

**Plan said:** "`.residualMarks`: … a `?` glyph `PointMark`-annotation at the midpoint … Tap: …
`sheets.present(.journalNote)` after setting a prefill", with a 44-pt target around the `?`.

**What I found:** a `Button` inside a `.annotation` on a **scrollable** `Chart` never receives the
tap. Verified on the simulator twice — once on the 44-pt `?` disc, once on the caption card (both
were `Button`s with `.contentShape(Rectangle())` and a ≥44-pt frame). Neither fired; the chart's
scroll gesture, `chartXSelection` and P0's `simultaneousGesture` consume the touch before it
reaches the annotation's view. This is the same family as P0's `.chartOverlay` finding, one level
in: **P0 learned an overlay steals touches from the chart; P2 learned the chart steals touches
from an annotation.**

**What shipped:** the in-chart `?` is a pure MARK (`.allowsHitTesting(false)`), and the affordance
is `LabMealsView`'s `residualPrompt` row — a sibling **below** the chart, in the same place the
`STILL <TAG>?` row lives, reading `? UNEXPLAINED +40 · 13 RDG · TAP TO NOTE`. It claims only its
own frame, so it has no gesture to lose. Confirmed working on the simulator: tapping it opens the
note sheet with the time picker at the excursion's start.

Side benefit: the caption is no longer competing for the plot's top band, and it can no longer
say "TAP TO NOTE" about something that is not tappable.

**For the orchestrator:** this constrains P4 too — a "long-press a ghost band for a drill" style
interaction cannot live in an annotation either. Chips and rows outside the plot are the only
reliable tap surfaces on this chart.

### 2. Ribbon labels stagger round-robin, not by window overlap

**Plan said:** "stagger label rows when ribbons overlap (prototype's 12-pt row offsets)".

**What I found:** implemented as interval packing first (lowest row whose previous occupant has
ended). On the simulator at 24 h zoom all four labels still printed over each other — because what
collides is the **label**, not the window: a label is ~110 pt wide while a two-hour ribbon is
~30 pt at that zoom. Two meals four hours apart never "overlap" and still collide.

**What shipped:** `MealResponseDatapoint.labelLanes` assigns rows round-robin in time order,
cycling through 4 rows. Any four consecutive meals are on four different rows at every zoom, which
is also exactly what the prototype artboard draws (rows at y=19/31/43/55 for meals 2–4 h apart).
The marks function has no plot width to measure against, so a width-aware rule is not available.
Tests updated to pin the new rule.

### 3. A close marker arriving AFTER a band's default end must still close it

Caught on the simulator, and it would have shipped as a nagging bug. `RegimeDeriver` originally
only accepted a closer with `closer.timestamp < defaultEnd`. But `STILL <TAG>?` is shown *at* the
default end (minus 30 min), so the user's answer almost always lands **after** it — meaning every
`BACK TO NORMAL` the user ever writes was ignored and the row asked again forever. Observed
directly: tapping **N** wrote the note, and the row stayed.

Fixed to `end: min(defaultEnd, closer.timestamp), isOpen: false` — a closer never *extends* a band
(the default is the longest it can honestly claim) but always *closes* it. New regression test
`closerAfterDefaultEndStillCloses` pins both halves, including that the prompt goes away.

### 4. Ribbon / regime labels use `position: .top`, not `.overlay`

`.annotation(position: .overlay)` lays the content out inside the **mark's own width**, so a label
longer than its mark truncates (`+47 · 39 MI…`) or clips (`ESSED 14→18`) and `overflowResolution`
does not rescue it. Both moved to `position: .top` with `overflowResolution: .init(x: .fit(to:
.chart), y: .fit(to: .chart))` plus `.fixedSize()` — the shape P0 proved for its cursor labels —
and are pushed down into the plot with `.padding(.top,)`. The plot's top band is now explicitly
budgeted: ribbon labels take rows 0–3, the regime label sits below them. Without that the regime
label printed straight over `NO BOLUS`.

### 5. `ResponseSummary.isLowConfidence` is `0 < n < 4`, not `n < 4`

Plan's struct comment said `n < 4`. Taken literally, an **empty** window (n = 0) would be "low
confidence", which changes `computeMealOverlayDelta` — it returns `isLowConfidence: false` on the
empty-window path. No readings is not low confidence; it is no measurement at all, and `delta ==
nil` is what says so. `emptyWindowIsNotLowConfidence` and `emptyWindowParity` pin both readings.

### 6. `computeMealOverlayDelta`'s in-progress window now closes at +2 h even if the caller lies

The kernel's window is `min(anchor + lag, now)`. The wrapper passes `now = isInProgress ? Date() :
anchor + 2 h`, which is bit-identical to the old `windowEnd` for any honestly-computed
`isInProgress`. The single external caller (`RootSheetContent.swift:218`) computes it honestly
(`Date().timeIntervalSince(meal.timestamp) < 2 * 60 * 60`), so behaviour is unchanged — pinned by
`MealOverlayDeltaParityTests` over 20 seeded randomised fixtures plus the empty-window case. The
only divergence would be a caller passing `isInProgress: true` for a meal older than two hours, and
there the kernel is *more* correct (it closes the window) rather than less.

### 7. Bracket units are `5U` / `4.5U`, not `5.0U`

P0's errata says insulin uses the `GlucoseView.formatIOB` shape (`"%.1fU"`) rather than
`Double.asInsulin()`. `%.1f` renders the prototype's `60g ⟷ 5U` as `60g ⟷ 5.0U`. Shipped a
trailing-zero trim (`MealResponseDatapoint.formatUnits`) so whole units read `5U` and part units
`4.5U`. Still not `asInsulin()` — the locale-comma / 2-decimal problem the errata is about is
avoided.

### 8. Excluded ribbons are dim-tinted, not hatched

The plan already offered this fallback and it was needed. A ribbon is a tall, thin rect: a
`LinearGradient` "hatch" runs perpendicular to its own axis, so on a tall rect it renders as
horizontal bands, not 45° hatching; and a `Canvas` in an `.annotation(.overlay)` cannot be
stretched to a mark's frame (annotations size to their ideal size, not the mark). Shipped
`amberDark.opacity(0.10)` plus the teaching tag, which is the plan's stated fallback. The legend
keeps `▨` — it reads as "shaded band". The tag is what carries the meaning, which is the point
("TAG = WHY").

### 9. The bracket flip is Charts' own overflow resolution, not a `plotWidth − 70` rule

The plan quoted the prototype's `x > plotWidth − 70` rule for flipping the last meal's bracket.
`LabOverlayMarks.marks(for:series:yMax:)` has no plot width (and I must not change its signature —
the siblings share it). `overflowResolution: .fit(to: .chart)` pulls an overflowing annotation back
inside the plot, which is the same outcome; confirmed on the simulator that the 80 g bracket at the
domain edge stays clear of the axis.

### 10. `JournalNotePrefill` carries `timestamp` + `tag`, no `text`

The plan sketched `.init(timestamp: now, tag: .stressed, text: "")`. Nothing sets a non-empty
prefill text in V1, so the field would have been dead. Dropped; easy to add later.

### 11. Files the plan did not name

`ResidualSegment`/`ResidualDetector` → `App/Views/Overview/Lab/LabResidualDetector.swift`;
`RegimeBand`/`RegimeDeriver`/`RegimePrompt` → `App/Views/Overview/Lab/LabRegimeDeriver.swift`. The
plan named files for Tasks 1–2 only. Both are pure and store-free; only `ResponseWindow.swift` had
to be in `Library/` (kernel, both targets, no SwiftUI — verified: zero `import SwiftUI`).

---

## Plan claims that were correct

- Every anchor into shipping code resolved: `MealOverlayLogic.swift:31-67` / `:78-103`,
  `RootSheetContent.swift:217-218`, `RatioEstimator.swift:52` / `:80-112`,
  `SheetCoordinator.swift:22`/`:41`, `RootSheetContent.swift:59-64`,
  `AddJournalNoteView.swift:17`/`:110`, `JournalNote.swift:12-16`.
- P0's platform signatures were all as the plan described them, and `LabOverlayMarks` really does
  isolate the four P2 arms — `ChartView.swift` is **0 insertions** on this branch.
- Reusing the Ratio Lab's `MealExclusionReason` taxonomy was the right call: `pairedBolusUnits`,
  `minGlucoseInWindow`, `endGlucose` and the thresholds were all directly callable, so the chart's
  teaching tags and the evidence table's cannot drift.
- Enum cases DO take default parameter values in Swift, but I used the explicit
  `.journalNote(prefill: nil)` at the three call sites anyway — it is one token and it makes the
  new payload visible at every site.

---

## Fixture / harness notes (not app findings)

- **`InsulinType` persists as JSON.** It is a `Codable` enum with no raw value, so GRDB stores
  `{"mealBolus":{}}` in the TEXT column — not `mealBolus`. Seeding a fixture with the plain case
  name silently yields "no bolus" everywhere. Anyone hand-seeding `InsulinDelivery` rows needs the
  JSON form.
- **`glucoseUnit` lives in the App Group suite**, and neither `simctl spawn defaults write` (app
  domain or group domain) nor editing the group container's plist made the app pick it up. The unit
  had to be switched through Settings → Glucose & Display. Worth knowing before anyone scripts a
  unit-switch check.
- **Sibling workers share the Simulator app.** Five simulator windows were open and other agents'
  windows repeatedly stole focus mid-batch; a `Wispr Flow` floating window also blocks synthetic
  clicks over a band of the screen. Several steps needed the window re-fronted via the Window menu
  before the tap landed. P0's "hold the click ~0.2 s" finding held: instantaneous clicks do nothing.

---

## Known nits (deliberately not fixed)

- At 24 h zoom with four meals the plot's top band carries five stacked labels (four ribbon rows +
  the regime row), and the regime label overlaps the trace. Every label has an opaque backing so it
  stays legible, and the stack is deterministic. A denser day would look busy; the honest fix is a
  per-zoom label budget, which needs plot width the marks function does not have.
- The carb dots draw **under** the ribbons, because `ChartLabOverlay`'s declaration order puts
  `.carbSizedMeals` first and `drawOrder` derives from it. Reordering the enum would move
  P1/P4/P5's layers too, so I left it. At 0.05–0.12 fill opacity the dots read through cleanly
  (confirmed on the simulator).
