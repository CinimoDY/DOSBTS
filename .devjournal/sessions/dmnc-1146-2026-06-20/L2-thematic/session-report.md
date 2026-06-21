## Session Report — DMNC-1146

**Date:** 2026-06-20
**Branch:** claude/dmnc-1146
**Linear:** DMNC-1146 — Dead code: ConsolidatedMarkerGroup.summaryLabel / dominantType / totalCarbs orphaned by event-marker lane rewrite

### What Was Done

Removed three orphaned computed properties from `ConsolidatedMarkerGroup` in `Library/Content/EventMarker.swift`:

- **`dominantType`** — returned the `EventMarkerType` with the most markers, defaulting to `.meal`. Was used by the old in-chart diamond/circle annotation design (pre-event-marker-lane).
- **`summaryLabel`** — returned a carbs-gram string ("42g") or marker count ("3"). Missing the `★` scored-meal prefix that the live chip rendering in `chipRows(isScored:)` shows.
- **`totalCarbs`** — returned the sum of meal marker rawValues, or nil. Superseded by inline computation inside `chipRows`.

All three had zero callers anywhere in `App/`, `Library/`, `Widgets/`, or `DOSBTSTests/`. Confirmed with exhaustive grep before deletion. Build succeeded cleanly (BUILD SUCCEEDED). Code review returned no findings.

### Why

These were leftovers from the pre-lane in-chart annotation design. The event-marker lane rewrite (DMNC-635/DMNC-715) replaced the old circle/diamond annotation path with `ConsolidatedMarkerGroup.chipRows(isScored:)`, which derives its own per-lane labels directly from `markers` and correctly applies the `★` scored-meal prefix. The old helpers were never cleaned up at the time.

The original concern surfaced in the DMNC-715 review (PR #62) was that `summaryLabel` was missing the `★` prefix — but on closer inspection the entire label path was dead, not just the prefix. The fix is deletion, not patching.

### No behavior change

Pure dead-code removal. No user-visible change. No CHANGELOG entry needed per project rules (internal cleanup).

### Files Changed

- `Library/Content/EventMarker.swift` — removed 19 lines (three computed properties from `ConsolidatedMarkerGroup`)
