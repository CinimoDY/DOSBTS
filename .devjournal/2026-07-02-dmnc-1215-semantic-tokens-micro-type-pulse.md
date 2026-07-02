# DMNC-1215: Semantic Tokens, Micro Type Scale, Pulse Animation (WP-B)

**Date:** 2026-07-02
**Branch:** claude/dmnc-1215
**Part of:** DMNC-1211 (visual-consistency refactor umbrella)

## What changed

Purely additive token additions across three design-system files. No view or call-site changes. All tokens consumed by the WP-C…H sweeps.

### AmberTheme.swift — Semantic Tiers

Added 8 pre-blended tokens under a new `// MARK: - Semantic tiers` section:

| Token | Recipe | Intent |
|-------|--------|--------|
| `borderFaint` | amberDark @ 0.3 | Grid lines, separators |
| `borderSubtle` | amberDark @ 0.4 | Quiet card hairlines, stat cell dividers |
| `borderStrong` | amberDark @ 0.6 | Emphasized dim strokes |
| `textFaint` | amberDark @ 0.7 | Helper text below amberDark |
| `surfaceTint` | amber @ 0.04 | Faint wash behind stat cells |
| `scrim` | dosBlack @ 0.7 | Modal/overlay dimming |
| `scrimHeavy` | dosBlack @ 0.95 | Near-opaque toast backdrop |
| `inkOnAmber` | dosBlack (alias) | Ink on solid amber fills (intent-named) |

Rule enforced by comment: never write `.opacity()` on palette tokens in views — use these instead.

### DOSTypography.swift — Micro Scale

Added 4 tokens filling the gap between `caption` (12pt) and `tabBar` (10pt):

- `micro` — 9pt regular (smallest legible; stat help captions, axis micro-labels)
- `microLabel` — 10pt medium (ALL-CAPS stat/grid labels; pair with `.tracking(0.6)`)
- `label` — 11pt medium (chip labels, hero-stat captions, IOB sublabels)
- `numeral` — 24pt semibold (stat-card values, stepper display digits)

Only ≥3-usage role-shaped sizes get names per spec; 13/14/18/22 stay `mono(size:weight:)`.

### AnimationTokens.swift — Pulse

Added under new `// MARK: - Pulse` section:

- `durationPulse: Double = 1.2` — rationalizes 0.8/1.2/1.4 s loading-pulse singletons
- `pulse` — `Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)`

### Tests (12 new pins in DesignTokenPinTests, 3 in AnimationTokensTests)

- Semantic tier pins include **alpha-channel verification** (pattern extension of the existing RGB-only approach)
- 4 micro-type font pins via `Font` equality
- `durationPulse == 1.2` value pin
- `durationPulse > durationLong` ordering invariant (ensures pulse is slower than transitions)
- Pulse smoke test (compiles and runs without crash)

All 50+ pin tests pass on iPhone 17 Pro simulator (iOS 26.5).

### Docs

- `docs/design-system.md`: semantic tier table, updated font scale table with new tokens, pulse row in AnimationTokens table
- `CLAUDE.md`: updated typography API one-liner, added semantic tier bullet to Key colors

## Key decisions

**Pre-blended vs inline opacity:** The spec required no `.opacity()` calls on palette tokens in views. Pre-blending in `AmberTheme` centralizes the intent and lets drift-guard tests catch changes.

**`inkOnAmber = dosBlack` (alias, not new color):** The intent is to survive a future `Color.black` guard. The name encodes usage context (ink on amber fill); the value is identical to `dosBlack`.

**`microLabel` vs `tabBar`:** Both are 10pt medium but `tabBar` carries tab-bar semantics. `microLabel` fills the ALL-CAPS stat-label role without overloading tab semantics.

**No `cgaYellow`:** Spec explicitly excludes it — zero consumers.
