# Zoom-Aware Marker Consolidation (Single Authority) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**User feedback (verbatim, source of truth for intent):** "The meal markers: not sure when I zoom in on the timeline if they can split up according to the space we have. The values are not correctly added when zoomed out because you can't have all the meal markers next to each other when you're zoomed out. You need the meal marker that shows the summary, but once you've zoomed in enough, it should split."

**Goal:** Marker chips split into individual markers as you zoom in and merge into summary chips as you zoom out, driven purely by available pixel space. Summed totals then match what the user expects at every zoom level.

**Architecture (verified findings — read before touching anything):**
- Two conflicting consolidation stages exist:
  - **Stage 1** — `ChartView.updateMarkerGroups()` (`App/Views/Overview/ChartView.swift:939-1015`) groups markers by a fixed time window `Config.consolidationWindows[chartZoomLevel]` (`612-624`: `3h→0, 6h→600, 12h→1200, 24h→1800`).
    - **Bug A:** at 3h zoom `window == 0`, so the `window > 0` guard at line 990 is permanently false → a new group is **never started** → the entire day renders as ONE chip at maximum zoom-in — the exact opposite of "zoom in → split".
    - **Bug B:** the gap test compares each marker to the **previous marker** (`currentMarkers.last`), not the group's start, so dense runs chain into groups far wider than the window — inflating summed chip totals ("values not correctly added").
  - **Stage 2** — `EventMarkerLaneView.consolidateByOverlap` (`App/Views/Overview/EventMarkerLaneView.swift:56-79`) merges by pixel proximity (fixed `estimatedChipWidth = 60`pt + 4pt gap) using positions that DO scale with zoom (`seriesWidth` from `updateSeriesMetadata()`, `ChartView.swift:798-813`, flows into the lane as `totalWidth`). Its own comment (52-55) says it **replaces** the window logic — but Stage 1 still runs, and Stage 2 can only merge, never split.
- **The chip arithmetic is correct and must not be touched.** Per-type sums in `ConsolidatedMarkerGroup.chipRows` (`Library/Content/EventMarker.swift:99-157`) are pinned by the `MarkerChipRowTests` suite (inside `DOSBTSTests/EventMarkerTypeTests.swift:43-162`; see also `docs/plans/2026-07-14-feat-marker-chip-clean-sums-plan.md`, shipped). Do NOT chase a summing bug — the wrong-looking totals are over-grouping upstream.
- Tap-through already passes the full merged marker set to the detail overlay (`EventMarkerLaneView.swift:31-41`) — unaffected by this change.

**Fix:** Stage 1 stops grouping entirely (one `ConsolidatedMarkerGroup` per marker); the pixel-based `consolidateByOverlap` becomes the single consolidation authority, extracted into a pure, tested function.

**Tech Stack:** Swift, SwiftUI, Swift Testing.

## Global Constraints

- `MarkerChipRowTests` must keep passing **unchanged** (3-row cap, insulin→meal→exercise order, clean summed labels, ★ prefix).
- Chips stay compact — icon + amount only, **no times on chips** (user-confirmed; per-entry times land in the detail sheet via the companion plan `2026-07-18-marker-detail-selective-edit-plan.md`). The 60pt lane budget is untouched.
- `Library/Content/EventMarker.swift` compiles into **both** app and widget targets — both must build.
- Merged-group id semantics stay stable across re-renders (the current code keeps the first-in-cluster's id through successive merges — preserve that so sheet identity doesn't churn).
- Accessibility labels (`accessibilityLabel(for:)`, lane 87-98) keep working for both single and merged groups.
- User-visible change → `CHANGELOG.md` `[Unreleased]` entry required. New test files need manual pbxproj registration.

---

### Task 1: Extract `consolidateByOverlap` into a pure, tested function

**Files:**
- Modify: `Library/Content/EventMarker.swift` (new static function on/near `ConsolidatedMarkerGroup`)
- Modify: `App/Views/Overview/EventMarkerLaneView.swift` (call the extracted function)
- Create test: `DOSBTSTests/MarkerConsolidationTests.swift` (+ pbxproj registration)

**Interface:**

```swift
extension ConsolidatedMarkerGroup {
    /// Walk groups left-to-right (by time) and merge any whose rendered chip
    /// would overlap the previous one. `xFor` maps a time to its pixel
    /// position at the current zoom; `estimatedWidth` returns the estimated
    /// chip width for a group (see Task 3). Pure — no view dependencies.
    static func consolidateByOverlap(
        _ groups: [ConsolidatedMarkerGroup],
        xFor: (Date) -> CGFloat,
        estimatedWidth: (ConsolidatedMarkerGroup) -> CGFloat,
        minGap: CGFloat = 4
    ) -> [ConsolidatedMarkerGroup]
}
```

- [x] **Step 1 (failing tests first)** — pin with a linear `xFor` stub (e.g. 1pt per minute × a scale factor to simulate zoom):
  - two groups farther apart than `width + gap` stay separate; closer merge;
  - merged group keeps the earlier group's `id`, concatenates markers in order, re-anchors to the **median** marker time (current behavior, lines 65-72);
  - transitive chains merge into one;
  - **zoom-split regression:** the same marker set that merges at a small scale (zoomed out) yields one group per marker at a large scale (zoomed in) — this is the test that would have caught Bug A;
  - empty input → empty output.
- [x] **Step 2:** Move the body of `EventMarkerLaneView.consolidateByOverlap` (56-79) into the extension; the lane's `body` calls it passing its `xPosition(for:)` and (until Task 3) a constant-60pt `estimatedWidth`. Tests green; behavior identical. _(Wired straight to content-aware width in one pass — see IMPLEMENTATION_NOTES sequencing note; overlap tests use a constant-width stub so the constant-60 semantics are still pinned.)_

### Task 2: Stage 1 stops grouping — one group per marker

**Files:**
- Modify: `App/Views/Overview/ChartView.swift`

- [x] **Step 1:** In `updateMarkerGroups()` (939-1015), delete the windowed grouping loop (985-1012). After building + sorting `allMarkers`, emit:
  ```swift
  markerGroups = allMarkers.map {
      ConsolidatedMarkerGroup(id: "group-\($0.id)", time: $0.time, markers: [$0])
  }
  ```
  (Keep the `"group-"` id prefix — merged visual groups inherit the first member's id, preserving current id semantics.)
- [x] **Step 2:** Delete `Config.consolidationWindows` (619-624) and every reference. Check the `.onChange(of: chartZoomLevel)` handler (509-516): remove only its `updateMarkerGroups()` call — zoom reactivity now flows automatically via `updateSeriesMetadata()` → `seriesWidth` → lane `totalWidth` → the pure consolidator running in the lane body. **Keep** any series-metadata/scroll work that handler also does, and keep the data-change triggers (meal/insulin/exercise `.onChange`s at 470/497/506).
- [x] **Step 3:** Build + run: at 3h zoom, chips are now individual (Bug A gone); at 24h, nearby chips merge. _(Build green; the split/merge logic is pinned by `MarkerConsolidationTests.zoomSplitRegression`. The live on-device zoom feel still needs human eyes — see the end-to-end Verification section below.)_

### Task 3: Content-aware chip width estimate

**Files:**
- Modify: `Library/Content/EventMarker.swift`
- Extend test: `DOSBTSTests/MarkerConsolidationTests.swift`

- [x] **Step 1 (failing tests first):** pure `estimatedChipWidth(isScored:) -> CGFloat` on `ConsolidatedMarkerGroup`, derived from its `chipRows` labels: `iconWidth + longestRowLabelCount × monoCharWidth + padding` (constants as `static let`, pinned). A single `5U` chip estimates narrower than a triple-stack `8U 2Uc 10Ub / ★60g / 45m` chip. Pin: single small chip < 60pt default; wide multi-segment chip > 60pt; monotonic in label length.
- [x] **Step 2:** Lane passes `{ $0.estimatedChipWidth(isScored: isGroupScored($0)) }` as `estimatedWidth`; delete the fixed `estimatedChipWidth = 60` constant (`EventMarkerLaneView.swift:27`) and its now-stale comment (23-27). Tests green.

### Task 4: CHANGELOG + full verification

- [x] `CHANGELOG.md` `[Unreleased]` → `### Fixed`: `- Chart event markers now split into individual chips as you zoom in and merge only when they'd visually collide — zoomed-in views no longer collapse the whole day into one summed chip`
- [x] Full suite: `xcodebuild test ... -scheme DOSBTSApp ...` → SUCCEEDED (MarkerChipRowTests untouched and green). _(651 passed / 0 failed on iPhone 17 Pro Max, OS 26.5.)_
- [x] Both targets build (app + `DOSBTSWidget`). _(App built as part of the test run; `DOSBTSWidget` scheme → BUILD SUCCEEDED.)_

## Verification (end-to-end, simulator + VirtualConnection)

Seed a dense cluster (3 meals + 2 boluses within 30 min) plus isolated entries hours apart:
1. 3h zoom: the cluster renders as several individual/near-individual chips, each with its own correct value; isolated entries are single chips.
2. 24h zoom: the cluster merges into one chip whose totals equal the sum of its entries (e.g. `8U 2Uc / 60g`); tapping lists all constituents.
3. Step through 3h → 6h → 12h → 24h: chips merge progressively; back down: they split. No zoom level shows the whole day as one chip.
4. Perf sanity: scrolling/zooming stays smooth with a heavy logging day (consolidation is O(N) per render over the day's markers).
