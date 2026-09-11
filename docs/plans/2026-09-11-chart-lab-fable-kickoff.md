# Chart Lab — planning kickoff

**Date:** 2026-09-11
**Base tree:** `main` @ `18c9be1b` (Build 136)
**Tracking:** DMNC-1500 (umbrella), DMNC-1501 / 1502 / 1503 (waves 1-3)
**Companion:** `docs/plans/2026-09-11-chart-lab-exploration-dossier.md` — **read it first, and do not re-explore the chart layer.** Every seam, line number, invariant and pinning test you need is already in it.

---

## How to use this document

**Arrangement:** Fable is the controller, in a regular Claude Code session in iTerm2. It reads the dossier, writes the wave plans, dispatches and reviews the workers, and runs the merge train.

Start that session in `/Users/doke/extracode/DOSBTS` on `main`, then paste the **Brief** section below. Everything after the brief is reference the planner reads from the repo.

**Do not orchestrate from a weak model**, here or in any successor session. The orchestrator writes the plans, judges worker pushback, and runs the merge train. `docs/solutions/best-practices/plan-driven-parallel-worker-orchestration.md` records that in the 2026-08-09 run **four orchestrator plan claims were wrong**, and each would have shipped a real bug had the worker obeyed literally. That seat has to be able to re-verify its own claims.

---

## Brief

> Plan the **DOSBTS Chart Lab**: a set of experimental, gated visualization surfaces that sit beside the shipping Overview chart, selectable from the top row, where new ideas can be tried and compared one tap away from the real chart, then promoted or deleted.
>
> **Read `docs/plans/2026-09-11-chart-lab-exploration-dossier.md` before anything else.** It is a complete map of the chart layer at this commit. Navigate by its anchors. Do not re-explore.
>
> **Dom's three pain points, in his words:** he can't see meal size (a 10g snack and an 80g dinner look identical), there's no cause and effect (nothing connects a meal or a dose to the curve that followed), and there's no pattern view (one day at a time only, so a recurring dawn rise never surfaces). He also said: *"It's okay if it's experimental, and we'll narrow down to good ones later."*
>
> **Do not change the shipping Overview chart's behavior.** The lab is additive and gated.
>
> Tracking issues already exist: **DMNC-1500** (umbrella) with **DMNC-1501 / 1502 / 1503** for waves 1-3. Dom's verbatim framing is preserved on the umbrella.
>
> Produce **one standalone, worker-executable checkbox plan per wave** under `docs/plans/`, following `docs/solutions/best-practices/plan-driven-parallel-worker-orchestration.md`. Then dispatch, review, merge-train and integrate per that same document.

---

## Architecture — settled, do not re-derive

### The selector is the mounting point

`ChartReportTypeRow` (`App/Views/Overview/ChartToolbar.swift:47`) iterates `ReportType.allCases` and dispatches `.setSelectedReportType`. `ReportType` (`Library/Content/ReportType.swift`) is a 21-line string enum whose raw values are the UserDefaults keys and whose labels are deliberately decoupled. **Adding a case lights it up in the top row and persists the selection for free.**

So the lab is new `ReportType` cases behind a new persisted `showChartLab` flag.

Touch points:

- `Library/Content/ReportType.swift` — lab cases plus `static func visible(labEnabled:) -> [ReportType]`
- `ChartToolbar.swift:47` — iterate `visible(labEnabled:)` instead of `allCases`
- `ChartToolbar.swift:64-69` — `normaliseDaysIfNeeded()` currently guards on `!= .glucose`; **any multi-day lab case must be considered here** or its day chips show nothing selected
- `ChartToolbar.swift:83` — a `ChartZoomRow` arm per new case (exhaustive switch, the compiler finds them)
- `ChartView.swift:20` — a `body` switch arm per new case
- New views under `App/Views/Overview/Lab/`
- `showChartLab` via the 4-file UserDefaults pattern in `CLAUDE.md`, toggle in `GlucoseDisplayCategoryView`

**Known layout problem to solve in wave 1:** the row is a plain `HStack` already carrying `TIME IN RANGE`. Three or four more entries overflow at phone width. It needs to become horizontally scrollable when the lab is on.

### "Duplicate then enrich" is built as an overlay set, not a copy

`glucoseChart` is a 420-line `Chart { }` body (`ChartView.swift:171-590`). Copying it per experiment is a maintenance trap.

Give `ChartView` an **overlay-set property defaulting to empty**. The shipping `GLUCOSE` tab passes nothing and is unchanged in behavior; each lab tab passes a different set and the same body renders extra marks. That is the side-by-side Dom asked for, one tap apart, with no duplicated chart body and no regression risk.

Wave 3's pattern views are genuinely different charts and get their own files. They are not variants of the glucose chart.

---

## Waves

Independent by design: wave 1 adds marks to the existing chart body, wave 2 adds a pure calculator plus one overlay, wave 3 adds standalone views on a different read path. They share only `ReportType.swift`, `ChartToolbar.swift`, `CHANGELOG.md` and `project.pbxproj` — the exact conflict profile the merge train handles.

### Wave 1 — `LAB: MEALS` — meal size and cause/effect · DMNC-1501

**Tier: Sonnet.** Almost pure reuse of code that already exists and is already tested. The plan quality is what makes the cheap tier safe — anchor every claim.

- **Carb-sized meal marks.** `mealSeries` and `MealDatapoint(carbs:)` are computed every render (`ChartView.swift:631, 925-928`) and **rendered nowhere**. `Config.mealSymbolSize` (`:601`) and `Config.insulinSymbolSizeRange: 30...160` (`:602`) sit unused, left from an earlier value-sized implementation. Render `mealSeries` as `PointMark` with `symbolSize` scaled from `carbs`.
- **Meal response ribbons.** Shade the two-hour window after each meal, tinted by the glucose delta that followed. `computeMealOverlayDelta` (`MealOverlayLogic.swift:31`) and `mealImpactDeltaColor` (`:18`, green under 30 / amber 30–59 / red 60+ mg/dL) already compute both. Zero new math.
- **Marker-to-curve connectors.** A faint rule from each marker to the glucose value beneath it, and to the value two hours later.

**Hard constraint — carb sizing goes on the chart, never in the marker lane.** Chip widths are estimated by `EventMarker.estimatedChipWidth` (`:182-202`) and pinned to exact pixels by `ChipWidthEstimateTests` (`5U` is 42pt, a triple stack 99pt). Anything changing a chip's rendered footprint must update the estimator in lockstep or consolidation merges the wrong groups. The ≤3-row / 60pt lane budget is separately pinned by `MarkerChipRowTests`. **Lane redesign is DMNC-1483's territory and is blocked on Figma — keep wave 1 out of it entirely.**

### Wave 2 — `LAB: COB` — the second graph line · DMNC-1502

**Tier: Opus.** New physiological math, safety-adjacent.

There is **no carb absorption model anywhere in the codebase** — a search for carbs-on-board and absorption returns nothing. Mirror `Library/Content/IOBCalculator.swift` (173 lines, pure, no SwiftUI, unit-tested): a model type with `percentEffectRemaining(at:)`, a result struct, and a free `computeCOB(...)` function. It drops into the 60-second sampling loop that already feeds the IOB area (`ChartView.swift:895-922`).

Optional stretch: a single net-effect line, carbs converted to mg/dL against insulin, using the `confirmedICR` Ratio Lab already persists.

**Safety — non-negotiable.** Ratio Lab's discipline applies without exception: no imperative dosing language, no carbs-in/units-out field, every number ships with its sample size. A COB curve is a teaching aid, never a bolus calculator. See the Ratio Lab bullet in `CLAUDE.md` and `docs/plans/2026-07-03-ratio-lab-plan.md`.

**The absorption model itself is a genuine design decision** — linear, bilinear, or oref0-style dynamic. State the choice and its rationale in the plan rather than leaving it to the worker.

### Wave 3 — `LAB: PATTERNS` — multi-day surfaces · DMNC-1503

**Tier: Opus for the data seam, Sonnet for the views.**

- **AGP percentile curve.** `ClinicReportBuilder.hourlyPatterns(from:)` (`Library/Content/ClinicReport.swift:119`) already returns an always-24-entry array of **median, p25 and p75 per hour**, unit-tested, with no on-screen consumer. Adding the 5th and 95th percentiles is a small extension of an existing tested function.
- **Day-overlay spaghetti.** Last 7 or 14 days traced faintly, today bold, over a 24-hour axis.
- **DOS hourly heatmap.** 24 columns by N days, cells coloured by mean glucose. Block characters suit the CGA aesthetic and echo `[GRAPH.EXE]` (DMNC-1245) already in the backlog.

**Data window caveat:** the chart's stores load `selectedDate`'s day or the last 24 hours only. Pattern views must go through `ClinicReportStore.getClinicReportData(days:)` — one `asyncRead`, 14/30/90 days — not the chart's own state. **Never call `dbQueue.write` inside an `asyncRead` callback; it deadlocks.**

---

## Constraints every worker brief must inline

- **`StyleGuardTests` fails the suite on ten source-scan rules:** no `.font(.system(`, no system Dynamic Type, no `Color.black`, no `.foregroundColor`, no `cornerRadius`, no bare `ProgressView()`, no inline animation curves, no raw `Color(red:)` outside `AmberTheme`, section headers via `.dosHeader()`, marker colours via `EventMarkerType.color`.
- **No glow shadows inside a `Chart { }` body or a `ForEach` row** (`docs/design-system.md:127`, performance).
- **The chart has no explicit scale domains.** The y-domain is forced by an invisible `RuleMark` at `ChartView.swift:173`, the x-domain by another at `:411`. Any overlay carrying non-glucose units **must** be projected onto the glucose axis with `Double.map(from:to:)`, exactly as IOB (`:306, :316`), basal bars (`:264`) and heart rate (`:717-723`) already do — otherwise it silently rescales the whole chart. The alternative is an explicit `.chartYScale(domain:)`. There is no third option.
- **A new data source needs both** an `.onChange` arm (`ChartView.swift:439-547`) **and** a call in the `onAppear` block at `:535-547`, or it stays empty on first render.
- **`ConsolidatedMarkerGroup`'s `==` compares id and count only** (`EventMarker.swift:62-72`), so a visual driven by marker contents will not refresh when a value is edited in place.
- **Lane height is hard-coded twice** — `ChartView.Config.markerLaneHeight = 60` (`:620`) and `EventMarkerLaneView.laneHeight = 60` (`:18`). Changing one silently clips.
- **`consolidateByOverlap` runs in the lane's view body on every render** (`EventMarkerLaneView.swift:30-35`), unmemoised. Per-group work added there costs on every scroll frame.
- **New test files are not auto-synced.** Each needs a manual `DOSBTSTests` group and `PBXSourcesBuildPhase` entry, and **each plan must be handed a distinct pbxproj object-ID pair up front** — two workers both taking "the next free pair" yields duplicate ids that `plutil -lint` calls OK while Xcode silently drops a test file from the target. Always follow the lint with `xcodebuild -project DOSBTS.xcodeproj -list 2>&1 | grep -i "malformed\|multiple groups"` (must be empty).
- **Tests are UserDefaults-isolated.** Use `makeTestDefaults()`; never construct `AppState()` bare.
- **Redux 4-file lockstep** for `showChartLab` and any new state, per `CLAUDE.md`. The `redux-state-coherence-reviewer` agent exists for exactly this check.
- **Figma exception.** `docs/design-system.md:262` sends dense new screens through a Figma frame first, and that route is blocked on DMNC-1482. **Lab screens are the explicit exception:** experimental, prose-described, never shipping as-is. A working lab screen is the better design medium here, and it unblocks the DMNC-1483 conversation rather than waiting on it.

---

## Orchestration

Follow `docs/solutions/best-practices/plan-driven-parallel-worker-orchestration.md`. Condensed:

1. **Plan.** One standalone checkbox doc per wave, executable by a worker with **zero session context**. Verified findings with `file:line` anchors, exact interfaces, test-first steps, named test suites, a simulator verification script, and an explicit out-of-scope line. The plan-writing pass is where the orchestrator does all the reading.
2. **Dispatch.** One worker per plan, in parallel. Each needs: its own git worktree and branch off `main`; its own simulator **UDID** (device names repeat across three installed runtimes, so partition by UDID, never by `name=`); a model tiered to plan difficulty; the executor protocol inlined; and the sibling-conflict rule inlined — base only on `main`, **never** rebase onto or merge sibling work.
3. **Review.** One adversarial reviewer per PR, producing severity-ranked findings **and** explicit clean-confirmations. Route **all** findings back to the **same worker that wrote the PR** — its context is intact, so fixes are cheap and correct there. Empirically this pass catches interaction-timing and hit-geometry bugs that unit tests cannot see.
4. **Merge train.** Have each worker fold `IMPLEMENTATION_NOTES.md` into the PR body and `git rm` the file first. Then merge most-isolated-first. `CHANGELOG.md` `[Unreleased]` conflicts **every time** and is keep-both. If two branches share Swift files, build the combined branch before merging. Expect a transient "Base branch was modified" after each squash-merge; poll rather than hammer.
5. **Integrate.** Run the **full suite once on the merged `main`** — each branch was only ever tested in isolation. Then, and only then, consider a build bump.

### Known dispatch failure modes

- **A subagent inheriting the parent model can fail with `thinking.type.disabled`.** Retry with an explicit `model` override.
- **Agent definitions added mid-session are not dispatchable** — the registry loads at startup. Fall back to a generic agent with an explicit model override and the executor protocol inlined; behavior is equivalent. `sonnet-worker`, `opus-worker`, `swift-reviewer` and `redux-state-coherence-reviewer` are all registered in this repo already.
- **A worker may park "awaiting a build notification" that will never fire.** Nudge it to verify in the foreground and not stop until the PR exists.
- **Simulator partitioning isolates `xcodebuild test` but not UI automation** — Simulator.app hosts every booted device in one process, so synthetic input cannot be scoped to a UDID. Treat interactive verification as single-threaded or a human step.
- **Full-suite runs go flaky under parallel load.** `AppGroupMiddlewareDispatchTests/startupSeedsKeys()` is the known offender. Re-run before blaming a branch.
- **Piping a verification command throws away its exit code.** `xcodebuild test … | tail -25` reports `tail`'s status and discards the `** TEST SUCCEEDED/FAILED **` line. Redirect the whole log to a file and grep it.
- **Plan errors surface as worker deviations — verify the pushback, don't overrule it.** Four orchestrator claims were wrong in the 2026-08-09 run. Budget review time for reading deviation notes as findings about the plan.

---

## Scope boundaries

**In scope:** gated experimental report types, additive chart overlays, a pure COB calculator with tests, standalone pattern views on the clinic-report read path, a `showChartLab` setting.

**Out of scope:** any change to the shipping `GLUCOSE`, `TIME IN RANGE` or `STATISTICS` tabs' behavior; marker-lane redesign (DMNC-1483, blocked on Figma); any dosing recommendation; a build bump or TestFlight deploy; Figma work (DMNC-1482, blocked on Dom).

**Promotion is a separate, Dom-gated decision.** Nothing graduates from the lab to the shipping chart in this cycle. The point is to build the things, look at them on device, and decide afterwards.

## Changelog

Lab surfaces are gated off by default, so they are **not user-visible** and need no `[Unreleased]` entry until something is promoted. The `showChartLab` toggle itself is visible in Settings and does need one.
