---
date: 2026-07-02
issue: DMNC-1221
title: Widget unification — delete WidgetColors, consume AmberTheme directly
tags: [design-system, widgets, refactor]
---

## What changed

Deleted `WidgetColors` (the 8-token hand-mirror of AmberTheme that predated fileSystemSynchronized) and rewired all ~83 widget call sites to `AmberTheme` directly.

### Key insight

The widget target already compiled all of `Library/` via `fileSystemSynchronized` — `DataStaleness` extensions in the old `WidgetDesignSystem.swift` proved this. `WidgetColors` was a maintenance liability: only 8 of AmberTheme's 18+ tokens were mirrored, and new tokens added to AmberTheme (semantic tiers, IOB colours) were silently absent from widgets. Parity is now compile-time.

### WidgetDesignSystem.swift

- Deleted: `WidgetColors` enum (all 8 hand-copied hex definitions)
- Kept: `WidgetFonts` — widget-scale type roles (glucoseHero 44/52 vs app 60) expressed via `DOSTypography.mono(...)`. Widget sizes legitimately differ from app scale.
- Updated: `phosphorGlow` default changed from `WidgetColors.amber` → `AmberTheme.amber`
- Updated: `DataStaleness` colour extensions → `AmberTheme` tokens
- Deleted: `Library/Assets.xcassets/WidgetBackground.colorset` (pure black, replaced by `AmberTheme.dosBlack`)

### Sweep across widget files

- 83× `WidgetColors.` → `AmberTheme.`
- 60× `.foregroundColor(` → `.foregroundStyle(` (SwiftUI deprecation alignment)
- `amberDark.opacity(0.3)` instances → `AmberTheme.borderFaint` (semantic tier, per CLAUDE.md "never write .opacity() on palette tokens")
- `amberDark.opacity(0.4)` → `AmberTheme.borderSubtle`

### Visible fixes

- **Live Activity / Dynamic Island**: was rendering SF Pro body font because the widget extension has no root `.fontDesign(.monospaced)` (App.swift applies that only to the app target). Fixed by changing `GlucoseActivityWidget.swift:53` `.font(.body).bold()` → `.font(WidgetFonts.mono(size: 17, weight: .bold))`.
- **Lock-screen rectangular widget metadata** (TIR, IOB, timestamp row): was rendering `.secondary` system colour (grey). Changed to `AmberTheme.amberDark` to stay within the DOS amber palette.
- **Moon icon overlays** (night profile indicator): raw `.font(.system(size: 10))` → `WidgetFonts.mono(size: 10)` for consistency.

### CLAUDE.md update

Updated the "Widget target has separate design system" architecture bullet to reflect the new reality: widgets consume AmberTheme/DOSTypography directly; WidgetFonts holds widget-scale roles only.

## What wasn't changed

- `WidgetFonts` size values — widget displays legitimately use different type sizes than the app hero
- Shadow/glow `.opacity()` calls (e.g. `.amber.opacity(0.4)` for sparkline shadow) — these are visual effects, not semantic colour tokens; no semantic tier exists for them
- `amberDark.opacity(0.1)` in large-widget no-data placeholder — no semantic tier at 0.1 opacity; kept as-is
