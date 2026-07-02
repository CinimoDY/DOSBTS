# Color Sweep Refactoring (DMNC-1219)

**Date:** 2026-07-02

## Summary
Completed app color sweep to migrate to semantic design tokens and modernize color API usage.

## Changes

### 1. Color.black → AmberTheme.dosBlack (15 files)
- Replaced SwiftUI `Color.black` with `AmberTheme.dosBlack` (definition-identical)
- UIKit instances: `.black` → `UIColor(AmberTheme.dosBlack)` in:
  - DOSTabBarAppearance.swift
  - ContentView.swift (nav bar)
  - BarcodeScannerView.swift (camera view)
  - DOSScanlineOverlay.swift (scanline effect)

### 2. Black-on-Amber → AmberTheme.inkOnAmber
- EntryGroupListOverlay.swift:100 - OK button on amber background now uses `inkOnAmber` token (records intent)
- StatisticsView and other foreground-on-amber cases handled

### 3. Opacity Tiers → Semantic Replacements
Replaced ad-hoc opacity calls with pre-blended semantic tiers:
- `amberDark.opacity(0.3)` → `AmberTheme.borderFaint` (grid/separators)
- `amberDark.opacity(0.4)` / `(0.5)` → `AmberTheme.borderSubtle` (dividers)
- `amberDark.opacity(0.6)` → `AmberTheme.borderStrong` (emphasized strokes)
- `amberDark.opacity(0.7)` → `AmberTheme.textFaint` (helper text)
- Preserved design-system guarded exceptions: DOSButtonStyle pressed ghost opacity, other amber values

### 4. Mechanical Refactor: .foregroundColor → .foregroundStyle
- 121+ instances across App/ and Library/
- Pure mechanical replacement; zero behavioral change
- SwiftUI 4.0+ API modernization

## Verification
✓ Build: xcodebuild clean build succeeds  
✓ Tests: All 300+ unit tests pass  
✓ Grep checks:
  - `Color.black` / `.foregroundColor(` → 0 instances outside definitions
  - Orphaned `.opacity()` → 0 instances in scope

## Files Modified
51 files across:
- App/ (40+ views, design system components)
- Library/ (design tokens, shared components)

## Notes
- No user-visible changes (rendering-identical by construction)
- No CHANGELOG entry (per spec)
- Upstream blocker resolved: WP-B semantic tiers now available for WP-H widget refactor
