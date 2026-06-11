# Changelog

All notable changes to DOSBTS since forking from [GlucoseDirect](https://github.com/creepymonster/GlucoseDirectApp) on 2026-02-28.

Format inspired by [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions below correspond to `CURRENT_PROJECT_VERSION` (TestFlight build numbers), since DOSBTS has not cut a semver release yet.

## [Unreleased]

### Added
- Persistent log actions on every tab: the INSULIN/MEAL buttons now live in a bar above the tab bar (same DOS ghost styling, icon beside label) and work from Overview, Log, Settings, and Daily digest. During a hypo treatment cycle, MEAL opens the hypo-filtered entry directly (R7, R8, AE2).
- Slim glucose strip at the top of the Log, Settings, and Daily digest tabs: current value with trend in the hero's colors, a timer indicator during treatment cycles, and the same 5–14 min amber / 15+ min red stale warnings as the hero — one shared staleness source, no separate refresh path (R7b).

### Changed
- Overview's own INSULIN/MEAL button row is gone — the persistent bar replaces it (no double buttons), and the chart expands into the reclaimed space (R9 Phase 2, taken early by user decision).
- Small informational text (settings descriptions, empty states, timestamps, field labels, digest statuses) brightened from dim amber to full amber across the app and widgets — dim amber measured 3.7:1 on black, below the WCAG AA floor. Dimming for disabled controls, unselected tabs, and decorative strokes is unchanged (R5/AE3).
- Meal rows in the food-entry recents and the Lists tab now share one component. The Lists tab gains an explicit Delete swipe action and Delete in the long-press menu (deleting previously required edit mode) — R3, R4, AE4.
- True CGA monitor feel: no real white anywhere the app controls. All unstyled text falls back to phosphor amber + monospace, navigation titles render amber-light monospace, toolbar buttons tint amber, and the manual Meal, Blood glucose, and Calibration forms plus the AI analysis screen drop their system-gray surfaces for black/amber (R1, R1a, AE1). CGA accents (green/cyan/red) and system chrome (keyboard, picker internals, back buttons) are unchanged.

### Changed (under the hood)
- All sheets (entry, treatment, chart-marker) now present from a single app-level root, so treatment prompts can never collide with or hide behind a user-opened sheet, and they now land you on the Overview tab where the treatment banner lives — even if they fire while you're in Settings or Digest (R8a, AE2a).

### Fixed
- Overview no longer overflows the screen when the hypo-treatment countdown banner is active — the chart compresses to absorb the banner, so the INSULIN/MEAL buttons stay fully above the tab bar instead of being pushed behind it.
- ASK AI in food search now navigates and starts the analysis on the first tap (it previously took several taps and often did nothing): the row's navigation cancelled itself because starting the analysis removed the link mid-push. The keyboard now drops on tap and the search text is kept for when you navigate back — DMNC-1023 wave (R6).
- "Log again" on a recent meal navigates again — its navigation destination was silently ignored inside the legacy navigation container.

## [Build 98] — 2026-06-10

### Fixed
- QUICK favourites row scrolls horizontally again — the hold-to-log mechanic blocked scrolling on amber chips; the hold control now cooperates with scrolling (a drag cancels the hold), on both the favourites row and the recents list — DMNC-796.

### Added
- "> QUICK" header is now tappable with a chevron: expands the favourites row into a wrapped grid showing all favourites (the row previously capped at 8 with no way to see the rest) — DMNC-796.

## [Build 97] — 2026-06-10

### Added
- Press-and-hold insta-log on QUICK favourites and recent meals: holding fills a countdown bar and logs immediately with an UNDO toast; releasing early cancels. The fill animation respects Reduce Motion, and VoiceOver users get a "Log immediately" action — DMNC-796, PR #50.

### Changed
- Tapping a QUICK favourite now opens it on the staging plate for review (portion, time, details) instead of logging instantly. Hypo-treatment favourites still log on a single tap. The "Log Now" swipe and long-press menu on recent meals are replaced by the hold gesture; "Add to Favorites" moved to a trailing swipe — DMNC-796, PR #50.
- Blood glucose entry uses the stepper field with tap-to-type (same control as insulin units), entered in your display unit (mg/dL or mmol/L) — DMNC-796, PR #50.
- Settings reorganized into a drill-down hub of six categories (Alarms & Alerts, Glucose & Display, Insulin, Sensor & Connection, Integrations, System & About). The old "Additional settings" grab-bag is dissolved — its controls moved to their natural categories — DMNC-794.
- Dependent settings controls (Nightscout URL/secret, Apple calendar picker, Health import options, digest reminder time) now dim when their parent toggle is off instead of disappearing, so the layout stays stable and options stay discoverable — DMNC-794.

### Fixed
- Typing a glucose or insulin value and immediately tapping Add now stores the typed value — the stepper field previously committed typed text only when the field lost focus, so Add could store the previous value — PR #50.
- Alarm limit +/− buttons now step by 5 mg/dL and respect the low/high bounds, matching the slider. Previously the buttons moved by 1 regardless of the configured step and could push a threshold past its safety bound — DMNC-794.

## [Build 96] — 2026-05-14

### Added
- Explicit Delete button in the meal/insulin edit sheet (the sheet that opens when you tap "edit" on a chart marker). Shows as **Delete Meal**, **Delete Insulin**, or **Delete Both** depending on what's in the entry, with a confirm dialog. Previously the only way to delete from this sheet was the non-obvious "clear description + zero carbs and Save" path.

## [Build 95] — 2026-05-13

### Added
- Daily digest reminder. Optional local notification fires once a day at a user-configured time and opens the Daily Digest tab when tapped. Toggle + time picker live in Settings → Additional settings; default time when first enabled is 20:00. Disabling the toggle clears the scheduled notification. Notification permission is requested on first enable — DMNC-691.

### Removed
- Internal Gen1/Gen2 freshInstall migration scaffolding. The middleware no longer dispatches once-only first-launch reset code that hasn't applied to a real user install in over a year. No user-visible behavior change; clears four deprecation warnings — DMNC-927.

## [Build 94] — 2026-05-13

### Added
- Siri voice logging for insulin and meals. Trigger via "Hey Siri, log insulin in DOSBTS" or "Hey Siri, log a meal in DOSBTS" — Siri prompts for the missing values (units / type / carbs / description) and writes the entry directly to the log without opening the app. Discoverable in the Shortcuts app and on Siri search results once the app has been opened once after upgrade. Defaults: insulin type = snack bolus, meal description = "meal", basal entries get a 24h ENDS automatically — DMNC-633, DMNC-634.

## [Build 93] — 2026-05-13

### Fixed
- Meal and insulin markers appear on the chart in the same frame the entry is added or edited (previously took 100-500 ms — sometimes longer — to show up). Root cause: the data store ran synchronous GRDB writes on the main thread, which blocked SwiftUI's runloop and stalled the chart's `.onChange` observers until the write+read round-trip completed. Writes are now async via `dbQueue.asyncWrite`, and edits/deletes hit an optimistic in-memory path in the reducer so the chart re-renders without waiting on the database — DMNC-905.

## [Build 92] — 2026-05-10

### Changed
- Insulin units field no longer forces a `.0` suffix while typing. Type `20` and the field shows `20`; the decimal separator is now yours to enter when you actually need a fractional value (e.g., `2.5`). Whole-number values display without a trailing `.0` even when the field isn't focused.
- Add Insulin → Basal now auto-sets the ENDS date/time to 24 hours after STARTS. The duration updates whenever you change the type to basal or adjust the starts time, so the once-daily injection flow (the dominant case) doesn't require touching the date picker.

## [Build 91] — 2026-05-08

### Fixed
- Home Screen widget glucose value now scales down to fit when the reading is three digits. The small + medium widget layouts both use `.minimumScaleFactor(0.6)` so a value like `123` shrinks to fit alongside the trend column instead of truncating to `1...`. Two-digit values keep the full hero size.

## [Build 90] — 2026-05-04

### Changed
- Heart-rate overlay now uses the same Y axis as the glucose line. An HR of 80 lands at the same height as a glucose of 80 mg/dL (or the equivalent mmol/L), so the line shows where the heart rate actually is rather than being squeezed into the top of the chart.
- Basal insulin IOB now decays from the entry's start time over the basal model's DIA. A 24-hour basal is fully gone by hour 24 (previously the segmented-infusion model extended observable IOB to ~48 hours past injection because each delivery segment decayed independently from its midpoint).
- Correction-bolus stacking warning in Add Insulin now shows only rapid-acting (meal/snack/correction) IOB. Long-acting basal is the steady-state baseline and isn't part of the correction-stacking decision.

### Added
- Basal insulin entries now appear in the chart event-marker badges and the entry-detail overlay alongside boluses, with a distinguishing outline-syringe icon and a `b` suffix on the chip label (e.g., `12Ub`). Tapping a badge that contains basal entries opens the same detail flow as for bolus entries.

## [Build 89] — 2026-05-04

### Changed
- Hero-row chrome is hidden when both the screen-lock prevention and an alarm snooze are inactive. Active states now carry text labels — `Screen lock off` (with a strike-through lock icon) and `Snoozed until <time>` — so the icons no longer require interpretation. Tapping the snooze label still extends the snooze by 30 minutes; the ✕ button still clears it. Screen-lock prevention has moved to Settings → Additional settings (`Keep screen awake`) since the hero-row entry path is no longer visible when the feature is off.

## [Build 88] — 2026-05-03

### Added
- Day/night alarm profiles. Two separate threshold + volume profiles switched on a fixed user-configured time window (default 22:00–07:00). Solves nighttime alarm fatigue without changing day-time behavior for users who don't opt in. Settings → Alarms now has Day profile, Night profile, and Sleep schedule sections; the existing single threshold/volume controls migrate transparently into both profiles. A small moon glyph appears in the Overview tab, the Home Screen + Lock Screen widgets, and the Live Activity when night profile is active (VoiceOver-readable). Boundary transitions use a 5-min responsiveness floor in the in-app alarm path; the home-screen widget timeline schedules a refresh entry exactly at the next boundary, and the Live Activity resolves the active profile at render time, so lock-screen surfaces stay correct without push churn. Treatment-cycle behavior, snooze, predictive low, and critical-low breakthrough all read the active profile transparently — no cycle pinning. Settings shows symmetric warning rows when night thresholds are more permissive than day, plus a red warning when the night high is unusually close to the low threshold. Sensor end-of-life warnings always play at the louder of the two configured volumes so a silenced night profile cannot suppress an overnight sensor failure. **Rollback note:** day-side threshold and volume changes dual-write to legacy keys for safe rollback to the prior build; night-side changes are not mirrored, so a rollback after night customization recovers to the day configuration — DMNC-692.

## [Build 87] — 2026-05-01

### Fixed
- INSULIN and MEAL quick-action buttons no longer get clipped by the tab bar at the bottom of the Overview tab. The sticky action row is now anchored above the tab bar via `.safeAreaInset(edge: .bottom)` instead of riding the bottom of a VStack whose final element extended into the tab bar's footprint, so the button labels render in full on every device size.

## [Build 86] — 2026-04-30

### Changed
- IOB readouts now react to settings changes mid-flight. The treatment-cycle banner picks up basal-DIA and bolus-preset changes immediately (previously only refreshed on new deliveries / appear). The "Add Insulin" sheet's stacking warning recomputes IOB on every body evaluation, so adjusting basal DIA while the sheet is open updates the warning live (previously it captured IOB once at sheet construction). Pre-existing reactivity gaps; no new functionality, just consistency — DMNC-879, PR #48.

### Removed
- Three deprecated-API warnings cleaned up at build time: SwiftUI Charts `plotAreaFrame` → `plotFrame` (with the new optional handled via `guard`, no force unwrap), ActivityKit `Activity.update(using:)` / `.end(using:)` / `.request(...:contentState:...)` → the `ActivityContent`-based variants, and `BarcodeScannerView`'s `NavigationLink(isActive:)` → `.navigationDestination(isPresented:)`. No behavior change; build log is quieter.

## [Build 85] — 2026-04-30

### Fixed
- Basal IOB no longer decays at the rapid-acting rate when a long basal DIA is configured. Previously the basal model was constructed with the bolus's 75-minute peak even at 24h DIA, so a 24h-DIA basal dose dumped most of its activity in the first ~5 hours and read near-zero by hour 6 — visually indistinguishable from a bolus on the chart. The basal model now scales its peak with DIA (≈ DIA × 0.4, floored at the bolus 75-minute peak so short DIAs degrade gracefully, and capped at 0.49 × DIA so the Maksimovic model's constants remain well-defined for every DIA in the UI's range). At 24h DIA you'll now see basal IOB stay around ~80% at hour 6 and ~42% at hour 12, which matches a long-acting profile (Lantus / Levemir / Tresiba). Affects every IOB display: chart area, hero header, treatment banner, AddInsulinView's stacking warning, and the entry-group overlay — PR #47.

### Changed
- Tapping a recent meal in the Log Meal sheet now reopens it on the staging plate so you can adjust the portion (or items) before saving as a new entry — instead of immediately re-logging the meal verbatim. Quick "log now" is preserved as a leading swipe-action and as a context-menu item on each row. Meals that were originally logged via AI analysis carry their `analysisSessionId` through the relog so the new entry still links to the same PersonalFood cluster (no spurious "correction" written) — DMNC-761, PR #46.

## [Build 84] — 2026-04-26

### Fixed
- Correction boluses are no longer counted as basal IOB. Previously the IOB calculator put `.correctionBolus` in the same bucket as `.basal`, so a 3U correction bolus showed up as "BASAL" in the chart legend and stack. The bucketing now follows insulin pharmacology: meal / snack / correction boluses are all rapid-acting and go into the bolus bucket; only `.basal` is in the basal bucket. The IOB header label, the chart's split-IOB stack, and the `mealSnackIOB` / `correctionBasalIOB` returned values all reflect this correctly now.

### Changed
- Marker flag poles dropped. The lane sits beneath the chart so the poles weren't anchored to anything semantically meaningful — just the bottom of the lane. Lane height shrinks 90 → 60pt.
- `IOBCalculatorTests/splitIOB()` updated to assert the new bucketing (`mealSnackIOB == 4.0` for meal + correction together, not split).

## [Build 83] — 2026-04-26

### Changed
- Chart event markers redesigned to match the locked Q2-final-lock brainstorm spec (`.superpowers/brainstorm/35252-1777068283/content/q2-marker-overlap-v15-final-lock.html`). Each event renders as a small black chip with an amber-dim border, containing one row per event type — `<icon> <value>` — stacked top-to-bottom in the order `insulin → meal → exercise`. A 22pt amber-dim "pole" drops from the chip's bottom centre to the lane baseline so the marker visually anchors at the event time. Single events with one type show a one-row chip (e.g. `🍎 30g`); multi-event groups stack rows (e.g. `💉 5U / 🍎 45g`). Multi-entries-within-a-type collapse to a sum with a count suffix (`5U×2`, `45g×3`).
- Marker consolidation rewritten from a fixed time-window (e.g. 30 min at 24h zoom) to overlap-driven: walk left-to-right, merge if the next chip would land within 4pt of the previous one's right edge. Chip widths therefore drive consolidation, not arbitrary minute counts — and you no longer get "all 7am entries collapsed into one icon" at 24h zoom even when their absolute distance would have rendered them separately.
- Touch target stays 88pt × 48pt centred on each chip; iOS resolves overlapping touch targets by centroid distance.
- Marker lane height bumped 48pt → 90pt to fit chip + pole. Chips with up to three stacked rows fit comfortably; the chart pane shrinks slightly to accommodate.
- Replaces the previous bare-icon-with-circle-border design which hid event values, conflated counts of different types, and overlapped messily in dense windows.

## [Build 82] — 2026-04-25

### Changed
- Split-IOB stacking order flipped: basal+correction now sits at the floor (sky blue baseline) and bolus stacks on top (warm green peaks). Matches the semantic — basal is the constant background insulin, bolus is the variable on-top dose. Visually you can see the basal "floor" stay roughly steady while bolus spikes ride above it.

## [Build 81] — 2026-04-25

### Fixed
- Split-IOB basal layer is now actually visible on the chart. Both AreaMark layers (bolus + basal) now declare an explicit `series:` argument so SwiftUI Charts treats them as two independent stacked series. Without it, the two `ForEach` loops were silently auto-grouped into a single series and the second layer never rendered — that's why the previous "make basal more visible" passes didn't help even at 0.85 opacity. Sky blue retained from Build 80.

## [Build 80] — 2026-04-25

### Changed
- Split-IOB basal layer color swapped from cool green (#40B38C) to bright sky blue (#5DD0F3). The previous green was too close to the warm-green bolus layer in saturation and value, so on a 24h chart with substantial bolus IOB the basal contribution was visually swallowed. Sky blue at 0.85 opacity reads cleanly above the warm-green bolus area.
- IOB area chart sampling resolution: 5-min → 1-min. The chart was showing visible step "cuts" when a new bolus delivery happened between two adjacent samples; finer sampling smooths the curve so deliveries integrate as a smooth ramp instead of a vertical step. Also makes DIA expirations fade gracefully.

## [Build 79] — 2026-04-25

### Changed
- Insulin entry stepper now uses 1-unit steps (was 0.5U). Pen users with whole-unit-only doses no longer have to tap twice per click. Help caption updated accordingly. Tap-to-type still works for fractional doses if needed.

### Fixed
- New meal and insulin entries now show on the chart immediately. Previously the reducer only updated the `latest*` reference and waited for the GRDB-write-then-load middleware round-trip before the marker appeared. Reducer now appends to `mealEntryValues` / `insulinDeliveryValues` optimistically; the load round-trip subsequently replaces with the canonical DB state, and the marker stays in place.

## [Build 78] — 2026-04-25

### Changed
- Daily Digest AI insight is now structured: a short opening paragraph (1–2 sentences naming the day's pattern) followed by 2–4 bullet points referencing specific times and values. Bullets render with a cgaCyan glyph so they pop visually against the amber prose. The Claude prompt was updated accordingly; old cached insights without bullets still render gracefully as a single paragraph. Inline markdown (italics, bold) is now interpreted via SwiftUI's LocalizedStringKey path. No headlines, no asterisks, no markdown headers — keeps the wall-of-text feeling at bay without adding heavy structure.

## [Build 77] — 2026-04-25

### Fixed
- Tapping a combined food + insulin marker on the chart now reliably shows BOTH the meal AND the insulin row in the read overlay. When the entity lookup transiently failed for one of them, the row was rendering with empty Texts (looking like blank space) — primary text and value text now fall back to a generic type label + the marker's pre-computed `label` so the row always has visible content. Subline falls back to a "paired w/ meal" / "paired w/ insulin" hint when the entity lookup fails.
- Bolus / insulin markers and row icons swap from the dim brown `amberDark` to the brighter primary `amber`. The previous brown was readable against the chart's amber-tinted background but nearly invisible on the read overlay's pure-black sheet.

## [Build 76] — 2026-04-25

### Changed
- Lists tab → Statistics section redesigned to match the Overview chart's STATISTICS tab vocabulary: hero AVG number with unit, 2×2 stat grid (GMI · TIR / SD · CV) with interpretive helpers ("Stable" / "Variable", "On target" / "Close" / "Off target"), stacked TBR/TIR/TAR distribution bar with three-up numeric breakdown, target range + readings/days footer, period chips (3d/7d/30d/90d) styled to match other AmberChip selections. Annotations toggle (double-tap) keeps the long-form GMI/TIR/SD/CV definitions for first-time readers.
- Lists tab → Usage section: views/day, total views, sensor uptime now render as 3-up `StatCard` row matching the rest of the stats vocabulary. Sensor uptime is colour-coded by clinical thresholds (≥90% green, ≥70% amber, otherwise red).
- Settings main list dropped iOS `.grouped` chrome: `.listStyle(.plain)`, hidden scroll background, dosBlack background, amber-dim row separators. Per-section sub-views still render their own iOS `Section` content; main-list visual is closer to a flat CGA list.
- Daily Digest 3-column stat grid uses the same `StatCard` primitive (TIR/LOWS/HIGHS/AVG/CARBS/INSULIN). TIR card now shows on-target/close/off-target hint; HIGHS amber colour matches the chart palette instead of the previous one-off RGB literal.
- Overview hero IOB label is bigger and easier to read: 14pt monospaced numeric values vs the old 12pt at 50% opacity, "BOLUS" / "BASAL" subscript labels (in the matching warm/cool green from the chart's split-IOB layers) replace the cryptic `M`/`B` suffixes. Color disambiguation matches the chart so the eye carries one mapping across both surfaces.

### Added
- `Library/DesignSystem/Components/StatsComponents.swift` extracts the shared stats primitives (`HeroStatView`, `StatCard`, `StackedTIRBar`, `TIRBreakdownRow`, `tirColor`, `tirHelp`) so the Overview chart, Lists tab, and Daily Digest all use the same vocabulary. Reduces drift if any one of these surfaces changes.

## [Build 75] — 2026-04-25

### Changed
- TIME IN RANGE tab on the Overview chart redesigned. Hero `TIR%` number large + colour-coded by clinical thresholds (≥70% green, ≥50% amber, otherwise red). Single horizontal stacked TBR/TIR/TAR distribution bar replaces the three separate bars. Three-up numeric breakdown below ("BELOW · IN RANGE · ABOVE"). Target range and days-covered footer.
- STATISTICS tab on the Overview chart redesigned. Hero AVG glucose with unit. 2×2 grid of stat cards: GMI (with "≈ A1C" hint), TIR (with on-target / close / off-target hint, colour-coded), SD (with unit), CV (with "Stable" / "Variable" hint, colour-coded against the 33% clinical threshold). Footer shows readings count + days covered.

## [Build 74] — 2026-04-25

### Changed
- Custom `AppleIcon` now used everywhere previously rendered Apple Inc.'s `apple.logo` SF Symbol: sticky [MEAL] action button, Lists tab → Meals header, Food photo analysis section header, Meal-from-photo result-edit section header, and the home-screen widget's last-meal row. `QuickActionButton` was generalised to accept a `@ViewBuilder icon` closure so callers can pass any icon view (SF Symbol, custom shape, composite). No more Apple Inc. logo anywhere user-facing.

## [Build 73] — 2026-04-25

### Added
- Custom `AppleIcon` (Path-based fruit silhouette with leaf) replaces Apple Inc.'s `apple.logo` SF Symbol for chart markers, the read-overlay row icon, and the combined-edit modal's FOOD section header. Distinct visual, no App Store identity-guidelines risk. Sticky [MEAL] action button + iOS Form `Label`s still use `apple.logo` for now (less prominent surfaces; harder to swap without a Label refactor).
- `CombinedFoodInsulinIcon` — a single statically-composed visual (apple bottom-left + syringe top-right) used for chart-marker batches that mix food + insulin entries.

### Changed
- Chart marker batches now show **one icon per batch type** with a circular border indicating multi-entry, instead of stacked icons + count badge:
  - 1 meal → bare apple icon
  - 2+ meals → apple icon + green circle border
  - 1 insulin → bare syringe icon
  - 2+ insulin → syringe icon + amber circle border
  - Mixed food + insulin (any count) → CombinedFoodInsulinIcon + amber border (or bare if both counts are 1)
  88×48pt touch target preserved.
- Bolus IOB area mark opacity bumped from 0.45 → 0.7. The warm-green bottom layer is now clearly readable underneath the cool-green basal+correction layer.
- Read overlay opens as a half-screen sheet (`.presentationDetents([.medium, .large])` with a visible drag indicator) instead of a full-screen modal. Combined edit modal is also half-screen by default, can be dragged up to full.
- Read overlay's "Edit" affordance is now lowercase text-only ("edit") — drops the pencil glyph.

## [Build 72] — 2026-04-25

### Changed
- Split-IOB colors changed: bolus (meal/snack) is now warm green (#8CBF40, yellow-leaning), basal+correction is cool green (#40B38C, blue-leaning). Both clearly green so they read as "two flavours of IOB" but distinguishable at a glance. Replaces the previous brown amber-dark for basal which was nearly invisible against the dark chart background.
- Removed the IOB legend chips from the chart header — the warm/cool green split is self-explanatory and the labels added clutter for nothing. HR legend chip kept since magenta-on-amber-chart isn't obvious without it.

## [Build 71] — 2026-04-25

### Changed
- Split IOB area marks now stack instead of overlapping. Meal/snack IOB (cyan) sits at the bottom, basal/correction IOB (amber-dark) stacks above it, so total area at any point equals the running total IOB and you can read both components at a glance.
- Chart legend chips for IOB and HR overlay components — small swatch + label pairs in the chart header row (e.g. `MEAL/SNACK` cyan + `BASAL/CORR` amber when split IOB is on). Color-to-component mapping is now visible without remembering which is which.
- Chart toolbar split into two consistent strips with matching font + underline treatment: report-type tabs (GLUCOSE / TIME IN RANGE / STATISTICS) above the chart, time-range / day-window tabs (3h…24h or 7d…ALL) **below** the chart. Both rows are now the same visual size — previously the zoom row was a notch smaller than the report-type row.
- Marker-lane position picker in Settings → Additional gets a label and a one-line description ("Where the meal/insulin/exercise icons sit relative to the glucose chart") so it's clear what the segmented control does.

## [Build 70] — 2026-04-25

### Changed
- `AddInsulinView` rebuilt to match the original brainstorm mockup. Drops iOS `Form`/`Section` (which was rendering gray rounded card backgrounds that broke the CGA aesthetic). New layout: flat black background, custom nav bar (Cancel · ADD INSULIN · Add), all-caps amber-dim form labels, full-width chips, big 56pt-tall stepper with separated value/unit display, IOB warning gets its own bordered amber-tint card.
- `AmberChip` selected state is now solid amber background + black semibold text (was: barely-visible 8%-opacity tint that disappeared against the dark background). Type chips are 44pt tall, preset chips 40pt; both fill available width.
- `StepperField` redesigned: 56pt tall body, 60pt-wide tinted +/- buttons, 24pt amber value with separate dimmed unit suffix (e.g. `4.5` + `U`). Optional caption underneath ("tap value to type · ±0.5U steps"). Tap-to-type still works.
- Meal/carbs icon swapped from `fork.knife` to `apple.logo` everywhere: chart markers, sticky [MEAL] action button, food-photo / meal-entry section headers, meals list tab, home-screen widget last-meal row.

## [Build 69] — 2026-04-25

### Added
- Unified marker → read overlay → edit flow (DMNC-848). Tapping any chart marker opens a Libre-style list overlay with chronological rows showing IN PROGRESS state, post-meal delta (mg/dL or mmol/L per user setting), confounder icons, PersonalFood glycemic average + observation count, and IOB-at-dose-time. Edit opens a single combined modal with shared time and edit-only semantics; both meal and insulin updates use id-preserving constructors and route through GRDB load-after-write so the chart re-renders cleanly.
- `AmberChip`, `StepperField`, `QuickTimeChips` design-system primitives for chip rows, numeric steppers, and quick-time selectors used in the redesigned insulin entry surface and combined edit modal.
- `StagingPlateRowView` extraction shared between `FoodPhotoAnalysisView` and the new `CombinedEntryEditView` — single ratio-link auto-scale + manual override implementation.
- End-of-line numeric BPM readout on the heart-rate chart overlay (when enabled and HR data is fresh within the last 10 minutes). DMNC-848 D6.
- Chart customisation: marker lane position toggle in Settings → Additional settings (above or below the glucose chart). Default is "above" — no change for existing users unless they opt into below. DMNC-848 D7.

### Changed
- `AddInsulinView` replaces the type `Picker` with an `AmberChip` row, the units `TextField` with a `StepperField`, and the time `DatePicker` with `QuickTimeChips` (NOW / −15m / −30m / −1h plus a `⋯` chip opening a custom DatePicker popover). Basal entries still show an `Ends` `DatePicker`. The IOB stacking warning for correction boluses is preserved.
- Chart marker visual: bare type-coloured icons (22pt) replace the bordered chips with text labels. Cross-type clusters consolidate with stacked icons (max 3) and a count badge in the dominant type's colour. Marker lane height bumped from 32pt to 48pt to honour the larger touch target.
- Insulin marker tap no longer shows a bare `confirmationDialog` with a Delete option. Delete now requires opening Edit; the read-overlay surface keeps the action gesture light.
- Heart-rate overlay on the glucose chart is now toggleable (Settings → Apple Health import → "HR overlay on chart"). Default is **off** to give users explicit control. Builds ≤ 62 rendered the magenta HR line whenever HealthKit import was active; users who want that back must enable the toggle. DMNC-848 D6.

## [Build 68] — 2026-04-24

### Changed
- App icon is now a CGM-sensor take on the eiDotter yolk: concentric amber disc / active-scan ring / central filament dome mirroring the brand's three-stop amber palette, with cardinal tick marks and symmetric transmission arcs reading as wireless emissions. Replaces the insulin-pen-and-drop placeholder. Source in `scripts/app-icon.svg` and `scripts/render-app-icon.py`; derived sizes via `scripts/resize-icon.sh`.

## [Build 67] — 2026-04-24

### Fixed
- Home-screen glucose widget stayed stale when the app was backgrounded. `WidgetCenter.reloadAllTimelines()` was only wired into `.setAppState(.active)` (scene-becomes-foreground) and `ContentView.onChange(of: latestSensorGlucose)` (which doesn't fire while the scene is backgrounded). New sensor readings arriving via the background BLE path never refreshed the widget until the widget's own 15-minute scheduled tick or the user reopened the app. Widget now reloads on every `.addSensorGlucose` from the middleware so it refreshes regardless of scene state.

## [Build 66] — 2026-04-24

### Added
- Thin 4px horizontal progress bar under the M:SS countdown text on the hypo-treatment banner, filling left-to-right over the configured wait duration. Gives a continuous visual cue of remaining recheck time without making you read the timer — DMNC-771, PR #39.

### Changed
- Settings → About gains a **Disclaimer** section clarifying DOSBTS is a community reader app, not a medical device, and that treatment decisions must be verified with the CGM manufacturer's reader and a clinician. Adds a **Build date** row (read from the binary's modification time) and a **Forked from** row linking to upstream GlucoseDirect — PR #38.

## [Build 65] — 2026-04-24

### Added
- Settings → **Connections** screen consolidates Nightscout, Apple Health & Calendar export, AI Features, and Health Import Sources into one indexed view with per-integration status dots (green = active / grey = inactive / red = needs configuration). Each row drills into the existing settings surface for that integration. Individual rows remain available in the main Settings list — DMNC-810, PR #35.
- **Usage** section on the Statistics screen (Lists tab) — views-per-day average, total views since tracking began, and sensor uptime % over the currently-selected window. Lets you spot over/undercheck patterns and data-quality gaps at a glance — DMNC-811, PR #36.

## [Build 64] — 2026-04-24

### Changed
- Red "Disconnected" warning chip under the hero glucose value and the sensor-line CONNECT chip now open a confirmation dialog with two reconnect options — Connect (BLE) for a fast reconnect to the paired session, or Scan Sensor (NFC) for a full re-scan (new sensor, expired session, transmitter reset) — DMNC-808, PR #27.
- Overview chart zoom picker is now tab-aware. GLUCOSE tab keeps `3h / 6h / 12h / 24h`; TIME IN RANGE and STATISTICS tabs show `7d / 30d / 90d / ALL`. The stats aggregation window updates on selection so TIR / AVG / SD / GMI reflect the picked range. Persisted per-tab via the existing state — DMNC-806, PR #28.
- Favourite chips in the `> QUICK` row now have a bounded width (~120pt) so a long barcode-scanned name can't dominate the row and short labels no longer get clipped by horizontal scroll. Long text truncates with `…`. Favourites gain an optional **Short label** field (editable from the favourite edit sheet) that renders on the chip in place of the full description when set. Existing favourites without a short label keep rendering as today — DMNC-804, PR #29.

## [Build 63] — 2026-04-24

### Changed
- Overview screen is now a fixed no-scroll layout. Chart toolbar (GLUCOSE / TIME IN RANGE / STATISTICS and 3h / 6h / 12h / 24h) pinned above the chart with an underline-on-selected treatment; sensor connection status moved inline under the hero with tap-to-reveal disconnect; sticky actions trimmed to INSULIN + MEAL (BG entry moved to the Log tab with a one-shot relocation alert on first launch). Full sensor / transmitter detail surface moved into Settings → Sensor details — DMNC-793, PR #26.

## [Build 62] — 2026-04-22

### Fixed
- Chart rendered blank on scene-restoration cold launches. `UIScreen` extension now walks `UIApplication.connectedScenes` (iOS 26 replacement for deprecated `UIScreen.main`), and `ChartView.screenWidth` clamps to `max(0, …)` so a pre-scene 0 width can't cache a negative value into the chart's `@State` — DMNC-780, PR #25.

## [Build 61] — 2026-04-22

### Added
- Changelog, README rewrite, and LICENSE fork attribution — PR #22
- GitHub Sponsors link for DOSBTS-specific support, alongside the upstream donate link — PR #22

### Changed
- Xcode project migrated to `fileSystemSynchronized` groups — new Swift files under `App/`, `Library/`, `Widgets/` are auto-picked up (`pbxproj` went from 2,055 → 750 lines) — DMNC-768, PR #21
- iOS deployment target bumped from 15.0/16.0 → 26.0 across all targets — DMNC-769, PR #19
- SettingsView: inter-group breathing room between setting groups — DMNC-770, PR #20

### Removed
- Facebook group and Crowdin rows from Settings → About — PR #22

## [Build 60] — 2026-04-20

### Added
- Widget phosphor display rework (expanded data: sparkline, IOB, TIR, last meal) — PR #18

## [Build 59] — 2026-04-20

### Added
- **Daily Digest tab** (4th tab) with per-day stats grid, AI-generated insight (Claude Haiku), and chronological event timeline. Requires separate `aiConsentDailyDigest` toggle. — DMNC-579, PR #17

### Fixed
- GRDB deadlock: moved write outside `asyncRead` to prevent queue starvation
- Double-resume crash in Combine Future → async bridge

## [Build 55] — 2026-04-21

### Added
- **Meal impact overlay** — tap a meal marker to see 2-hour post-meal glucose delta, confounder detection (correction bolus / exercise / stacked meal), and PersonalFood rolling glycemic score. Dual-trigger computation (retroactive on app activation + real-time on new readings). — DMNC-688, PR #14
- **Libre-style event marker lane** above the glucose chart with SF Symbol icons (fork.knife, syringe.fill, figure.run) and zoom-dependent consolidation. — DMNC-635, PR #16
- Refactoring UI polish: warm greys, marker lane depth, stats hierarchy

### Fixed
- Backport cleanup from DOOMBTS: Y-axis trailing, HR legend header, haptic feedback — DMNC-714

## [Build 54] — 2026-04-18 ("IOB release")

### Added
- **Insulin-on-Board (IOB)** — OpenAPS oref0 Maksimovic exponential decay model with `InsulinPreset` enum (rapid-acting peak 75m / DIA 6h, ultra-rapid peak 55m / DIA 6h). Hero display with 60s refresh, split display toggle, chart AreaMark overlay (iOS 16+), stacking warning in AddInsulinView, InsulinSettingsView. — PR #13

## [Build 53] — 2026-04-17

### Added
- **Stale data indicator** on hero glucose — "X MIN AGO" warning (amber 5–14 min, red 15+) to prevent dosing decisions on silently stale data

## [Build 52] — 2026-04-17

### Added
- **XCTest target** with initial reducer snapshot tests (later expanded to 137 tests)

## [Build 51] — 2026-04-17

### Added
- **Predictive low alarm** — 20-min forward extrapolation of glucose trajectory using smoothed minuteChange. Fires "Trending Low" notification with "EAT NOW" UNNotificationAction. Chart shows dashed projection line (iOS 16+) with red cross marker at predicted threshold crossing. Toggle: `showPredictiveLowAlarm`.

## [Build 50] — 2026-04-17

### Added
- Chart markers: bigger markers, delete buttons on meal/insulin markers, grouped entries (15-min timegroup → circle with count + total carbs)

## [Build 49] — 2026-04-17

### Added
- **Guided hypo treatment workflow** ("Rule of 15") — alarm → `.showTreatmentPrompt` → user logs 15g carbs → 15-min countdown → recheck → stabilised or treat again. Background-safe via UNNotificationAction buttons + foreground TreatmentModalView. Alarm suppression during countdown with critical-low safety floor (`alarmLow - 15 mg/dL` breaks through). Configurable wait time (`hypoTreatmentWaitMinutes`, default 15). TreatmentEvent persisted to GRDB.

## [Build 35–48] — 2026-04-08 → 2026-04-15

### Changed
- **Libre-inspired layout overhaul** — hero glucose → treatment banner (if active) → chart → action buttons → connection → sensor. Matches standard CGM app flow.
- **Sticky action buttons** + compact hero/chart layout
- **Sensor disc app icon**
- **Gradient glucose color** — green in range, amber high, red danger
- **ActiveSheet enum** — all sheets consolidated into a single `.sheet(item:)` with discriminator (fixes iOS sibling sheet collisions)

## [Build 29–34] — 2026-04-03 → 2026-04-08

### Added
- **Staging plate UX** — amount editing + inline barcode — DMNC-567
- **Portion presets & smart quantities** — DMNC-562
- **Conversational follow-up** for food clarification — DMNC-560
- **Barcode scanning** via Open Food Facts (free, no AI consent required) — DMNC-561
- **Natural-language food parsing** via Claude — DMNC-558

## [Build 24–28] — 2026-03-22 → 2026-04-03

### Added
- **Editable AI results** with staging plate + learning from corrections (PersonalFood glycemic database)
- **Log again swipe** + add to favorites context menu
- **Favorites management** — reorder, edit, delete

## [Build 21–23] — 2026-03-15 → 2026-03-22

### Added
- **Unified food entry view** with favorites, recents, and search — PR #1
- **FavoriteFood model**, middleware, Redux wiring
- Quick re-logging workflow

## [Build 16–20] — 2026-03-10 → 2026-03-15

### Added
- **Thumb calibration** for portion sizing, sensor button layout — DMNC-527, DMNC-456
- Combined MANUAL/PHOTO buttons aligned with INSULIN
- Grouped meal buttons under LOG FOOD label

### Fixed
- Middleware race condition, automatic signing (build 15)

## [Build 2–15] — 2026-02-28 → 2026-03-09

### Added
- **DOSBTS rebrand** — bundle identity, signing, app name
- **eiDotter CGA amber design system** — Phase 1 (tokens moved to Library, components added), Phase 2 (all views migrated to AmberTheme + DOSTypography), Phase 3 (legacy Color.swift removed)
- **Phosphor glow** matched to glucose alarm state
- **CRT scanline overlay** (optional)
- **UI overhaul** — restructured navigation, quick actions, CRT effects
- **AI food analysis** — photo analysis via Claude with full nutrition breakdown, HealthKit export
- **Insulin** — initial insulin stores, HealthKit export, Nightscout upload
- **Food logging MVP** — meal entries, chart markers, manual logging
- **HealthKit import** — nutrition, exercise, heart rate

---

## Pre-fork

Everything before 2026-02-28 is upstream [GlucoseDirect](https://github.com/creepymonster/GlucoseDirectApp) by Reimar Metzen — the foundational work on Libre 1/2/3 sensor connections, LibreLinkUp integration, Bubble transmitter support, calibration math, Nightscout upload, Apple Watch calendar export, HealthKit export, and the Redux-like architecture. DOSBTS inherits all of it under MIT.

See the [upstream repository](https://github.com/creepymonster/GlucoseDirectApp) for the pre-fork history.
