# DMNC-791: Design Token Drift Guard + Prototype Workflow Docs

**Date:** 2026-06-19
**Branch:** claude/dmnc-791
**PR:** https://github.com/CinimoDY/DOSBTS/pull/60

## What changed

### U1 — Token drift-guard test (`DOSBTSTests/DesignTokenPinTests.swift`)

New test suite with 31 tests pinning the hand-mirrored eiDotter tokens:
- **14 color pins** — all named static `AmberTheme` properties via `UIColor(Color)` + `getRed(_:green:blue:alpha:)` at ±0.001 tolerance. Added `amberDark`'s previously-omitted blue channel (= 0.0), plus all tokens added since the original CaptionLegibilityTests were written (`iobBolus`, `iobBasal`, `cgaMagenta`, etc.)
- **8 typography pins** — `DOSTypography` members via `Font` equality (`DOSTypography.x == Font.system(size:weight:design:)`). `glucoseHero` includes the `.monospacedDigit()` modifier.
- **8 spacing pins** — `DOSSpacing` constants via `CGFloat` equality.
- **1 comment block** — explains local-pin scope, eiDotter source, PORT/SKIP/EVALUATE flow, and the DMNC-801 migration trigger.

Manual `project.pbxproj` registration (3 entries: PBXFileReference, PBXGroup, PBXSourcesBuildPhase) — the tests target is not file-system-synchronized.

**Key decision:** Font equality (`==`) instead of `debugDescription.contains()` — the latter is fragile and undocumented; equality is the natural contract for `Equatable Font`.

### U2 — Docs reconcile + workflow

`docs/design-system.md`:
- **Color table** — corrected 5 hex values (`amberDark` #9a5700 not #CC8C00; `cgaGreen` #55ff55 not #00AA00; `cgaRed` #ff5555; `cgaCyan` #55ffff; `dosBlack` #000000; `amberLight` #fdca9f; `amberMuted` #555555). Removed nonexistent `dosGray`. Added `cgaMagenta`, `iobBolus`, `iobBasal`.
- **Typography table** — removed nonexistent `title`/`header`/`data` rows; added `displayMedium`, `bodyLarge`, `tabBar`; fixed `button` (17pt semibold, not 15pt medium); fixed `caption` (12pt, not 13pt).
- **iOS compat** — updated iOS 15.0 → iOS 26.0.
- **New section** — "Prototype-Driven Design Workflow" (provisional): when to use frames vs prose, the frame→implement→verify loop, no-MCP fallback, token consumption flow (PORT/SKIP/EVALUATE), platform constraints checklist.

`CLAUDE.md`: Added substantive workflow summary to the Design System section — actionable without opening another file.

### U3 — Snapshot convention (`docs/design-frames/README.md`)

New file establishing:
- When a snapshot is required (Figma-driven features only)
- Naming convention: `DMNC-NNN-screen-slug.png` + `.spec.md`
- PNG export at 2× + Pillow optimisation
- Companion spec template (frame size, component/token table, key measurements, states, platform checklist)
- What lives here vs elsewhere

## Why

`docs/design-system.md` was drifted on both the color table (5+ wrong hex values, one nonexistent token `dosGray`) and the typography table (3 nonexistent members `title`/`header`/`data`, wrong sizes/weights). Without a test, these could silently rot further.

The drift-guard test catches accidental `AmberTheme.swift` edits before they ship. The workflow docs establish the Figma-first handoff pattern so future dense-screen work has a defined process.

## Tests

All 31 `DesignTokenPinTests` pass. Full suite passes (no regressions). Tests run via `xcodebuild -scheme DOSBTSApp test`.
