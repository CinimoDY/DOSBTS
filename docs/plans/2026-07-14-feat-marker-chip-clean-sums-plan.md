# Marker Chip Clean Sums — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Event-marker chips show the clean accumulated total per entry type — no confusing `×N` count suffix — so a chip holding multiple meals reads `60g` and multiple boluses read `8U`, with bolus/correction/basal still summed separately.

**Architecture:** The summation already exists and is correct — `ConsolidatedMarkerGroup.chipRows(isScored:)` reduces each type's markers to a total. The only change is dropping the `count > 1 ? "…×count" : "…"` branch in all five segment builders so the label is always the clean total. Pure display change in one pure function + its tests; no view, state, or consolidation changes.

**Tech Stack:** Swift, Swift Testing (`@Test`/`#expect`), SwiftUI (unaffected — `FlagView` renders whatever labels the function returns).

## Global Constraints

- Per-type separation is preserved: bolus / correction / basal each sum only within their own type and render as separate colored segments in the one insulin row. Meal/snack bolus both map to `.bolus` (unchanged).
- Suffixes stay: `U` bolus, `c` correction (`Uc`), `b` basal (`Ub`), `g` meal, `m` exercise. `★` prefix on scored meals stays.
- Single-entry chips are already clean (`45g`, `5U`) — behaviour there is unchanged; only multi-entry chips lose the `×N`.
- `formatMarkerUnits` unchanged: integer units drop the decimal (`5U`), fractional keep one place (`2.5U`).
- User-visible change → a `CHANGELOG.md` `[Unreleased]` entry is required.
- `EventMarker.swift` lives in `Library/` and compiles into **both** the app and widget targets — both must build.

---

### Task 1: Clean summed labels in `chipRows` + tests

**Files:**
- Modify: `Library/Content/EventMarker.swift:109-172` (the five segment builders inside `chipRows(isScored:)`)
- Test: `DOSBTSTests/EventMarkerTypeTests.swift:101-105` (rewrite) + new multi-entry cases in the `MarkerChipRowTests` suite
- Modify: `CHANGELOG.md` (`[Unreleased]` entry)

**Interfaces:**
- Consumes: `ConsolidatedMarkerGroup.chipRows(isScored: Bool) -> [MarkerChipRow]`; `MarkerChipRow` (`.leadType`, `.segments`); `MarkerChipSegment(type:label:)`; test helpers already in the suite — `mk(_ type: EventMarkerType, _ value: Double) -> EventMarker` and `group(_ markers: [EventMarker]) -> ConsolidatedMarkerGroup`.
- Produces: no signature change — same function, same types; only the `label` strings for multi-entry groups change (drop `×N`).

- [ ] **Step 1: Rewrite the existing `×N` test + add the missing multi-entry sum tests (failing)**

In `DOSBTSTests/EventMarkerTypeTests.swift`, replace the `multipleBolusesCollapse` test (currently lines 101-105) with the block below. It renames the test to the new intent and adds one clean-sum case per remaining type plus a mixed-insulin case:

```swift
    @Test("multiple boluses show the clean summed total (no ×N)")
    func multipleBolusesSumClean() {
        let rows = group([mk(.bolus, 4), mk(.bolus, 6)]).chipRows(isScored: false)
        #expect(rows[0].segments[0].label == "10U")
    }

    @Test("multiple corrections sum within type (no ×N)")
    func multipleCorrectionsSumClean() {
        let rows = group([mk(.correction, 2), mk(.correction, 1.5)]).chipRows(isScored: false)
        #expect(rows[0].segments == [MarkerChipSegment(type: .correction, label: "3.5Uc")])
    }

    @Test("multiple basal entries sum within type (no ×N)")
    func multipleBasalSumClean() {
        let rows = group([mk(.basal, 10), mk(.basal, 8)]).chipRows(isScored: false)
        #expect(rows[0].segments == [MarkerChipSegment(type: .basal, label: "18Ub")])
    }

    @Test("mixed insulin sums each type separately, no ×N on any segment")
    func mixedInsulinSumsPerType() {
        // 2 boluses (5+3), 2 corrections (1+1), 1 basal (10)
        let rows = group([
            mk(.bolus, 5), mk(.bolus, 3),
            mk(.correction, 1), mk(.correction, 1),
            mk(.basal, 10),
        ]).chipRows(isScored: false)
        #expect(rows.count == 1)
        #expect(rows[0].segments.map(\.label) == ["8U", "2Uc", "10Ub"])
    }

    @Test("multiple meals sum carbs to a clean total (no ×N)")
    func multipleMealsSumClean() {
        let rows = group([mk(.meal, 20), mk(.meal, 25), mk(.meal, 15)]).chipRows(isScored: false)
        #expect(rows[0].segments[0].label == "60g")
    }

    @Test("scored multi-meal group keeps the ★ prefix on the clean total")
    func scoredMultipleMealsSumClean() {
        let rows = group([mk(.meal, 20), mk(.meal, 40)]).chipRows(isScored: true)
        #expect(rows[0].segments[0].label == "★60g")
    }

    @Test("multiple exercise entries sum minutes to a clean total (no ×N)")
    func multipleExerciseSumClean() {
        let rows = group([mk(.exercise, 30), mk(.exercise, 15)]).chipRows(isScored: false)
        #expect(rows.last?.segments[0].label == "45m")
    }
```

- [ ] **Step 2: Run the suite to confirm the new expectations fail**

Run:
```bash
xcodebuild test -project DOSBTS.xcodeproj -scheme DOSBTSApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -configuration Debug \
  -only-testing:DOSBTSTests/MarkerChipRowTests 2>&1 | grep -E "passed|failed|TEST (SUCCEEDED|FAILED)" | tail
```
Expected: FAIL — the multi-entry cases fail because the code still emits `10U×2`, `3.5Uc×2`, `60g×3`, etc.

- [ ] **Step 3: Drop the `×N` branch in all five segment builders**

In `Library/Content/EventMarker.swift`, inside `chipRows(isScored:)`, replace the five `let label = … .count > 1 ? "…×count" : "…"` blocks with the clean-total form (the `.count` locals disappear):

```swift
        // ---- Insulin lane: bolus → correction → basal segments ----
        var insulin: [MarkerChipSegment] = []

        let bolus = markers.filter { $0.type == .bolus }
        if !bolus.isEmpty {
            let total = bolus.reduce(0.0) { $0 + $1.rawValue }
            insulin.append(MarkerChipSegment(type: .bolus, label: formatMarkerUnits(total)))
        }

        let correction = markers.filter { $0.type == .correction }
        if !correction.isEmpty {
            let total = correction.reduce(0.0) { $0 + $1.rawValue }
            // "c" suffix distinguishes correction from meal/snack bolus (same filled-syringe icon)
            insulin.append(MarkerChipSegment(type: .correction, label: "\(formatMarkerUnits(total))c"))
        }

        let basal = markers.filter { $0.type == .basal }
        if !basal.isEmpty {
            let total = basal.reduce(0.0) { $0 + $1.rawValue }
            // "b" suffix distinguishes basal (long-acting) within the shared insulin row
            insulin.append(MarkerChipSegment(type: .basal, label: "\(formatMarkerUnits(total))b"))
        }

        if let lead = insulin.first {
            rows.append(MarkerChipRow(leadType: lead.type, segments: insulin))
        }

        // ---- Meal lane ----
        let meals = markers.filter { $0.type == .meal }
        if !meals.isEmpty {
            let total = meals.reduce(0.0) { $0 + $1.rawValue }
            let prefix = isScored ? "★" : ""  // ★ marks meals with a glycemic impact score
            rows.append(MarkerChipRow(leadType: .meal, segments: [MarkerChipSegment(type: .meal, label: "\(prefix)\(Int(total))g")]))
        }

        // ---- Exercise lane ----
        let exercise = markers.filter { $0.type == .exercise }
        if !exercise.isEmpty {
            let total = exercise.reduce(0.0) { $0 + $1.rawValue }
            rows.append(MarkerChipRow(leadType: .exercise, segments: [MarkerChipSegment(type: .exercise, label: "\(Int(total))m")]))
        }
```

(The lead-icon comment block above `rows.append(MarkerChipRow(leadType: lead.type…))` may be kept or trimmed — behaviour is unchanged.)

- [ ] **Step 4: Run the marker tests to confirm they pass**

Run:
```bash
xcodebuild test -project DOSBTS.xcodeproj -scheme DOSBTSApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -configuration Debug \
  -only-testing:DOSBTSTests/MarkerChipRowTests 2>&1 | grep -E "passed|failed|TEST (SUCCEEDED|FAILED)" | tail
```
Expected: `** TEST SUCCEEDED **`; the 3-row-invariant and per-type-order tests (`allTypesCollapseToThreeRows`, `insulinLaneCombinesSegments`) still pass — only labels changed.

- [ ] **Step 5: Build both targets**

Run:
```bash
xcodebuild -project DOSBTS.xcodeproj -scheme DOSBTSApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -configuration Debug build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -3
xcodebuild -project DOSBTS.xcodeproj -scheme DOSBTSWidget -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -configuration Debug build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -3
```
Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 6: Add the CHANGELOG entry**

In `CHANGELOG.md`, under `## [Unreleased]` (create a `### Changed` heading if absent), add:
```markdown
- Chart event markers that group multiple entries now show the clean accumulated total (e.g. `60g`, `8U`) instead of a `×N` count — carbs summed for meals, insulin summed per type (bolus / correction / basal kept separate)
```

- [ ] **Step 7: Run the full suite (guard nothing else regressed), then commit**

Run:
```bash
xcodebuild test -project DOSBTS.xcodeproj -scheme DOSBTSApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -configuration Debug 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|failed, " | tail
```
Expected: `** TEST SUCCEEDED **`. Then:
```bash
git add Library/Content/EventMarker.swift DOSBTSTests/EventMarkerTypeTests.swift CHANGELOG.md docs/plans/2026-07-14-feat-marker-chip-clean-sums-plan.md
git commit -m "feat(chart): accumulate marker chip values into a clean total (drop ×N)"
```

## Self-Review

- **Spec coverage:** clean sum (drop `×N`) — Step 3 ✓; sum carbs for meals — `multipleMealsSumClean` ✓; sum insulin per type kept separate — `mixedInsulinSumsPerType` + `multipleCorrectionsSumClean` + `multipleBasalSumClean` ✓; zoom-dependence — unchanged (consolidation untouched, correct by design); count still available on tap — unchanged (expanded panel), and VoiceOver still announces "N entries" via the existing `accessibilityLabel`.
- **Placeholder scan:** none — every step has exact code/commands.
- **Type consistency:** uses only existing symbols (`chipRows`, `MarkerChipRow`, `MarkerChipSegment`, `formatMarkerUnits`, test helpers `mk`/`group`); no new types or signatures.

## Verification (end-to-end)

`Cmd+U` (or the `-only-testing:DOSBTSTests/MarkerChipRowTests` run) green → both target builds green → optional simulator spot-check (VirtualConnection): with several meals and boluses close together, zoom out so they merge into one chip and confirm it reads a single clean total (`60g`, `8U 2Uc 10Ub`), and tapping still lists the individual entries.
