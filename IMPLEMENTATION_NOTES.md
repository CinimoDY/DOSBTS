# Implementation Notes

Newest on top. Decisions/observations logged by opus-worker executors when the
brief granted judgment or reality diverged from the plan.

## 2026-07-18 — DMNC-1415 zoom-aware marker consolidation (single authority)

Plan: `docs/plans/2026-07-18-zoom-aware-marker-consolidation-plan.md`

**Judgment — merge-distance formula (average of half-widths).** The extracted
`ConsolidatedMarkerGroup.consolidateByOverlap` computes the collision threshold
as `mergeDistance = (estimatedWidth(last) + estimatedWidth(group)) / 2 + minGap`
rather than the original single-full-width form (`estimatedChipWidth + minChipGap`).
Reason: chips are center-positioned in the lane (`.position(x: xPosition(for:))`),
so two chips actually collide when their centers are closer than the sum of their
half-widths plus the gap. This reduces to the original `60 + 4 = 64` when both
widths are the constant 60 (so Task 1 Step 2's "behavior identical" requirement
holds), and it is the most faithful reading of the CHANGELOG wording "merge only
when they'd visually collide". Pinned by `MarkerConsolidationTests.mergeThresholdAveragesWidths`.

**Judgment — content-aware width constants.** `estimatedChipWidth(isScored:)`
derives the footprint from the chip's own `chipRows` labels using
`chipIconWidth 12 + per-boundary gaps (chipIconTextGap 4) + labelChars × chipMonoCharWidth 7`,
then `+ 2 × chipHorizontalPadding 5`, taking the widest row (rows stack
vertically). Constants mirror `FlagView` geometry (11pt SF Mono semibold ≈ 7pt
advance — deliberately conservative so chips err on merging a hair early rather
than overlapping; HStack `spacing: 4`; `.padding(.horizontal, 5)`). Pinned exact
values: single `5U` = 40pt (< 60 default), triple stack = 97pt (> 60), in
`ChipWidthEstimateTests`.

**Judgment — `.onChange(of: chartZoomLevel)` handler contents kept.** Read the
handler (formerly lines 509–516): it held only `DirectLog.info(...)`,
`debounceSeriesMetadata()`, and `updateMarkerGroups()`. Removed only the
`updateMarkerGroups()` call; kept `debounceSeriesMetadata()` — that is the
series-metadata work that recomputes `seriesWidth` for the new zoom, which now
drives lane reactivity (`seriesWidth → totalWidth → xPosition → consolidator`).
The scroll-to-end-on-zoom work is a *separate* `.onChange(of: chartZoomLevel)`
inside `glucoseChart` (~line 130) and was left untouched.

**Deviation — sequencing compression (build cycles).** The plan sequences Task 1
Step 2 (lane wired to a constant-60 `estimatedWidth`, build green) then Task 3
Step 2 (swap to content-aware). Both are pure additive functions, so I added them
together and wired the lane straight to the content-aware closure in one pass. The
intermediate constant-60 semantics are still exercised (the overlap tests use a
constant-width stub). I ran one final verification (app full test suite + widget
build) covering Task 2 Step 3 and Task 4 rather than three separate xcodebuild
cycles — each cycle is multi-minute and the net verified state is identical.

**Not human-verifiable here.** The live zoom split/merge *feel* (stepping 3h → 6h
→ 12h → 24h on device/simulator with a seeded dense cluster) needs human eyes; the
pure-function tests pin the logic but not the on-screen gesture.
