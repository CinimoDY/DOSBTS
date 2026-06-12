# Session Report — DMNC-1044 Stat box height equalisation

**Date:** 2026-06-12  
**Branch:** claude/dmnc-1044  
**Linear:** DMNC-1044

## What Was Done

Fixed the Daily Digest stat boxes to all render at the same height regardless of whether they have a subline (help text). Previously, cards with no subline (LOWS, HIGHS, CARBS, INSULIN) were shorter than those with one (TIR shows "On target / Close / Off target", AVG shows "mg/dL"), causing a visually jagged grid.

**Root cause:** `StatCard` used `if let help { Text(help) }` — when `help` is nil the view is never added to the hierarchy, so the VStack is shorter by one text row + spacing.

**Fix:** Always render the help text row, but make it invisible (`opacity(0)`) when `help` is nil, and mark it `accessibilityHidden(true)` so VoiceOver doesn't land on a blank element. This reserves the layout space without changing any public API.

**File changed:** `Library/DesignSystem/Components/StatsComponents.swift` — `StatCard.body`

## Decisions

- Chose `opacity(0)` + `accessibilityHidden` over an explicit `.frame(height:)` sentinel because the invisible Text automatically tracks font-metric changes (Dynamic Type, etc.) without needing a hardcoded constant. Accessibility hidden flag added after code review flagged the VoiceOver blank-announcement risk.
- Did not change the `help` API (still `String?`) — the fix is entirely within the rendering layer.

## Build verification

`xcodebuild … build` → **BUILD SUCCEEDED**
