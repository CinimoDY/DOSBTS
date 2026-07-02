# DMNC-1216: Build `.dosCard()` + `.dosHeader()` and consolidate cards/headers

**Date**: 2026-07-02
**Branch**: claude/dmnc-1216
**Issue**: [DMNC-1216](https://linear.app/lizomorf/issue/DMNC-1216/wp-c-build-doscard-dosheader-and-consolidate-cardsheaders) — part of [DMNC-1211](https://linear.app/lizomorf/issue/DMNC-1211) (visual-consistency refactor)

## Summary

The docs promised `.dosCard()` and `.dosHeader()`; neither existed. Cards were
hand-rolled `overlay(Rectangle().stroke(...)) + background` assemblies that
diverged, and section headers diverged several ways. Built the two real
modifiers, adopted them at the genuine card/header sites, pinned the variant
mapping, and rewrote the docs to match reality.

## New file

`Library/DesignSystem/Modifiers/DOSSurfaces.swift` (pure SwiftUI, both targets):

- `enum DOSCardVariant { panel, info, stat, toast }` with **exposed** `fill` /
  `stroke` (so the drift-guard test can assert the mapping):
  - `.panel` → `cardBackground` / `dosBorder` (general warm panels)
  - `.info` → clear / `cgaCyan` (AI/info framing)
  - `.stat` → `surfaceTint` / `borderSubtle` (quiet data cells)
  - `.toast` → `dosBlack` / `amber` (floating overlays/toasts)
- `.dosCard(_ variant:stroke:padding:)` — sharp corners, 1px stroke, variant
  fill. `stroke:` overrides for stateful borders; `padding: nil` defers padding
  to the caller (asymmetric-padding sites).
- `.dosHeader(_ color:)` — 12pt semibold mono, 1.2 tracking, uppercase, **no
  glow** (the docs promised a glow, which would violate the "no glow in list
  rows" perf rule — docs corrected instead).

## Card adoption (all hand-rolled assemblies removed)

- `DigestView.aiInsightCard` → `.dosCard(.info)` (exact match: clear + cyan)
- `StatsComponents.StatCard` → `.dosCard(.stat, padding: nil)` (exact match:
  surfaceTint + borderSubtle; keeps its asymmetric v/h padding)
- `TightControlToast` → `.dosCard(.toast, stroke: cgaCyan, padding: nil)` (keeps
  its cyan accent + phosphor glow shadow)
- `LoggedMealToast` → `.dosCard(.toast, padding: DOSSpacing.sm)` — **convergence**:
  border brightens `amberDark` → `amber`, fill `black@0.95` → `dosBlack`
- `TreatmentBannerView` → `.dosCard(.toast, stroke: bannerBorderColor, padding: nil)`
  — the banner was borderless; it now gains a **state-colored** toast border
  (green for countdown/recovered, amber for rechecking/staleData). New
  `bannerBorderColor` computed off the existing `bannerState` switch, so the
  4-state banner is preserved, not regressed.
- `WhatsNewView.BuildCard` → `.dosCard(.panel, padding: nil)` — **convergence**:
  fill clear → `cardBackground`, stroke `amberDark@0.6` → `dosBorder`

## Header adoption

- `DigestView` "AI INSIGHT" → `.dosHeader(cgaCyan)`, "TIMELINE" →
  `.dosHeader(amber)`. Both were `DOSTypography.caption` (12pt regular) →
  canonical 12pt semibold + tracking + uppercase.

## Deliberate skips / deferrals (documented so a reviewer can veto)

- **Scanner "overlays"** (`BarcodeScannerView`, `ItemBarcodeScannerView`): the
  `Rectangle().stroke(amber, lineWidth: 2)` there is an **empty viewfinder frame**
  (fixed 280×120, no fill, no wrapped content), not a card. `.dosCard()` would
  regress it (1px, adds fill). Left as-is.
- **`EntryGroupListOverlay`**: no card assembly (its only `Rectangle` is the OK
  button's amber fill). Nothing to convert.
- **`CombinedEntryEditView`**: the `Rectangle().stroke` is a **text-field border**;
  sections are divider-separated, not carded. Not a card.
- **System `Section(header: Label(...))` headers** (Settings ×~15 files,
  StatisticsView, ChartReportViews' `HeroStatView` labels): a single,
  already-consistent `Label` family — not the hand-rolled divergent headers
  `.dosHeader()` targets. Converting all ~34 means a Title-Case→UPPERCASE change,
  `amberDark` dimming (below the design system's own 18pt+ amberDark contrast
  guidance at 12pt), and icon-resizing on system list-section headers — a broad
  visual sweep, none of it on the acceptance spot-check surfaces. Deferred as a
  follow-up (the issue explicitly sanctions splitting C1 cards / C2 headers).
  `.dosHeader()` is built + pinned-by-usage + documented, so the follow-up is a
  pure adoption pass. The System & About screenshot confirms these render fine
  as-is.

## Docs

- `docs/design-system.md`: rewrote **Cards** (variant table + rules) and **View
  Modifiers** (accurate inventory). Deleted the promised-but-nonexistent
  `.dosText()` / `.dosData()` / `.dosGlowSmall()` / `.dosTextField()`.
- `CLAUDE.md` Design System section: added the `.dosCard`/`.dosHeader` pointer +
  the "never hand-roll card chrome" rule + the deferred-headers note.

## Verification

- ✅ `xcodebuild ... DOSBTSApp build` — **BUILD SUCCEEDED**
- ✅ `xcodebuild ... DOSBTSWidget build` — **BUILD SUCCEEDED** (DOSSurfaces is shared)
- ✅ `xcodebuild test -only-testing:DOSBTSTests` — **TEST SUCCEEDED** (350+, incl.
  4 new `DOSCardVariant` fill/stroke pins)
- ✅ Simulator spot-check: Overview renders clean; **Daily Digest** confirms all
  three visible adoptions at once — `.stat` StatCards (subtle surfaceTint +
  borderSubtle), `.info` AI-insight card (clear + cyan border), and both
  `.dosHeader`s (AI INSIGHT cyan, TIMELINE amber, canonical uppercase/tracking);
  Settings/System & About render clean.
- ⚠️ What's New `.panel` card and the treatment-banner state-border weren't
  captured **live** (cliclick drag wouldn't scroll the `.plain` list to the
  Changelog row; the treatment banner needs an active hypo cycle to appear).
  Both are verified via build + tests + code review + the identical `.dosCard`
  mechanism proven on Digest.

## Review follow-up (xhigh workflow code review)

The adversarial review confirmed three genuine issues, all fixed in the same PR:

1. **`.toast` fill dropped 5% translucency** — the toasts used
   `Color.black.opacity(0.95)`; my `.toast` variant used opaque `dosBlack`.
   `AmberTheme.scrimHeavy` (dosBlack @ 0.95) is the design system's purpose-built
   toast backdrop and exactly matches the prior value. Changed `.toast` fill →
   `scrimHeavy` (deviates from the issue's literal "dosBlack" spec, but preserves
   behavior and uses the existing token). Pin test + docs updated.
2. **LoggedMealToast border silently brightened** `amberDark` → `.toast`'s default
   `amber`. Added `stroke: AmberTheme.amberDark` to keep the quiet dim border.
3. **TreatmentBannerView sampled `Date()` twice per render** (`bannerContent` and
   the new `bannerBorderColor` each re-read the time-dependent `bannerState`), so
   at the exact expiry instant the border and content could disagree for one
   frame. Resolved `bannerState` once in `body` and threaded it to both
   `bannerContent(for:)` and `bannerBorderColor(for:)`.
4. **TreatmentBanner border was full-bleed** (found in the final report): the
   banner's only horizontal padding is *interior* (before `.dosCard`), and its
   parent `OverviewView` stacks it in a `VStack(spacing: 0)` with no outer
   margin — so the new toast stroke rendered flush against the screen bezels
   (invisible before, when the banner was borderless). Added outer
   `.padding(.horizontal, .md)` (+ `.vertical, .xs`) after `.dosCard` to inset
   it like every other card.

Net effect of the fixes: the toasts and stat cells are now **pixel-preserved**;
the only intended user-visible changes are the Digest section headers, the
treatment-banner state border, and the What's New warm-panel fill (all disclosed
in the CHANGELOG).

Findings intentionally **not** changed:
- **BuildCard → `.panel`** (gains cardBackground fill, dosBorder stroke): the
  disclosed, intended "general warm panel" consolidation for patch-notes cards.
- **`padding:` param bypassed by most callers**: it's the issue-specified API
  (`padding: nil` = caller-managed); the 2 default-padding callers justify it.
- **DigestView header weight/tracking change**: the point of the task.

## Notes

- `DOSSurfaces.swift` lives under `Library/DesignSystem/Modifiers/` (new dir) —
  auto-synced into both targets via `fileSystemSynchronized`, no pbxproj edits.
- The pin tests were appended to the existing `DesignTokenPinTests` suite (per
  the issue) to avoid a new test file + manual pbxproj `PBXSourcesBuildPhase` entry.
