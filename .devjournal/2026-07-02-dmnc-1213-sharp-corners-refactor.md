# DMNC-1213: Harden All Corners to Radius 0

**Date**: 2026-07-02  
**Branch**: claude/dmnc-1213  
**Issue**: [DMNC-1213](https://linear.app/lizomorf/issue/DMNC-1213/wp-a-harden-all-corners-to-radius-0-sharp-dos-corners-no-exceptions)

## Summary

Pure mechanical refactor to enforce DOS aesthetic: all `cornerRadius` values ≥1 became sharp (radius 0). This is part of [DMNC-1211](https://linear.app/lizomorf/issue/DMNC-1211) (visual-consistency refactor).

## Changes

**Strategy**: Replace all rounded corners with sharp corners:
- `RoundedRectangle(cornerRadius: n)` → `Rectangle()`
- `.cornerRadius(n)` → delete the modifier
- `.clipShape(RoundedRectangle(...))` → `.clipShape(Rectangle())` (keep clip where needed to prevent bleeds)

**Files Modified (15 files, 25 changes)**:
1. `App/DesignSystem/Components/StepperField.swift` (lines 95, 98)
2. `App/DesignSystem/Components/HoldToCommitProgress.swift` (lines 117, 189)
3. `App/Views/SharedViews/TightControlToast.swift` (line 76)
4. `App/Views/SharedViews/LoggedMealToast.swift` (line 36)
5. `App/Views/Lists/StatisticsView.swift` (lines 202, 206)
6. `App/Views/AddViews/BarcodeScannerView.swift` (lines 148, 181)
7. `App/Views/AddViews/ItemBarcodeScannerView.swift` (lines 86, 133)
8. `App/Views/AddViews/FoodPhotoAnalysisView.swift` (line 395)
9. `App/Views/AddViews/CombinedEntryEditView.swift` (line 230)
10. `App/Views/Overview/TreatmentBannerView.swift` (lines 183, 187)
11. `App/Views/Overview/ChartView.swift` (line 272 — `.cornerRadius(2)` deleted)
12. `App/Views/Overview/EventMarkerLaneView.swift` (line 145)
13. `App/Views/Overview/EntryGroupListOverlay.swift` (line 102)
14. `Library/DesignSystem/Components/StatsComponents.swift` (lines 98, 134, 136)
15. `App/Views/Overview/ChartReportViews.swift` (lines 134, 147, 165, 179 — `.cornerRadius(0)` deleted)

**Documentation Updated**:
- `CHANGELOG.md`: Added entry under `[Unreleased]` → Changed: "All panels, toasts, and stat cards now use sharp DOS corners"
- `docs/design-system.md`: Line 150 updated to "cornerRadius 0 (sharp DOS corners, no exceptions)"

## Verification

✅ **Build**: `xcodebuild ... build` succeeded  
✅ **Tests**: `xcodebuild ... test` — all 350+ tests passed (no geometry assumptions in HoldToCommitProgress/StepperField tests)  
✅ **Grep**: `grep -rn "cornerRadius: [1-9]" App Library Widgets` → 0 matches  
✅ **Grep**: `grep -rn "\.cornerRadius([1-9]" App Library Widgets` → 0 matches (only `.cornerRadius(0)` deleted, non-0 modifiers removed entirely)

## Review follow-up (same PR)

The acceptance criterion was the grep (radius 0 *everywhere*), not the enumerated site list — the four sites initially skipped as "not in the explicit list" were swept in a review-fix commit:

- `AddInsulinView.swift:177` (IOB stacking warning border, radius 3 → sharp)
- `AmberChip.swift` lines 66/83/87 (chip border + segmented fill/stroke, radius 2–3 → sharp)

## Notes

- The 19 explicit sites from the issue were the focus; ChartReportViews `.cornerRadius(0)` (4 extra changes) were bonus no-ops that are now cleaned up.
- No new files created; pure mechanical substitutions using Edit tool.
- Accepted boundary: no chip token design system needed; radius 0 guards globally.
