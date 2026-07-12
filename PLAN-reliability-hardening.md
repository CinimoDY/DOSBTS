# PLAN: Reliability hardening — silent failures + first tests for untested data paths

**Linear:** none yet — create a Linear issue in the DOSBTS project when starting (title: "Reliability hardening: silent serialization failures + payload mapper tests", reference this file) so the PR has a tracking id.
**Rank:** 5 of 6. Effort: S–M (~half a day). Independent of all other plans.

## Goal

Users dose insulin off the widget and off Nightscout followers. Today, three data paths can fail **with zero observability**, and the payload mappers feeding them have **zero tests**:

1. `App/Modules/AppGroupSharing/AppGroupSharing.swift:237,266` — `guard let json = try? JSONSerialization.data(...) else { return }` → widget/FreeAPS shared glucose silently not updated (stale widget, no log line).
2. `App/Modules/Nightscout/Nightscout.swift:98,281,317,399` — same silent-return pattern → readings/treatments silently never uploaded.
3. `App/Modules/DataStore/DailyDigestStore.swift:64,106,138,228,268` — five `Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!` force-unwraps, violating the repo's hard no-`!` rule (`docs/development-rules.md`).

Fix all three classes and add the first unit tests for the pure payload mappers (`toFreeAPS`, `toNightscoutGlucose`, `toNightscoutInsulinDelivery`, `toNightscoutSensorStart`).

This is internal-only hardening: **no CHANGELOG entry** (CLAUDE.md: internal changes don't get one), no behavior change on the happy path.

## Preconditions

`git pull --ff-only`; branch `chore/reliability-hardening`. Line numbers above verified against Build 129 (`ee719767`) — re-verify with the greps in Acceptance before editing.

## Exact files to touch

| File | Change |
|---|---|
| `App/Modules/AppGroupSharing/AppGroupSharing.swift` | Log-on-failure at the 2 guard sites |
| `App/Modules/Nightscout/Nightscout.swift` | Log-on-failure at the 4 guard sites |
| `App/Modules/DataStore/DailyDigestStore.swift` | Replace 5 force-unwraps with guarded fallback |
| `App/Modules/DataStore/TreatmentEventStore.swift` | Context strings on the 3 bare `DirectLog.error("\(error)")` catches (lines ~62,74,78) |
| `DOSBTSTests/PayloadMapperTests.swift` | NEW — mapper + serialization tests (needs pbxproj registration, see traps) |
| `DOSBTS.xcodeproj/project.pbxproj` | Register the new test file |

**No Redux changes, no new actions, no UI.** If you find yourself editing `DirectAction.swift` or any view, you have exceeded scope.

## Implementation steps (in order)

1. **AppGroupSharing (2 sites).** The guard-return already preserves the last-good shared payload (it never overwrites with garbage) — the missing piece is purely observability. Change each to:
   ```swift
   guard let sharedValuesJson = try? JSONSerialization.data(withJSONObject: sharedValues) else {
       DirectLog.error("AppGroupSharing: failed to serialize shared glucose payload (\(sharedValues.count) values) — widget will show stale data")
       return
   }
   ```
   (Adapt the message per site: one is `addBloodGlucose`, one `addSensorGlucose`.)
2. **Nightscout (4 sites, lines 98/281/317/399).** Same pattern; message must name the operation so a log reader can tell which upload was dropped (sensor start / glucose batch / treatment — read each enclosing function name and say so): `DirectLog.error("Nightscout: failed to serialize <operation> payload — upload skipped")`.
3. **DailyDigestStore (5 sites).** All five are the same expression inside `asyncRead` blocks. Replace with a guarded form that fails the read gracefully rather than crashing:
   ```swift
   guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else {
       promise(.failure(.withMessage("DailyDigestStore: calendar arithmetic failed for \(startOfDay)")))
       return
   }
   ```
   **Check each site's context individually**: sites inside `Future { promise in ... }` fail the promise; if any site is in a non-promise context (e.g. a plain write), fall back to `return` + `DirectLog.error`. Check the exact `DirectError` API first (`grep -n "case withMessage\|case withError" Library/` — if only `.withError` exists, wrap an `NSError` or add nothing new; do NOT invent enum cases without checking).
4. **TreatmentEventStore.** Change `DirectLog.error("\(error)")` → `DirectLog.error("TreatmentEventStore.<functionName>: \(error)")` at the three catches. Nothing else — the write-only V1 design is intentional (CLAUDE.md), do not add reads or user-facing errors.
5. **`DOSBTSTests/PayloadMapperTests.swift`** (Swift Testing: `import Testing`, `@Test`, `#expect` — match the existing suite style):
   - `toFreeAPS()` on a `SensorGlucose` fixture: expected keys present (inspect the mapper at `AppGroupSharing.swift:275+` for the exact key set — likely `sgv`/`date`/`direction`-style), values round-trip through `JSONSerialization.data` (i.e. `#expect(throws: Never.self) { try JSONSerialization.data(withJSONObject: [mapped]) }`).
   - Same for `BloodGlucose.toFreeAPS()` (`AppGroupSharing.swift:291+`).
   - `toNightscoutGlucose()` (both overloads at `Nightscout.swift:474,490`), `toNightscoutInsulinDelivery()` (:509), `toNightscoutSensorStart()` (:453): keys + serializability + a nil-returning edge if the mapper has one (read each mapper; several return `[String: Any]?` — pin when and why nil happens).
   - These mappers are `internal` in the app target — the test target uses `@testable import DOSBTSApp` like every other test file (copy the import line from `DirectReducerTests.swift`).
6. **Register the test file in pbxproj** (tests are NOT fileSystemSynchronized — CLAUDE.md § Adding New Files): add to the `DOSBTSTests` group and `PBXSourcesBuildPhase`. Then prove it runs: temporarily add `@Test func canary() { #expect(Bool(false)) }`, run the suite, see exactly one new failure, delete the canary. **An unregistered test file "passes" by never executing — this check is mandatory.**
7. Run the full suite + both target builds; PR.

## Cases a weaker model would miss

1. **Do not "upgrade" the guards into `throw`s.** These functions are called from Combine middleware chains typed `AnyPublisher<DirectAction, DirectError>`; making them throwing changes signatures up the chain and risks tearing down long-lived publishers (a Combine failure CANCELS the pipeline — a single bad payload would kill all future Nightscout uploads until relaunch, which is strictly worse than today). Log-and-skip is the correct semantic.
2. **Do not add user-facing error UI.** A failed widget write or Nightscout upload during background delivery has no meaningful user surface; the widget already shows staleness tiers (5/15-min amber/red) as designed. Observability (logs) is the deliverable.
3. **`JSONSerialization` failures here are near-impossible by construction** (the mappers emit plain String/Int/Double dictionaries) — which is exactly why the sites went unlogged for months. The point of the change is that *when* a mapper regression makes a payload non-serializable (e.g. someone adds a `Date` or `UUID` raw value), it surfaces in the log AND the new mapper tests catch it at Cmd+U time. Both halves matter; don't skip the tests because the fix looks trivial.
4. **DailyDigestStore promise contexts differ per site.** Two of the five sites sit in `getX` read Futures, others in different flows (lines 106 vs 228 vs 268 have different enclosing functions). Read each before editing; the mechanical find-and-replace with a single `promise(.failure(...))` form will not compile everywhere.
5. **`UserDefaults.shared` is the App Group suite** — do NOT write tests that touch it (the App Group container may not exist in the test runner, and shared-suite writes pollute cross-test state). Test the *mappers* (pure), not the store writes. Repo test rule: state-dependent tests use `makeTestDefaults()` / `AppState(defaults:)` (`DOSBTSTests/DirectReducerTests.swift:15`) — but mapper tests shouldn't need AppState at all.
6. **Don't fix the `StoreExport.swift:87` `mmolLFormatter.string(...)!` here** even though it's also a force-unwrap — it's inside the export path that PLAN-endo-report-export touches; fixing it twice creates merge conflicts. Leave a one-line note in the PR description instead.
7. **`DirectLog` context-string convention**: look at 2–3 existing good log calls (`grep -rn "DirectLog.error(\"" App/Modules/ | grep -v "\\\\(error)\"" | head`) and match their prefix style rather than inventing a new format.
8. **Line numbers drift.** Re-run the verification greps (below) after pulling; edit by pattern, not by memorized line number.

## Acceptance criteria

1. Verification greps BEFORE editing (must match, else stop and re-scout):
   - `grep -c "try? JSONSerialization" App/Modules/AppGroupSharing/AppGroupSharing.swift` → 2
   - `grep -c "try? JSONSerialization" App/Modules/Nightscout/Nightscout.swift` → 4
   - `grep -c 'byAdding: .day, value: 1, to: startOfDay)!' App/Modules/DataStore/DailyDigestStore.swift` → 5
2. AFTER editing:
   - `grep -n 'byAdding.*)!' App/Modules/DataStore/DailyDigestStore.swift` → no hits.
   - Every `try? JSONSerialization` guard in the two files has a `DirectLog.error` in its else body (grep the else bodies by eye).
   - `grep -rn '!' App/Modules/DataStore/DailyDigestStore.swift | grep -v '!=' | grep -v '//'` reviewed — no remaining force-unwraps.
3. Full suite green; new `PayloadMapperTests` visibly executed (test count increased; canary check performed during step 6).
4. Both app + widget builds succeed.
5. Behavior spot-check on simulator: normal run still updates the widget (add glucose via VirtualConnection, widget timeline refreshes) — proving the guards weren't inverted.
6. No CHANGELOG entry (internal-only), but the PR description lists the sites fixed.

## Bookkeeping

Create + link the Linear issue; conventional commit `fix(reliability): log silent serialization failures, remove force-unwraps, test payload mappers`. Post-merge: `docs/solutions/` candidate — "silent guard-return serialization pattern" as a best-practice note if the reviewer agrees.
