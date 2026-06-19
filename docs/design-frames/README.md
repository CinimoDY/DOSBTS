# Design Frames

Committed PNG snapshots of Figma design frames, used as durable design records and as the no-MCP fallback for implementation sessions.

Each Figma-driven feature commits its frame snapshot and companion spec here in the same PR that ships the feature.

## When a snapshot is required

A snapshot is required whenever a Figma frame is used as the design source-of-truth (dense or net-new screens). Small/incremental prose-driven changes do not need a snapshot.

## Naming convention

```
<DMNC-NNN>-<screen-slug>[-<variant>].png
<DMNC-NNN>-<screen-slug>[-<variant>].spec.md
```

Examples:
- `DMNC-1050-overview-chart.png` + `DMNC-1050-overview-chart.spec.md`
- `DMNC-1071-meal-entry-modal-empty-state.png` + `DMNC-1071-meal-entry-modal-empty-state.spec.md`

Use the same issue prefix for the PNG and the spec. If one issue produces multiple frames, add a short screen slug after the issue prefix.

## PNG export and optimisation

1. In Figma, select the target frame → Export → PNG at 2× (for Retina fidelity).
2. Optimise with the manual Pillow script before committing:
   - See `docs/solutions/best-practices/png-screenshot-optimization-via-pillow-20260422.md` for the exact command.
   - Typical reduction: 40–60% without visible quality loss.
3. Commit the optimised PNG alongside the companion spec in the same commit.

## Companion spec format (`*.spec.md`)

The spec must be self-sufficient: an implementation session with no Figma MCP access should be able to produce a pixel-close result from the PNG + spec alone.

```markdown
# <Screen Name> — Design Spec

**Issue:** DMNC-NNN
**Figma frame:** <figma.com/... URL>
**Frame size:** <width>×<height> pt

## Layout

<Describe the major layout regions: top/bottom bars, content stacks, insets.>

## Components and tokens

| Element | Token / value | Notes |
|---------|---------------|-------|
| Background | `AmberTheme.dosBlack` | Full screen |
| Heading text | `DOSTypography.displayMedium` | amber |
| Card fill | `AmberTheme.cardBackground` | |
| Border | `AmberTheme.dosBorder` | 1pt |
| ... | ... | ... |

## Key measurements

| Measurement | Value |
|-------------|-------|
| Horizontal padding | `DOSSpacing.md` (16pt) |
| Row height | 44pt min |
| ... | ... |

## States

<Describe any variant states visible in the frame (empty, loading, error, etc.) and how they differ.>

## Platform constraints satisfied

- [ ] Nav title uses `dosNavigationTitle`
- [ ] Persistent bar uses `safeAreaInset(edge: .bottom)`
- [ ] No nested sheets
- [ ] No real white
- [ ] Font sizes from `DOSTypography` only
- [ ] `NavigationStack` (not `NavigationView`)
```

## What lives here vs elsewhere

- **This directory** — PNG snapshots and companion specs, one pair per Figma-driven feature.
- **`docs/design-system.md`** — The full Prototype-Driven Design Workflow procedure and the complete token reference.
- **`CLAUDE.md`** — The concise in-session summary (when to use frames, the loop, the platform checklist).
- **Figma** — The authoritative live design source (DMNC-1119 DOSBTS app file). Snapshots here are a durable record, not a substitute for the live file.
