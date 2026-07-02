# DMNC-1226: README screenshots refresh (Build 61 → 121)

**Date:** 2026-07-02
**Branch:** claude/dmnc-1226

## What changed

Replaced four README hero screenshots that were last captured at Build 61 (early 2026, pre-event-marker-lane, pre-digest, pre-DOS-sweep). Build 121 captures show the current UI in the simulator with synthetic glucose data.

## Screenshots captured

All four via `xcrun simctl io <device> screenshot` on iPhone 17 Pro simulator (DA17D86D).

**Synthetic data injected into GRDB:**
- 290+ `SensorGlucose` readings at 5-min intervals: 2026-07-01 15:42 UTC → 2026-07-02 16:12 UTC
- Pattern: two peaks (~177, ~162 mg/dL) around breakfast/lunch, then flat landing ~100 mg/dL
- 3 `MealEntry` rows (Porridge 58g, Grilled chicken salad 35g, Apple 25g) at July 2 CEST morning
- 1 `DailyDigest` row for July 1 CEST with a hand-crafted structured `DigestInsight` JSON

**`latestSensorGlucose` in App Group plist** — written via Python `plistlib` with `json.dumps()` because PlistBuddy stores bare dicts without quoting keys, producing malformed JSON the app can't decode.

**DailyDigest date format gotcha:** GRDB stores dates as UTC ISO8601 text. July 1 CEST starts at `2026-06-30 22:00:00.000` UTC. The app's past-day cache lookup does a timezone-aware `startOfDay`, so bare `'2026-07-01'` partially matched but today always recomputes. Found the existing computed record at the UTC-midnight key and updated it in-place.

## Click coordinate derivation

`cliclick` against the Simulator window. Empirically calibrated:
- macOS_x = 943 + (screenshot_px_x / 3 + 11)
- macOS_y = 66 + (screenshot_px_y / 3 + 47)

Confirmed working clicks: "24h" (1236,798), Daily digest tab (1306,916), Settings tab (1204,916), "<" back-arrow in Digest (1004,278), MEAL button (1255,863).

## Code review findings fixed

1. QUICK section described as "hypo-treatment favourites" — wrong in normal `.meal` route where QUICK shows ALL favourites (hypo-filter only active during `.filteredFoodEntry`)
2. IOB decay curve overlay omitted from Overview alt-text — still rendered in ChartView.swift:278-318
3. Photo and Ask AI paths missing from meal-entry alt-text — still exist in UnifiedFoodEntryView.swift, consent-gated
4. "meal chips" is internal CLAUDE.md jargon — replaced with "event markers"
5. Settings alt-text verbatim-enumerated all six category labels — dropped to "six category rows"
