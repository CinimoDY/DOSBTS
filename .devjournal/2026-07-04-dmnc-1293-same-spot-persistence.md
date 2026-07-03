# DMNC-1293 — "Same Spot" Persistence: Chart Report Type + Collapsed Sections

**Date:** 2026-07-04  
**Branch:** claude/dmnc-1293  
**Part of:** DMNC-1291 (polish & consistency cycle umbrella) — WP-P2

## What changed

Two `@State` properties that silently reset on tab switch or relaunch are now persisted through Redux + UserDefaults:

1. **`selectedReportType`** (GLUCOSE / TIME IN RANGE / STATISTICS) — was `@State` in `OverviewView`; now a Redux property backed by UserDefaults. `ChartReportTypeRow` dispatches `.setSelectedReportType` on tap; `ChartZoomRow` reads from `store.state.selectedReportType` directly.

2. **`listSectionExpanded: [String: Bool]`** — a new Redux dictionary keyed by the stable `sectionName` string each `CollapsableSection` already held (`"CGM"`, `"Meals"`, `"Blood glucose"`, `"Insulin"`, `"Sensor errors"`). `CollapsableSection` now accepts an `onCollapsedChange: ((Bool) -> Void)?` callback; each list view passes a closure that dispatches `.setListSectionExpanded`.

## Architecture decisions

**ReportType moved to `Library/Content/`.**  
`DirectState.swift` lives in `Library/` (compiled into both app and widget targets). `ReportType` was defined in `App/Views/Overview/ChartToolbar.swift`, making it inaccessible from `Library/`. Moving it to `Library/Content/ReportType.swift` resolves the dependency without touching pbxproj (fileSystemSynchronized picks it up automatically).

**`CollapsableSection` gets a callback, not a `Binding<Bool>`.**  
The `@State private var collapsed: Bool` stays as internal state. Adding an `onCollapsedChange` callback is minimally invasive: no API break, no new protocol requirement, the `extension CollapsableSection where Teaser == EmptyView` is untouched. The initial `collapsed:` value — `!store.state.listSectionExpanded[key, default: false]` — is evaluated at construction time, which is exactly when it needs to be (view recreation on tab switch restores from the store; within-session toggles are tracked by `@State`).

**Default: collapsed.** An absent key in `listSectionExpanded` means not expanded (`false`) → `collapsed = !false = true`. This matches the old hardcoded `collapsed: true` so first-launch behaviour is unchanged.

**`statisticsDays` not persisted here.** The plan mentions it "persists in Redux" (i.e., in-memory); the existing `var statisticsDays = 3` in AppState has no `didSet`. Left as-is — this issue only covers `selectedReportType` and section state.

## 4-file lockstep

| File | Change |
|---|---|
| `Library/DirectState.swift` | `selectedReportType: ReportType` + `listSectionExpanded: [String: Bool]` |
| `Library/DirectAction.swift` | `setSelectedReportType` + `setListSectionExpanded` |
| `Library/DirectReducer.swift` | Two new cases |
| `App/AppState.swift` | Both properties with `didSet` + init from defaults |
| `Library/Extensions/UserDefaults.swift` | Keys + accessors (`ReportType` via rawValue, `[String: Bool]` via `dictionary(forKey:)`) |

## Tests

Appended 5 tests to `DOSBTSTests/DirectReducerTests.swift`:

- `cycleReportType()` — reducer cycles all three report types
- `reportTypePersists()` — AppState init restores persisted value
- `expandSection()` — sets one section, leaves others nil
- `collapseSection()` — can collapse after expand
- `sectionExpandedPersists()` — AppState init restores full dictionary

All 5 pass. Full suite: `** TEST SUCCEEDED **`.

## Verification

- App target builds clean ✓
- Widget target builds clean (no new Library types affect widget logic) ✓
- All 5 new tests pass ✓
- Full test suite passes with 0 failures ✓
- CHANGELOG entry added under `[Unreleased]` → Changed ✓
