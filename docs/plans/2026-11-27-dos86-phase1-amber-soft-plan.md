# DOS-86 phase 1 — readable dim text (amberSoft) — DMNC-1662

**Goal:** every piece of dim **text** in DOSBTS passes WCAG AA (4.5:1) on black, by giving dim text its own token
`amberSoft` (#B87C1A, 5.82:1) instead of reusing the decoration token `amberDark` (#9A5700, 3.67:1).
Source: eiDotter DOS-86 (`../dos-86/tokens/dos-86.tokens.json` → `color.phosphor.amberSoft`, role `textDim`;
eiDotter `src/tokens/theme.dos-86.tokens.json` → `text.secondary`).

**Branch:** `feat/dos86-amber-soft` off `main`. **Linear:** DMNC-1662 (parent DMNC-1645).

## Global constraints

- `amberDark` keeps its value (#9A5700). Do NOT brighten it. `CaptionLegibilityTests.amberDarkStaysDim`
  (`DOSBTSTests/AmberChipTests.swift:73`) must keep passing unchanged.
- Strokes, fills, backgrounds, dividers, card strokes, chart data encodings and stand-alone icons **stay amberDark**:
  non-text graphics need only 3:1, and amberDark (3.67:1) passes. This is the decoration role.
- No new `.opacity()` on palette tokens in views (StyleGuard). No raw `Color(red:)` outside `AmberTheme.swift`.
- Out of scope: the stale-tier yellow (`stalenessColor`), greys (`cardBackground`, `dosBorder`, `amberMuted`: phase 2,
  DMNC-1663), glow and scanlines (phase 3, DMNC-1664). Do not add `cgaYellow` in this PR; phase 2 or a later PR adds it when it has a user.
- Intended differences from DOS-86 (Dom, 2026-11-27, DMNC-1665): pure #000000 screen, bright cyan #55FFFF for
  info/AI, SF Mono everywhere. Don't change any of them.

## Tasks

### 1. Token
- [ ] `Library/DesignSystem/AmberTheme.swift`, after `amberLight`: add
  ```swift
  /// eiDotter DOS-86 `amberSoft` / theme `text.secondary`: #B87C1A — dim TEXT (5.82:1 on black, passes AA).
  /// The dimmest amber that is legal for running text. `amberDark` stays the decoration step (borders,
  /// strokes, disabled glyph art, chart encodings) — 3.67:1, fine for graphics (3:1), too dark for text.
  public static let amberSoft = Color(red: 184.0 / 255.0, green: 124.0 / 255.0, blue: 26.0 / 255.0)
  ```
- [ ] Update the doc comment on `amberDark` (currently "Secondary text, dimmed states (18pt+ only)") to say
  "Decoration: borders, strokes, disabled glyph art, chart encodings. Not for text — use `amberSoft`."
- [ ] `textFaint`: leave its VALUE (amberDark @0.7; it is pinned at `DesignTokenPinTests.swift:197`) but re-document it as
  **decoration only** (chart fade tiers). Its **text** sites move to `amberSoft` (task 3).

### 2. Tests first
- [ ] `DOSBTSTests/DesignTokenPinTests.swift`: add `amberSoftColorPin` next to `amberLightColorPin` (line 32), same shape
  and tolerance, pinning 184/124/26.
- [ ] `DOSBTSTests/AmberChipTests.swift` `CaptionLegibilityTests`: add
  `@Test("amberSoft on black meets AA for normal text (>=4.5:1)")`, using the same token-resolve and `contrastOnBlack` pattern as `amberMeetsAA`.
  Update the suite doc comment: amberSoft is the AA dim-text step.
- [ ] Run them and see `amberSoftColorPin` fail before task 1 lands, if you do it test-first. Then pass.

### 3. Call-site sweep (the main work; about 136 amberDark references, about 11 textFaint)
Get the list with: `grep -rn "amberDark\|textFaint" App Widgets Library --include='*.swift' | grep -v AmberTheme.swift`

**Rule. Open every site and judge what is actually drawn:**

| Drawn thing | Token |
|---|---|
| `Text`, `Label` (title), `TextField` prompt, tab-bar title, any glyph string used as text (`"—"`, `"·"`, `"▸"`) | **amberSoft** |
| A ternary on text, e.g. `isSelected ? amber : amberDark` → keep amber for selected, use **amberSoft** for unselected | **amberSoft** |
| A colour-returning helper whose result colours text (e.g. `rowColor`, `timestampColor`, `valueColor:` args, `RatioLabView:426/509`, `FoodImpactView:82-85`, `SettingsConnectionsView:170`, `SensorLineView:201-213`, `Widgets/WidgetDesignSystem.swift:46 timestampColor .fresh`) | **amberSoft**. If a helper colours both text and a shape, prefer amberSoft |
| `.stroke`, `.fill`, `.background`, `Divider().background`, `.dosCard(stroke:)` | keep amberDark |
| A colour inside `Chart{}` marks, `Canvas` data drawing, or `AmberTheme.amberDark.opacity(x)` fades (Lab marks, sweep fades, `LabOverlayMarks:85/148/365/366/371`, `LabSweepView:653/655`, `GlucoseWidget:516`) | keep (data encoding) |
| A stand-alone SF Symbol that is not text (e.g. `CombinedEntryEditView:305` clock icon, `AppleIcon:94`) | keep amberDark, **unless** it sits in a row as a text glyph next to amberSoft text and would look mismatched. Then use amberSoft, and note it |
| `EventMarker.swift:35 .basal` colour | colours the basal chip label `10Ub` (text) **and** the outline syringe. Check `DOSBTSTests/EventMarkerTypeTests.swift`; if a test pins it, update the pin. → **amberSoft** |
| `LabLegendItem(color:)` (`LabChrome.swift:15`) | colours glyph + label text together. If the colour matches a chart mark colour, keep it so the legend matches the marks. Note each case |

Specific sites worth naming:
- [ ] `Library/DesignSystem/Modifiers/DOSSurfaces.swift:78` — `dosHeader(_ color: Color = AmberTheme.amberDark)`
  → default `AmberTheme.amberSoft`. Update its doc comment ("`amberSoft` default"). This changes ~48 section headers app-wide
  (12pt text that fails AA today). The biggest visible change.
- [ ] `App/DesignSystem/DOSTabBarAppearance.swift:40-41` — the normal (unselected) tab icon + title → amberSoft (both, so the tab stays one colour).
- [ ] `Library/DesignSystem/Components/StatsComponents.swift:44,50,80,88,187` — unit, label and help text → amberSoft
  (`:88` is `textFaint` on help text → amberSoft).
- [ ] Widgets: `GlucoseWidget.swift`, `GlucoseActivityWidget.swift`, `SensorWidget.swift`, `TransmitterWidget.swift` text sites → amberSoft.
- [ ] `StyleGuardTests`: check whether any rule mentions amberDark or textFaint usage counts, and keep it green.

Write every judgment call that isn't obvious into `IMPLEMENTATION_NOTES.md` (file:line → choice → why).

### 4. Docs
- [ ] `docs/design-system.md`: colour table — add `amberSoft #B87C1A | Dim text (AA, 5.82:1)` and re-label `amberDark` as
  decoration. In the Component Standard checklist (around line 219), change "`amberDark` reserved for intentional dimming / disabled /
  decorative strokes" to "`amberSoft` for dim text; `amberDark` for decoration only (strokes, disabled glyph art, chart encodings)".
- [ ] `docs/design-system.md`: add a short section **"Intended differences from eiDotter DOS-86"** (Dom, 2026-11-27, DMNC-1665):
  pure #000000 screen (OLED), bright cyan #55FFFF for info/AI, SF Mono everywhere (not JetBrains Mono).
- [ ] `CLAUDE.md` → Design System → Key colors: add the line `- **Dim text:** #b87c1a → AmberTheme.amberSoft (DOS-86 textDim; AA)`,
  change the **Dim amber** line to `(decoration: borders, strokes — not text)`, and add one line under Rules:
  `- Intended differences from DOS-86: pure black screen, bright cyan info, SF Mono (DMNC-1665) — don't "fix" them.`
- [ ] `CHANGELOG.md` → `## [Unreleased]` → `### Changed`:
  `- Dim text throughout the app — section headers, labels, units, captions and widget timestamps — is a little brighter so it is easier to read, using the readable dim amber from the eiDotter DOS-86 theme — DMNC-1662, PR #NN`

## Verification
- [ ] Build both schemes (DOSBTSApp, DOSBTSWidget) on your assigned simulator UDID. Redirect logs to a file and grep for
  `** BUILD SUCCEEDED **`. Don't pipe into `tail`, which throws away the exit code.
- [ ] Run tests: `-only-testing:DOSBTSTests/DesignTokenPinTests -only-testing:DOSBTSTests/CaptionLegibilityTests -only-testing:DOSBTSTests/StyleGuardTests -only-testing:DOSBTSTests/EventMarkerTypeTests`
  (`@Suite` type names; a file name passes vacuously with 0 tests. Check that the test count is > 0). Then run the full `DOSBTSTests` suite once.
- [ ] Take simulator screenshots, before (on `main`) and after: Overview, Settings hub, Settings › Alarms & Alerts, Digest, Lists › Statistics.
  Save them under `$SCRATCH/dos86-phase1/` and list the paths in the PR body.

## Ship
- [ ] Commit this plan file too (`docs/plans/2026-11-27-dos86-phase1-amber-soft-plan.md`).
- [ ] Before opening the PR, move the `IMPLEMENTATION_NOTES.md` content into the PR body and `git rm` the file.
- [ ] PR title: `feat(design): readable dim text — amberSoft from eiDotter DOS-86 (DMNC-1662)`.
