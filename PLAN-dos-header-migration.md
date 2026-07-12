# PLAN: dosHeader migration — system Section headers → canonical `.dosHeader()` + StyleGuard Rule 9

**Linear:** none yet — create a DOSBTS-project issue when starting ("Migrate system Section headers to .dosHeader + guard", note it completes the DMNC-1216 surface-chrome convergence; CLAUDE.md calls it a "tracked follow-up").
**Rank:** 6 of 6. Effort: S (~2–3 hours, mostly verification screenshots). Fully mechanical; independent of all other plans.

## Goal

Every SwiftUI `Section` header under `App/Views/` renders through the canonical `.dosHeader()` modifier (12pt semibold mono, 1.2 tracking, uppercase, `amberDark` default — `Library/DesignSystem/Modifiers/DOSSurfaces.swift:78`), and a new StyleGuard test locks the class shut so unstyled system headers can never reappear.

## Ground truth (verified 2026-07-10 against Build 129 — re-verify before editing)

- There are **48 header-closure sites in 21 files** under `App/Views/` using the trailing/argument closure form `header: {` — the old CLAUDE.md phrasing `Section(header: Label(...))` (argument-form) has **zero** hits; do not grep for that.
- 42 sites wrap a `Label("…", systemImage: "…")`, ~3 wrap `Text`, rest misc. Site count per file:
  `FoodPhotoAnalysisView 7 · SensorDetailView 5 · AboutView 5 · InsulinSettingsView 4 · AlarmSettingsView 4 · AISettingsView 3 · StatisticsView 3 · UnifiedFoodEntryView 3 · AppleExportSettingsView 2 · one each in: SystemAboutCategoryView, SensorConnectorSettingsView, SensorConnectionConfigurationView, NightscoutSettingsView, InsulinCategoryView, HealthImportSourcesView, GlucoseSettingsView, GlucoseDisplayCategoryView, CalibrationSettingsView, BellmanSettingsView, FactoryCalibrationView, CustomCalibrationView`
- `.dosHeader(_ color: Color = AmberTheme.amberDark)` is a plain view modifier — it works applied directly to a `Label` (font/tracking/case/color cascade to the label's text; the icon inherits the `foregroundStyle` color). **The migration is a one-modifier append per site, not a Section restructure.**
- One site already carries custom styling: `SensorDetailView.swift:72-74` (`Label("Connection error", ...).foregroundStyle(AmberTheme.cgaRed)`) — see step 2 for how to treat semantic colors.

## Preconditions

`git pull --ff-only`; branch `style/dos-header-migration`.

## Exact files to touch

- The 21 view files listed above (mechanical edit at each of the 48 sites).
- `DOSBTSTests/StyleGuardTests.swift` — new Rule 9 test.
- `CLAUDE.md` — delete the sentence fragment "System `Section(header: Label(...))` headers (Settings, Statistics) are not yet migrated — tracked follow-up." from the surface-chrome bullet (it becomes false on merge).
- `CHANGELOG.md` — `Changed` entry (headers are user-visible).

## Implementation steps (in order)

1. **Build the authoritative hit list first** (line numbers here WILL drift):
   ```bash
   grep -rn "header: {" App/Views --include="*.swift"
   ```
   Expect 48. If materially different, re-scout before editing.
2. **Migrate each site**: append `.dosHeader()` to the header's content view:
   ```swift
   } header: {
       Label("Disclaimer", systemImage: "exclamationmark.shield").dosHeader()
   }
   ```
   Color rules (from the modifier's doc comment — "the color carries section semantics"):
   - Default (no argument) for ordinary sections — this is almost all of them.
   - Sections that ALREADY carry a semantic `foregroundStyle` keep the semantics **through the parameter**: `SensorDetailView:72` becomes `.dosHeader(AmberTheme.cgaRed)` and the now-redundant `.foregroundStyle(AmberTheme.cgaRed)` line is deleted (dosHeader sets foregroundStyle itself — stacking both leaves a dead line).
   - AI-related sections (`AISettingsView`, AI blocks in `FoodPhotoAnalysisView`) use `.dosHeader(AmberTheme.cgaCyan)` **only if** the section header is currently cyan-styled or the screen's other chrome uses the cyan AI framing (check each; when in doubt, default `amberDark`).
3. **Add Rule 9 to `StyleGuardTests.swift`.** The existing `Rule`/`scan()` machinery is **line-based** and cannot express "a `header: {` line NOT followed by `.dosHeader(`". Write a bespoke test instead (same file, after `rule8_...`), reusing `swiftFiles(in:)` + `relativePath(of:)` + `report(_:)`:
   ```swift
   @Test("Rule 9 — Section headers use .dosHeader()")
   func rule9_sectionHeadersUseDosHeader() throws {
       var hits: [StyleGuardTests.Hit] = []
       for file in Self.swiftFiles(in: "App") {
           let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
           for (i, line) in lines.enumerated() where line.contains("header: {") && !Self.isCommentLine(line) {
               // window: the header line itself + the next 4 lines must mention .dosHeader(
               let window = lines[i ..< min(i + 5, lines.count)]
               if !window.contains(where: { $0.contains(".dosHeader(") }) {
                   hits.append(.init(/* match existing Hit init shape */))
               }
           }
       }
       #expect(hits.isEmpty, Comment(rawValue: Self.report(hits)))
   }
   ```
   Adapt mechanically to the actual `Hit` initializer and helper signatures in the file (read them first — do not invent fields). **The exemption list starts EMPTY** — the goal is zero exceptions, unlike Rule 3's sanctioned sites. Scope is `"App"` only (`Library`/`Widgets` don't build List sections with this pattern; keep the scan tight).
4. **Run Rule 9 BEFORE migrating** (it should report exactly the 48 sites — this proves the test sees what the grep sees), then migrate, then run again → zero hits. This before/after is the guard's own validation; note both counts in the PR description.
5. **Visual verification pass** (headers are the one place iOS applies its own List styling, and iOS 26 ignores several appearance proxies — CLAUDE.md documents this class of surprise): boot the simulator, screenshot every touched screen (xcodebuild-mcp `screenshot` tool, or `xcrun simctl io booted screenshot`): Settings hub → each of the 6 categories (incl. drilling into Alarm, Insulin, Sensor Detail, About, AI, Nightscout, Bellman, Calibration, Apple Export, Health Import), Lists tab → Statistics section, Add-flow sheets (UnifiedFoodEntry, FoodPhotoAnalysis), Calibration views. Headers must render 12pt uppercase mono amberDark (or their semantic color) on every screen — compare against `RatioLabView`/`DigestView` which already use `.dosHeader` as the reference look.
6. CHANGELOG `Changed` entry: `- Settings, statistics, and entry-sheet section headers now use the canonical DOS header style` (append the new Linear id). Update CLAUDE.md per above.
7. Both target builds + full suite; PR.

## Cases a weaker model would miss

1. **Grep for `header: {`, not `Section(header:`.** The CLAUDE.md sentence describes the pattern loosely; the argument-label form has zero hits in this codebase. A model that greps the literal CLAUDE.md phrase concludes "already done" and closes the task wrongly.
2. **`.dosHeader()` REPLACES `foregroundStyle`, it doesn't compose with it.** The modifier sets `foregroundStyle(color)` internally; leaving an existing `.foregroundStyle(...)` after it (or before it) creates order-dependent dead code. Semantic colors move INTO the parameter (`SensorDetailView:72` cgaRed case).
3. **Do not convert `Label` to `Text`.** The icons are load-bearing navigation aids in Settings; `.dosHeader()` on a `Label` styles text and tints the icon via foregroundStyle — exactly the desired result. A "cleaner" Text-only rewrite is a scope violation and a visual regression.
4. **The line-based `Rule` machinery cannot express Rule 9** — the ban is "header closure WITHOUT dosHeader nearby", a negative cross-line condition. Forcing it into the `Rule` struct produces either 0 hits forever (useless) or bans the closure form entirely (breaks the 48 fixed sites). The bespoke windowed test is the design; the 4-line look-ahead window covers every real site shape found (`Label` on the next line, sometimes with a second modifier line — e.g. multiline Labels in SensorDetailView).
5. **The window size has a known edge**: a header whose content spans >4 lines before any modifier would false-positive. If step 4's post-migration run reports a false positive, widen the window for that shape rather than adding an exemption — exemptions are for sanctioned violations, not scanner limits.
6. **iOS section-header default casing**: system List headers auto-uppercase/gray small text; after `.dosHeader()` the explicit `.textCase(.uppercase)` + font override wins, but **verify on-device rendering per screen** (step 5) rather than trusting the modifier — the repo has documented iOS 26 cases where appearance layers silently ignore overrides (`dosNavigationTitle` exists precisely because `.navigationTitle` styling is ignored).
7. **`FoodPhotoAnalysisView` and `UnifiedFoodEntryView` are sheets in the entry flow** — they're included in the 48 even though CLAUDE.md's note only names "Settings, Statistics". Migrating only the named screens leaves Rule 9 failing on the rest; the guard forces the honest full sweep. (That's the point of writing the guard first.)
8. **Don't touch `Library/` or `Widgets/`** — `.dosHeader` already lives in shared `DOSSurfaces.swift`; no token or modifier changes are needed. If a header site seems to need a NEW color, that's an `AmberTheme` conversation, not this PR (PORT → SKIP → EVALUATE flow in CLAUDE.md).
9. **Statistics screen**: `StatisticsView.swift` sits under `App/Views/Lists/` (not Settings/) — a Settings-only file sweep misses its 3 sites.

## Acceptance criteria

1. Pre-migration: bespoke Rule 9 reports the same site count as `grep -rn "header: {" App/Views --include="*.swift" | wc -l` (expected 48; both numbers recorded in the PR).
2. Post-migration: Rule 9 → zero hits; full suite green (`StyleGuardTests` rules 1–8 must also stay green — the edit adds no banned constructs); both target builds succeed.
3. `grep -rn "header: {" App/Views --include="*.swift" | wc -l` is UNCHANGED pre/post (the closures remain; only content styled) — proving no Section restructuring happened.
4. Screenshots of every touched screen show the canonical header look; the SensorDetail connection-error header is still red (`cgaRed` via parameter).
5. `grep -rn "dosHeader" App/Views --include="*.swift" | wc -l` ≥ 48 + the pre-existing usages.
6. CLAUDE.md no longer claims the migration is pending; CHANGELOG `Changed` entry present.

## Bookkeeping

Create + link the Linear issue; commit `style(chrome): migrate all Section headers to .dosHeader + StyleGuard Rule 9`. This closes the last open item from the DMNC-1216 surface-chrome convergence.
