# Milestones — DMNC-1295

## Initial implementation
Commit `58cdbdd5` — WP-P4 swipe-delete parity, tap-to-edit for insulin, swipe-dismiss protection for three entry sheets, delete-policy documentation in design-system.md.

## Code review fixes
Commit `d4716d9c` — addressed 7 confirmed findings from the workflow-backed high-effort code review:
- Critical: added `restore*` actions to bypass live-sensor middlewares on swipe-delete undo
- Medium: fixed toast insulin label to use `asInsulinUnits()` + `localizedDescription`
- Medium: fixed toast BG label to use `asGlucose(glucoseUnit:withUnit:)` (locale-aware)
- Low: removed dead `LoggedEntry.entryID` property
- Low: aligned `markerGroup(for:)` id prefix and label with ChartView
- Low: fixed CHANGELOG section order (Added before Changed)
