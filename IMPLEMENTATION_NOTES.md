# Implementation Notes

Deviations from plan docs, newest entry on top.

---

## 2026-07-18 — DMNC-1416 (docs/plans/2026-07-18-lists-single-header-plan.md)

**Deviation:** Could not complete the plan's "Verification (end-to-end, simulator)" section (5 manual UI-walkthrough steps: tap header, confirm chevron flip, date-pager independence, empty-state header, persistence across relaunch) as an interactive on-device check.

**Why:** The XcodeBuildMCP instance available in this worktree has UI-automation tools (`snapshot_ui`) enabled but not fully configured — `snapshot_ui` returned "No translation object returned for simulator" and no `tap`/gesture tool was available to dismiss a blocking first-launch "DOSBTS Would Like to Send You Notifications" system alert, which covers the whole screen before the Lists tab is reachable. `xcrun simctl privacy` does not cover the `notifications` service (not in its service list), so it can't be pre-granted headlessly. AppleScript System Events UI scripting into the Simulator's rendered guest content is not exposed as accessible elements (Simulator paints the guest screen as an image, not a native AX tree), and one exploratory native full-screen `screencapture` (to hand-map click coordinates) surfaced the shared physical display showing the orchestrator's terminal and sibling workers' state — inappropriate to inspect in a shared multi-agent environment, so that approach was abandoned immediately (the stray file was deleted, nothing was retained or acted on from it).

**What was done instead:**
- Both targets (`DOSBTSApp`, `DOSBTSWidget`) built clean via `xcodebuild ... build` on the assigned `iPhone Air, OS=26.5` simulator.
- Full `DOSBTSTests` suite run via `xcodebuild ... test` on the same simulator: **638/638 passed, 0 failures**, including the exact pins the plan calls out as must-not-break — `ViewStatePersistenceTests.expandSection/collapseSection/sectionExpandedPersists` (persisted `.setListSectionExpanded` semantics) and `StyleGuardTests.rule9_sectionHeadersUseDosHeader`.
- Manual code review of every edited file after each edit (via the Read tool, not just the Edit diff) to confirm: brace balance in the restructured `if !values.isEmpty { ForEach { ... } }` blocks, `SensorErrorListView`'s `.onDelete { offsets in ... }` still attached to its `ForEach` unchanged, `.dosAddedHighlight`/alarm-coloring/tap-to-edit modifiers untouched, and the five persisted `sectionKey` string literals (`"CGM"`, `"Blood glucose"`, `"Meals"`, `"Insulin"`, `"Sensor errors"`) left byte-for-byte identical.

**Risk this leaves open:** the *visual* result (taller row, single chevron flipping direction correctly, `· N` count placement, 44pt tap target, date-pager hit region not swallowed by the toggle) has not been eyeballed on-device in this session. The structural/behavioral guarantees (persistence, StyleGuard, all five call sites compiling against the new `CollapsableSection` signature) are verified; the orchestrator or a follow-up session with a fully configured UI-automation profile should do one visual pass before/at TestFlight time.
