# DMNC-1218 — App Font Sweep: Zero Raw .font(.system) Outside DOSTypography

**Date:** 2026-07-02  
**Branch:** claude/dmnc-1218  
**Part of:** DMNC-1211 (visual consistency refactor umbrella)

## What changed

Swept every `App/` and `Library/` Swift file for raw `.font(.system(...))` calls and replaced them with DOSTypography tokens. 52 sites across 18 files.

**Mapping applied:**

| Raw | Token |
|-----|-------|
| `size: 9, weight: .regular` | `DOSTypography.micro` |
| `size: 10, weight: .medium` | `DOSTypography.microLabel` |
| `size: 11, weight: .medium` | `DOSTypography.label` |
| `size: 12` | `DOSTypography.caption` |
| `size: 24, weight: .semibold` | `DOSTypography.numeral` |
| `size: 56, weight: .bold` | `DOSTypography.mono(size: 56, weight: .bold)` |
| `size: 18/13/14/20/22/36/48/64`, or non-standard weight | `DOSTypography.mono(size:weight:)` |

Also converted 5× `.font(.caption)` system text styles in `AlarmSettingsView.swift` → `DOSTypography.caption`. These lose Dynamic Type scaling but are identical at the default size (noted in PR body).

## Rendering neutrality

`App.swift` already applies `.fontDesign(.monospaced)` at root, so every site that omitted `design: .monospaced` was already rendering as mono. Converting to tokens makes the intent explicit but changes nothing visually. Weight was matched exactly in every case — anything that wasn't an exact token match (e.g. 11pt .semibold, 9pt .medium) uses `mono(size:weight:)`.

One interesting case: `EntryGroupListOverlay`'s `.font(.system(size: 20))` icon font became `DOSTypography.bodyLarge` — that token is 20pt .regular .monospaced, a perfect match.

## Files touched

`StepperField.swift`, `StatisticsView.swift`, `GlucoseStatusBar.swift`, `ItemBarcodeScannerView.swift`, `AddInsulinView.swift`, `BarcodeScannerView.swift`, `UnifiedFoodEntryView.swift`, `FoodPhotoAnalysisView.swift`, `StagingPlateRowView.swift`, `ChartReportViews.swift`, `EventMarkerLaneView.swift`, `ChartView.swift`, `EntryGroupListOverlay.swift`, `GlucoseView.swift`, `AlarmSettingsView.swift`, `AppleIcon.swift`, `AmberChip.swift`, `StatsComponents.swift`

## Verification

- `grep -rn '\.font(\.system(' App Library` → 0 results ✓
- System text style grep → 0 results ✓  
- Both targets (`DOSBTSApp`, `DOSBTSWidget`) build clean ✓
- All tests pass (`** TEST SUCCEEDED **`) ✓
- No CHANGELOG entry (rendering-neutral) ✓
