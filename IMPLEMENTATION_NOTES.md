# Implementation Notes

Deviations from written plans, newest entry first.

---

## 2026-07-18 — DMNC-1413 Insulin Batch Entry (`docs/plans/2026-07-18-insulin-batch-entry-plan.md`)

Executed task-by-task per the sonnet-worker protocol. Two minor deviations, both conservative interpretations where the plan text was ambiguous or where the dispatching brief overrode the plan doc's literal wording:

1. **Simulator substitution.** The plan doc's verification command literally reads `iPhone 17 Pro`; the dispatching brief assigned this worker `platform=iOS Simulator,name=iPhone 17,OS=26.5` (three sibling workers use other simulators in parallel to avoid collisions). Used `iPhone 17` everywhere per the brief, not `iPhone 17 Pro`. Both the plan checkbox and the reported verification command reflect the substituted simulator.

2. **Staged-row time format.** Task 2 Step 3 specifies rendering each staged entry's time as `HH:mm`. There is no literal `"HH:mm"` `DateFormatter` convention anywhere in the codebase — the established pattern for a time-only string in a row (confirmed by searching `Library/Extensions/Date.swift` and its callers, e.g. `EventMarkerLaneView.swift`, `SnoozeView.swift`) is the locale-aware `Date.toLocalTime()` (`.formatted(.dateTime.hour().minute())`). Used `entry.starts.toLocalTime()` instead of a hardcoded 24-hour formatter, matching every other time-only display in the app rather than introducing a one-off format.

No other deviations. All interfaces (`InsulinBatchBuilder.commitSet`/`iobInputs`, the `addCallback: (_ deliveries: [InsulinDelivery]) -> Void` signature, the `LoggedEntry.insulinBatch` case) match the plan's `Interfaces` section verbatim. `AddedEntryHighlighter.flash(_:)` is called once per delivery id in a loop as the plan directs (Task 3) — note this only visually highlights the *last* id since the highlighter stores a single `highlightedID`, which is the plan's specified behavior, not a gap introduced here.
