# DMNC-1220 — Motion & Rhythm Sweep: AnimationTokens + Spacing Grid

**Date:** 2026-07-02  
**Branch:** claude/dmnc-1220

## What changed

Swept all 18 raw animation duration sites out of `App/` and `Widgets/` and tokenised every spacing outlier, making `AnimationTokens` the single authority for all motion values in the codebase.

### New tokens added (`Library/DesignSystem/AnimationTokens.swift`)

| Token | Value | Replaces |
|---|---|---|
| `easeReveal` | `.easeOut(0.25s)` | raw `.easeOut(duration: 0.25–0.3)` on reveal/cascade animations |
| `easeSnap` | `.easeOut(0.15s)` | raw `.easeOut(duration: 0.15)` for quick collapse/cancel |
| `highlightFade` | `.easeOut(1.2s)` | raw `.easeOut(duration: 1.2)` one-shot row highlight fade |
| `blink` | `.easeInOut(0.4s).repeatForever()` | raw `.easeInOut(duration: 0.5).repeatForever()` cursor blink |
| `gestureProgress(duration:)` | `.linear(duration:)` | press-and-hold fill (functional, not a fixed duration) |

### Animation sites tokenised (18)

- `DOSButtonStyle` — spring(0.2/0.9) → `snappy`
- `HoldToCommitProgress` — linear(holdDuration) → `gestureProgress`, easeOut(0.15) → `easeSnap`
- `LoadingView` — easeInOut(0.5).repeatForever() → `blink`
- `DigestView` — easeOut(0.3) → `easeReveal`, easeInOut(1.4).repeatForever() → `pulse`
- `WhatsNewView` — easeOut(0.25) × 2 → `easeReveal`, easeOut(0.3) → `easeReveal`
- `TightControlToast` — easeOut(0.25) → `easeReveal`
- `AddedEntryHighlighter` — easeOut(1.2) × 2 → `highlightFade`
- `StagingPlateRowView` — linear(0.18) → `easeStandard`
- `CombinedEntryEditView` — linear(0.18) → `easeStandard`
- `FoodPhotoAnalysisView` — linear(0.18) → `easeStandard`
- `UnifiedFoodEntryView` — easeInOut(0.3) → `easeStandard`, linear(0.2) → `easeStandard`, linear(0.15) → `easeSnap`
- `GlucoseView` — easeInOut(0.8).repeatForever() → `pulse` (converges to 1.2s per spec)

### Spacing outliers onto 8px grid

- `6pt × 12 sites` → `DOSSpacing.xxs` (4pt) — tight chip/label/icon spacings in GlucoseView, AddInsulinView, SensorLineView, DigestView, StatisticsView, GlucoseDisplayCategoryView, SystemAboutCategoryView, GlucoseActivityWidget, GlucoseWidget (×5)
- `FiguresLoadingView(dotSize: 10, spacing: 7)` → `(dotSize: DOSSpacing.xs, spacing: DOSSpacing.xxs)` — in DigestView and FoodPhotoAnalysisView
- `AddInsulinView spacing: 20` → `DOSSpacing.lg` (24)

## Why

Part of WP-G (DMNC-1220) under the DMNC-1211 visual-consistency umbrella. The goal is zero raw animation durations outside `Library/DesignSystem/` so any future timing tweak has a single edit point. The `pulse` convergence rationalises three different "slow breathing loop" values (0.8/1.2/1.4s) into one.

## Design choices

- `highlightFade` kept as `.easeOut` (not the looping `pulse`) because `AddedEntryHighlighter` is a one-shot fade, not a loop — using `pulse` here would have made the row glow loop forever.
- `blink` rounds 0.5s down to `durationLong` (0.4s) — imperceptible difference on a cursor blink.
- `gestureProgress(duration:)` is a factory not a constant because the duration must match `HoldToCommitProgress.holdDuration` exactly (functional constraint, not a display preference).
- 6pt spacing → `.xxs` (4) rather than `.xs` (8) throughout: all occurrences are tight internal groupings (icon+value, chip rows, caption-below-control) matching the DOSSpacing.xxs "icon-to-label" description.

## Acceptance verified

- `grep -rnE '\.(easeIn|easeOut|easeInOut|linear)\(duration:|spring\(response:' App Widgets` → 0 results ✓
- `AnimationTokensTests` — all 14 tests pass including 6 new smoke tests for the new tokens ✓
- Both `DOSBTSApp` and `DOSBTSWidget` build succeeded ✓
