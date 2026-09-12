# Chart Lab P1 — `LAB: NIGHT` + the whole-system window loader — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven-development). Checkbox steps. Read the file at each anchor before editing; shipping-code anchors were verified on `main` @ `3a288d3d`; lab-platform anchors (`App/Views/Overview/Lab/*`) refer to the merged P0 PR — open those files first and re-verify every signature. Record every deviation in `IMPLEMENTATION_NOTES.md`.

**Issue:** DMNC-1506 (P1) · **Branch:** `feat/chart-lab-p1-night` · **Worktree:** `../DOSBTS-wt-lab-p1` · **Base:** `main` after P0 (DMNC-1504) merged · **Tier:** Opus · **Simulator:** `-destination 'id=0272B8A9-4EA4-4E13-A584-3A7E0262CBE2'` (iPhone 17 Pro Max, iOS 26.5; always by `id=`) · **pbxproj object IDs:** file ref `C1AB15040000000100A00001`, build file `C1AB15040000000100A00002`.

**Visual spec:** artboard **2 (Night)** — https://claude.ai/code/artifact/0f40d578-b3a3-460c-a651-aff0f3240dfb (`…/screens/Night.dc.html`). Copy: header `IN BED 23:10 · ASLEEP 6H40 · AWAKE ×2` (cyan) + `ASLEEP 112 → WAKE 152 · ↑ +40 · n=81` (amberLight); the 20:00→10:00 axis with a vertical `00:00` rule; the faint cyan sleep band with hatched awake gaps; the dashed magenta HR line; the dinner ribbon carried across the window start (`+38 · 24 RDG`); the `T-0 62` hypo mark; the sleep-stage block lane (`SLEEP` label); the POST strip `GLU 96% · INS 2 · MEAL 1 · EX — · HR ✓ · SLEEP ✓ · STEPS n/a · NOTES 1`; the NIGHT · DAY · WK row; legend `▮ 2H RESPONSE · ▒ AWAKE · POST COVERAGE PER STREAM`.

**Intent (Dom, verbatim):** "make tangible to users the connection everything has to show: your data, the exercise, and also things that factor into the whole system of diabetes … stress level, other factors in life" — the night is the one period no current window can show whole.

**Goal:** One loader fetches every stream for one interval and reports per-stream coverage, so a lab tab can span midnight. `LAB: NIGHT` uses it to show 20:00→10:00 with sleep stages, heart rate, the evening dose's IOB tail and the last meal's ribbon, a header that names the night's numbers with their N, and a POST strip that says which streams are loaded, empty, or unavailable.

## Architecture (verified findings)

- **Platform seam (P0):** `LabChartView(overlays:)` builds its series from `LabChartInputs(state:overlays:)` (day/24 h store windows). You add a second inputs path from a `LabWindowSnapshot` and an explicit domain; `.nightContext` is your `LabOverlayMarks` arm; `.mealResponseRibbons` is P2's — if P2 has not merged when you branch, the dinner ribbon on NIGHT is drawn by your arm from `computeMealOverlayDelta` and the train reconciles (say so in the notes).
- **Load windows today** (the problem you fix): meals/insulin/exercise = selected day or last 24 h (`ExerciseStore.swift:169-190` `datetime('now', '-… hours')` fallback); journal notes = exact day (`JournalNoteStore.swift:37-46`, `getJournalNoteValues(selectedDate:)` `:168`); heart rate = exact day, hourly (`App/Modules/AppleImport/AppleHealthImport.swift:201` `queryHeartRate(state:publisher:)` → `:311` `fetchHourlyHeartRate(for date:)` with `state.selectedDate ?? Date()`); IOB deliveries = DIA lookback (`IOBMiddleware.swift:41-51`). Four sources, three window rules.
- **The one-read precedent:** `App/Modules/DataStore/ClinicReportStore.swift:22-70` — `getClinicReportData(days:)`: `guard let dbQueue`, ONE `asyncRead`, `filter(Column(timestamp) >= cutoff)`, "never per-hour/per-day in a loop (N+1 reads on the serialized DatabaseQueue stall the app)", NO writes. Copy its shape for the interval read.
- **The transient-state template:** `ratioEvidence` (3-file: `DirectState`, `AppState` plain var, `DirectReducer` set case; action pair load/set) and `RatioLabMiddleware.swift:30-50` — guard `.active`, `.map { .setX }`, **`.catch { … Just(.setX(fallback)) }.setFailureType(to: DirectError.self)`** so the publisher is total (`docs/solutions/logic-errors/middleware-failure-swallowed-nil-as-loading-spins-20260704.md`). Both `App.swift` middleware arrays must register the new middleware (grep `middlewares:`).
- **HealthKit:** `AppleHealthImport.swift:105-113` `readPermissions: Set<HKObjectType>` (carbs, energy, protein, fat, heartRate, activeEnergyBurned, workoutType); `:118` `requestAuthorization(toShare: nil, read: readPermissions)`; `:131-133` the read schedule `(type, .immediate | .hourly)`. Sleep is `HKObjectType.categoryType(forIdentifier: .sleepAnalysis)` with `HKCategoryValueSleepAnalysis` values `.inBed, .awake, .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM`. Adding a read type re-prompts existing users once; HealthKit never reveals a read denial — an empty result is indistinguishable from "no data", so the POST strip says `n/a` only for `.notDetermined`, else `—` for empty.
- **Coverage learning:** `docs/solutions/logic-errors/grdb-mismatched-fetch-windows-silent-zero-result-20260704.md` — every secondary fetch must cover the primary window; assert it in a test.
- **Design system:** `.dosCard` variants (`DOSSurfaces.swift`), `DOSTypography` roles, `AmberTheme.cgaCyan` for sleep, `cgaMagenta` (0.3–0.5 alpha) for HR as the shipping chart does (`ChartView.swift:334-361`), block glyphs as accents only.

## Global constraints

Kickoff constraints verbatim (StyleGuard; no glow in `Chart{}`; explicit domains; `Double.map`; UserDefaults-isolated tests; Redux 4-file lockstep — this plan adds transient (3-file) state only; pbxproj IDs + lint + list check). Plus: no `dbQueue.write` inside `asyncRead`; every derived number carries its N; `n/a` cells deep-link to Settings → Integrations → Apple Health; no changelog entry; the lab is off by default; NIGHT shows only when the lab is on.

---

### Task 0 — Test scaffold

- [ ] `DOSBTSTests/ChartLabNightTests.swift`; pbxproj rows after `ChartLabTests.swift`'s (IDs above); `plutil -lint` + `-list | grep` clean; file-private helpers copied from `DirectReducerTests.swift:28-34`.

### Task 1 — `LabStream` registry + `LabWindowSnapshot` (new `Library/Content/LabWindow.swift`, pure)

```swift
enum LabStream: String, CaseIterable, Codable {
    case glucose, bloodGlucose, meals, insulin, iob, exercise, heartRate, sleep, journalNotes, steps
    enum Shape { case continuous, event, interval }
    var shape: Shape { … }
    enum Source { case grdb, healthKit }
    var source: Source { … }          // steps/sleep/heartRate → .healthKit
    var label: String { "GLU" / "BG" / "MEAL" / "INS" / "IOB" / "EX" / "HR" / "SLEEP" / "NOTES" / "STEPS" }
}
struct SleepSample: Equatable, Codable { enum Stage: Int, Codable { case awake = 0, rem = 1, core = 2, deep = 3, inBed = 4, unspecified = 5 }; let start: Date; let end: Date; let stage: Stage }
struct HeartRateSample: Equatable, Codable { let time: Date; let bpm: Double }   // reuse P0's if it exists
enum LabStreamStatus: Equatable { case loaded(DateInterval), empty, unavailable, failed }
struct LabWindowSnapshot: Equatable {
    let interval: DateInterval
    let readings: [SensorGlucose]; let bloodGlucose: [BloodGlucose]; let meals: [MealEntry]; let deliveries: [InsulinDelivery]
    let iobDeliveries: [InsulinDelivery]; let exercise: [ExerciseEntry]; let notes: [JournalNote]
    let heartRate: [HeartRateSample]; let sleep: [SleepSample]
    let status: [LabStream: LabStreamStatus]
    static let empty: LabWindowSnapshot
    var coverage: [LabStream: DateInterval] { … }   // span of returned rows per stream
}
```
- [ ] Tests `@Suite("Lab window")`: `coverage` spans min…max timestamp per stream; a stream with no rows is `.empty`; `LabStream.allCases` labels are unique and ≤ 5 chars.

### Task 2 — The loader: action + middleware + one interval read

- [ ] `DirectAction.swift`: `case loadLabWindow(interval: DateInterval, streams: Set<LabStream>)` + `case setLabWindow(snapshot: LabWindowSnapshot?)`; `DirectState.swift` / `AppState.swift` / `DirectReducer.swift`: transient `var labWindow: LabWindowSnapshot?` (3-file, `ratioEvidence` template; no reducer case for the load action).
- [ ] `App/Modules/DataStore/LabWindowStore.swift`: `DataStore.getLabWindowRaw(interval:) -> Future<LabWindowRaw, DirectError>` — ONE `asyncRead` fetching readings, blood glucose, meals, deliveries, exercise, journal notes with `timestamp >= interval.start − 4 h && <= interval.end` (the 4 h lead so ribbons/IOB tails that start before the window still draw), plus IOB deliveries with `starts >= interval.start − max(bolusDIA, basalDIA)`; NO writes. Copy `ClinicReportStore.swift:22-70` line for line in shape.
- [ ] `App/Modules/ChartLab/LabWindowMiddleware.swift`: on `.loadLabWindow`, guard `state.appState == .active`; `Publishers.Zip` the GRDB read with the HealthKit reads (Task 3) — each HealthKit read is its own `Future` wrapped in `.catch` → `.failed` status so one denial never sinks the window; `.map { .setLabWindow(snapshot) }` `.catch { Just(.setLabWindow(.empty(with: interval, status: allFailed))) }.setFailureType(to:)`. Register in BOTH `App.swift` arrays. Re-trigger on `.setSelectedDate` only while a lab tab that uses the window is selected (`state.selectedReportType == .labNight`).
- [ ] Tests: reducer set/clear; **coverage contract** — given fixture rows spanning the interval, `snapshot.coverage[stream]` ⊇ requested interval for every `.grdb` stream (a pure `LabWindowSnapshot.assemble(raw:interval:)` makes this testable without the DB); a failed HealthKit stream leaves the GRDB streams `.loaded`.

### Task 3 — HealthKit sleep (+ interval HR)

- [ ] `AppleHealthImport.swift`: add `HKObjectType.categoryType(forIdentifier: .sleepAnalysis)` to `readPermissions` (`:105-113`, keep the file's style); add `func fetchSleep(in interval: DateInterval) async throws -> [SleepSample]` (an `HKSampleQuery` on `HKCategoryType(.sleepAnalysis)` with `HKQuery.predicateForSamples(withStart:end:)`, mapping `HKCategoryValueSleepAnalysis` → `SleepSample.Stage`) and `func fetchHourlyHeartRate(in interval:)` (generalise `:311`'s day version; keep the day version as a wrapper). Expose both through whatever service object the middleware can reach (mirror how `queryHeartRate` `:201` is invoked — read that call site first). Authorisation status via `healthStore.authorizationStatus(for: sleepType)`: `.notDetermined` → `.unavailable`.
- [ ] `Info.plist` `NSHealthShareUsageDescription` already exists (grep) — extend its copy to mention sleep if it lists data types; otherwise leave it.
- [ ] Tests: `SleepSample.Stage` mapping from raw `HKCategoryValueSleepAnalysis` ints (pure); the summary maths in Task 4.

### Task 4 — `NightSummary` (pure) + `LabNightView` + the `.nightContext` arm + POST strip

```swift
struct NightSummary: Equatable {   // Library/Content/NightSummary.swift
    let inBed: Date?; let asleep: Date?; let wake: Date?; let asleepMinutes: Int; let awakeCount: Int
    let glucoseAtSleep: LabFigure?; let glucoseAtWake: LabFigure?; let riseByWake: LabFigure?   // n = readings between
    static func make(sleep: [SleepSample], readings: [SensorGlucose], unit: GlucoseUnit) -> NightSummary
}
```
- [ ] `LabNightView` (`App/Views/Overview/Lab/LabNightView.swift`): window = `[day−1 20:00, day 10:00]` for the selected day (`selectedDate ?? today`); `.onAppear` / `.onChange(of: selectedDate)` dispatch `.loadLabWindow(interval:, streams: [.glucose, .bloodGlucose, .meals, .insulin, .iob, .exercise, .heartRate, .sleep, .journalNotes])`; while `labWindow == nil` show `FiguresLoadingView.inline`; then header (two lines per the artboard, cyan / amberLight, N from `NightSummary`), `LabChartView(inputs: LabChartInputs(window: snapshot, domain: interval, overlays: [.nightContext, .mealResponseRibbons], …))` — add that initializer to `LabChartInputs` (P0's `init(state:overlays:)` stays), the sleep-stage lane (30-min cells, heights by stage, `cgaCyan` at 1.0 deep / 0.7 core / 0.45 rem / 0.25 awake), the POST strip, then a `NIGHT · DAY · WK` row where DAY and WK are dimmed (`.disabled` + `.opacity`, CLAUDE.md pattern) — V1 ships NIGHT only.
- [ ] `.nightContext` arm: faint `RectangleMark` `cgaCyan.opacity(0.05)` over `[inBed, wake]`, hatched awake gaps (`cgaCyan.opacity(0.25)` rectangles), the HR `LineMark` (copy `ChartView.swift:334-361`, gated by nothing — NIGHT always shows HR when present), a 1 pt `amberDark` `RuleMark` at `00:00` with a `00:00` micro label, the hypo `T-0 <value>` label at the first reading < 70 (red, micro).
- [ ] POST strip (`LabCoverageStrip`, `App/Views/Overview/Lab/LabCoverageStrip.swift`): one row, `DOSTypography.microLabel`, cells per `LabStream` in the order `GLU INS MEAL EX HR SLEEP STEPS NOTES`; `.loaded` → `amber` + value (`96%` for glucose = readings ÷ expected at the sensor interval; counts for events; `✓` for HR/sleep), `.empty` → `amberDark` `—`, `.unavailable` → `amberLight` underlined `n/a` (tap → `store.dispatch(.setSettingsCategory(category: .integrations))` — verify the enum case name in `Library/Content/SettingsCategory.swift`), `.failed` → `cgaRed` `!`. `STEPS` is always `n/a` in this build (not read yet).
- [ ] `ChartView.swift`: replace `case .labNight: LabPlaceholderView(tab: .labNight)` with `LabNightView()` — the only line you touch in that file.
- [ ] Tests: `NightSummary.make` on a fixture (in bed 23:10, asleep 23:20, wake 05:50, two awake gaps) → `asleepMinutes` excludes awake gaps, `awakeCount == 2`, `riseByWake.n` = readings between asleep and wake; glucose coverage % maths; POST cell state mapping.

### Task 5 — Suites, build

- [ ] Green: `ChartLabNightTests`, `ChartLabTests`, `DirectReducerTests`, `StyleGuardTests`; full suite (log to file, grep the result line; known-flaky `AppGroupMiddlewareDispatchTests/startupSeedsKeys()`). Both targets build (`Library/` compiles into the widget — keep `LabWindow.swift` free of UIKit/HealthKit imports).

## Verification (simulator; HealthKit on the simulator has no sleep data — seed it via the Health app on the simulator: add a Sleep sample 23:10→05:50 last night, or accept `SLEEP —` and verify the `n/a`/`—` states; virtual sensor for glucose)

1. Lab on → `LAB: NIGHT` shows the loading figure, then the 20:00→10:00 chart with the `00:00` rule and hour labels `8p … 10a`; the newest reading sits near the right edge when it is morning.
2. First open prompts HealthKit for the new Sleep read; grant → header shows `IN BED · ASLEEP · AWAKE ×N` and `ASLEEP … → WAKE … · ↑ … · n=…`; deny/skip → header shows `SLEEP —`, strip cell `SLEEP n/a`, tap → Settings Integrations.
3. A 7 U bolus logged at 22:20 the previous evening shows its IOB area decaying across midnight; an 80 g dinner at 19:05 shows its ribbon starting before the window's left edge (label `+Δ · n RDG`).
4. HR dashed line present when Apple Health HR exists; `HR —` otherwise.
5. POST strip: `GLU 96%` (or the real coverage), `INS 1`, `MEAL 1`, `EX —`, `HR ✓/—`, `SLEEP ✓/n/a`, `STEPS n/a`, `NOTES 0/1`.
6. `<` / `>` day pager moves the night by one day and reloads; kill + relaunch on NIGHT restores it.
7. GLUCOSE tab unchanged; lab off → nothing renders.
8. Airplane mode: everything above still renders (HealthKit and GRDB are local).

## Out of scope

Steps; DAY/WK modes of the NIGHT tab; the wake-anchored AGP; COB; the marker lane; changelog.

## Sibling / merge notes

Parallel with P2–P5 off the merged P0. You touch `LabOverlayMarks.swift` (one arm), `LabChartSeries.swift` (`init(window:domain:…)`), `ChartView.swift` (one line), `DirectState/AppState/DirectReducer/DirectAction` (transient window state), both `App.swift` arrays, `AppleHealthImport.swift`, new files. P2 also reads `journalNoteValues` and adds fields to `LabChartSeries` — expected conflict, mechanical. Never rebase onto or merge sibling work. Fold `IMPLEMENTATION_NOTES.md` into the PR body and `git rm` it.
