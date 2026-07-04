# Session Report — DOSBTS

**Date:** 2026-07-04
**Branch:** claude/dmnc-1295
**Commits:** 3 (2 code, 1 docs)

## What Was Done

**WP-P4 Interaction parity** (DMNC-1295):
- Replaced `.onDelete` with `.swipeActions(edge: .trailing)` on BloodGlucoseListView, InsulinDeliveryListView, SensorGlucoseListView — each delete shows an undo-capable LoggedEntryToast
- Added tap-to-edit for insulin rows → opens CombinedEntryEditView via SheetCoordinator
- Added `.interactiveDismissDisabled()` on AddInsulinView, AddBloodGlucoseView, AddCalibrationView
- Added Interaction Patterns / Delete-confirmation policy section to docs/design-system.md

**Code-review fixes** (7 confirmed findings from workflow-backed high-effort review):
- Critical: Added restoreBloodGlucose / restoreInsulinDelivery / restoreSensorGlucose actions — undo now bypasses all live-sensor middlewares (alarms, ReadAloud, HealthKit, Nightscout, treatment cycle)
- Medium: Fixed toast insulin label: asInsulinUnits() + localizedDescription
- Medium: Fixed toast BG label: asGlucose(glucoseUnit:withUnit:) (locale-aware)
- Low: Removed dead LoggedEntry.entryID property
- Low: Aligned markerGroup(for:) id prefix ("insulin-<uuid>") and label (asInsulin()) with ChartView
- Low: Fixed CHANGELOG section order (Added before Changed)

## Commits

| Hash | Message |
|------|---------|
| 58cdbdd5 | feat(interaction): WP-P4 — swipe-delete parity, dismiss protection, delete policy |
| d4716d9c | fix(interaction): address code-review findings for WP-P4 swipe-delete undo |
| d6e42877 | docs(devjournal): DMNC-1295 session journal + compound learning |

## Issues Updated

- DMNC-1295 (In Review) — PR #94 attached

## Open Items

None — all confirmed code-review findings resolved.

## Next Steps

1. PR #94 review pass
2. Merge and promote to [Build 127] when polish cycle ships

## Open PRs

- PR #94 — feat(interaction): WP-P4 — Interaction parity (DMNC-1295)
