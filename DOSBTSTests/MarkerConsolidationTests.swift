//
//  MarkerConsolidationTests.swift
//  DOSBTSTests
//
//  Pins the pure pixel-overlap consolidation (the SINGLE marker consolidation
//  authority, DMNC-1415): chips split into individual markers as you zoom in
//  and merge only when their rendered chips would visually collide. Includes
//  the zoom-split regression that would have caught the old Stage-1 bug where
//  the whole day collapsed into one chip at maximum zoom-in.
//

import CoreGraphics
import Foundation
import Testing
@testable import DOSBTSApp

@Suite("Marker pixel-overlap consolidation (DMNC-1415)")
struct MarkerConsolidationTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: Helpers

    /// A single-marker group at `minute` past `base`. The group id carries the
    /// "group-" prefix that ChartView emits, matching production.
    private func singleGroup(
        _ id: String,
        minute: Double,
        type: EventMarkerType = .meal,
        value: Double = 20
    ) -> ConsolidatedMarkerGroup {
        let time = base.addingTimeInterval(minute * 60)
        let marker = EventMarker(
            id: id, time: time, type: type, label: "", rawValue: value, sourceID: UUID()
        )
        return ConsolidatedMarkerGroup(id: "group-\(id)", time: time, markers: [marker])
    }

    /// Linear time→pixel stub simulating zoom: `scale` points per minute.
    private func xFor(scale: CGFloat) -> (Date) -> CGFloat {
        { date in CGFloat(date.timeIntervalSince(base) / 60) * scale }
    }

    /// Constant-width footprint stub (content-independent) for the overlap tests.
    private func constantWidth(_ w: CGFloat) -> (ConsolidatedMarkerGroup) -> CGFloat {
        { _ in w }
    }

    private func minutes(of group: ConsolidatedMarkerGroup) -> Double {
        group.time.timeIntervalSince(base) / 60
    }

    // MARK: consolidateByOverlap — separation vs merge

    @Test("groups farther apart than width+gap stay separate")
    func fartherApartStaySeparate() {
        // width 60, gap 4 → mergeDistance (60+60)/2 + 4 = 64pt. At 1pt/min, a
        // 70-minute gap = 70pt ≥ 64 → no merge.
        let groups = [singleGroup("a", minute: 0), singleGroup("b", minute: 70)]
        let result = ConsolidatedMarkerGroup.consolidateByOverlap(
            groups, xFor: xFor(scale: 1), estimatedWidth: constantWidth(60), minGap: 4
        )
        #expect(result.count == 2)
    }

    @Test("groups closer than width+gap merge")
    func closerThanThresholdMerge() {
        // 50-minute gap = 50pt < 64 → merge.
        let groups = [singleGroup("a", minute: 0), singleGroup("b", minute: 50)]
        let result = ConsolidatedMarkerGroup.consolidateByOverlap(
            groups, xFor: xFor(scale: 1), estimatedWidth: constantWidth(60), minGap: 4
        )
        #expect(result.count == 1)
        #expect(result[0].markers.count == 2)
    }

    // MARK: merged-group identity, ordering, re-anchor

    @Test("merged group keeps the earlier id, concatenates markers in time order, re-anchors to median")
    func mergePreservesIdOrderAndMedian() {
        let groups = [
            singleGroup("a", minute: 0),
            singleGroup("b", minute: 10),
            singleGroup("c", minute: 20),
        ]
        let result = ConsolidatedMarkerGroup.consolidateByOverlap(
            groups, xFor: xFor(scale: 1), estimatedWidth: constantWidth(60), minGap: 4
        )
        #expect(result.count == 1)
        let merged = result[0]
        #expect(merged.id == "group-a")                       // earlier group's id survives
        #expect(merged.markers.map(\.id) == ["a", "b", "c"])  // concatenated in time order
        // median of [0, 10, 20] min → index count/2 = 1 → 10 min (current behavior)
        #expect(minutes(of: merged) == 10)
    }

    @Test("transitive chain merges into a single group")
    func transitiveChainMergesToOne() {
        let groups = (0..<5).map { singleGroup("m\($0)", minute: Double($0) * 10) }
        let result = ConsolidatedMarkerGroup.consolidateByOverlap(
            groups, xFor: xFor(scale: 1), estimatedWidth: constantWidth(60), minGap: 4
        )
        #expect(result.count == 1)
        #expect(result[0].markers.count == 5)
    }

    // MARK: the zoom-split regression (would have caught the old Stage-1 bug)

    @Test("same marker set merges when zoomed out and splits per-marker when zoomed in")
    func zoomSplitRegression() {
        // Five markers 10 min apart across an hour.
        let groups = (0..<5).map { singleGroup("m\($0)", minute: Double($0) * 10) }

        // Zoomed OUT (0.5pt/min): positions 0,5,10,15,20 — all within 64 → one chip.
        let zoomedOut = ConsolidatedMarkerGroup.consolidateByOverlap(
            groups, xFor: xFor(scale: 0.5), estimatedWidth: constantWidth(60), minGap: 4
        )
        #expect(zoomedOut.count == 1)
        #expect(zoomedOut[0].markers.count == 5)

        // Zoomed IN (20pt/min): positions 0,200,400,600,800 — every gap ≥ 64 →
        // one group per marker. This is the case the old fixed-window Stage 1
        // got exactly backwards (whole day → one chip at max zoom).
        let zoomedIn = ConsolidatedMarkerGroup.consolidateByOverlap(
            groups, xFor: xFor(scale: 20), estimatedWidth: constantWidth(60), minGap: 4
        )
        #expect(zoomedIn.count == 5)
        #expect(zoomedIn.allSatisfy { $0.markers.count == 1 })
    }

    @Test("empty input yields empty output")
    func emptyInputEmptyOutput() {
        let result = ConsolidatedMarkerGroup.consolidateByOverlap(
            [], xFor: xFor(scale: 1), estimatedWidth: constantWidth(60), minGap: 4
        )
        #expect(result.isEmpty)
    }

    // MARK: 64pt merge-threshold floor (fixed 88pt touch targets)

    @Test("merge threshold floor is pinned at the legacy 64pt")
    func mergeFloorPinned() {
        #expect(ConsolidatedMarkerGroup.minMergeDistance == 64)
    }

    @Test("two narrow 40pt chips at 45pt separation merge — the floor overrides the content-aware threshold")
    func narrowChipsFloorMerge() {
        // avg width + gap = (40+40)/2 + 4 = 44 < 45 would keep them separate,
        // but each chip carries a fixed 88pt centered touch target: unmerged at
        // 45pt, the later sibling's hit rect would cover the earlier chip's
        // visible half (tap on "5U" opens the neighbor's sheet). The 64pt floor
        // (legacy 60 + 4) caps hit-rect overlap at what main already shipped.
        let groups = [singleGroup("a", minute: 0), singleGroup("b", minute: 45)]
        let result = ConsolidatedMarkerGroup.consolidateByOverlap(
            groups, xFor: xFor(scale: 1), estimatedWidth: constantWidth(40), minGap: 4
        )
        #expect(result.count == 1)
        #expect(result[0].markers.count == 2)
    }

    // MARK: equality contract (stale-chip guard)

    @Test("groups with the same id but different marker counts are NOT equal (accretion must re-render)")
    func equalityIncludesMarkerCount() {
        // Merges preserve the first-in-cluster id, so a new entry accreting
        // into an on-screen cluster keeps the id but grows markers — id-only
        // equality would let SwiftUI skip re-rendering the summed label.
        let one = singleGroup("a", minute: 0)
        let two = ConsolidatedMarkerGroup(
            id: one.id, time: one.time,
            markers: one.markers + singleGroup("b", minute: 1).markers
        )
        #expect(one != two)
        #expect(one == ConsolidatedMarkerGroup(id: one.id, time: one.time.addingTimeInterval(60), markers: one.markers))
    }

    // MARK: merge distance uses the average of the two half-widths (design pin)

    @Test("merge threshold is the average of the two chips' widths plus gap")
    func mergeThresholdAveragesWidths() {
        // wide=100, narrow=40, gap=4 → mergeDistance (100+40)/2 + 4 = 74pt
        // (above the 64pt floor, so the content-aware threshold governs).
        let wide = singleGroup("wide", minute: 0)
        func widthByContent(_ g: ConsolidatedMarkerGroup) -> CGFloat {
            g.id == "group-wide" ? 100 : 40
        }

        // 70pt apart (< 74) → merge.
        let merged = ConsolidatedMarkerGroup.consolidateByOverlap(
            [wide, singleGroup("narrow", minute: 70)],
            xFor: xFor(scale: 1), estimatedWidth: widthByContent, minGap: 4
        )
        #expect(merged.count == 1)

        // 80pt apart (≥ 74) → separate.
        let separate = ConsolidatedMarkerGroup.consolidateByOverlap(
            [wide, singleGroup("narrow", minute: 80)],
            xFor: xFor(scale: 1), estimatedWidth: widthByContent, minGap: 4
        )
        #expect(separate.count == 2)
    }
}

// MARK: - Content-aware chip width estimate

@Suite("Content-aware chip width estimate (DMNC-1415)")
struct ChipWidthEstimateTests {
    private let t = Date(timeIntervalSince1970: 1_700_000_000)

    private func mk(_ type: EventMarkerType, _ value: Double) -> EventMarker {
        let id = UUID()
        return EventMarker(id: id.uuidString, time: t, type: type, label: "", rawValue: value, sourceID: id)
    }

    private func group(_ markers: [EventMarker]) -> ConsolidatedMarkerGroup {
        ConsolidatedMarkerGroup(id: "g", time: t, markers: markers)
    }

    @Test("layout constants are pinned")
    func constantsPinned() {
        #expect(ConsolidatedMarkerGroup.chipMonoCharWidth == 7)
        #expect(ConsolidatedMarkerGroup.chipIconWidth == 14)
        #expect(ConsolidatedMarkerGroup.chipIconTextGap == 4)
        #expect(ConsolidatedMarkerGroup.chipHorizontalPadding == 5)
    }

    @Test("a single 5U chip estimates narrower than the 60pt default")
    func singleChipUnderDefault() {
        let width = group([mk(.bolus, 5)]).estimatedChipWidth(isScored: false)
        // icon 14 + 1 gap (4) + "5U" 2 chars × 7 (14) + 2 × padding 5 (10) = 42
        #expect(width == 42)
        #expect(width < 60)
    }

    @Test("a triple-stack chip estimates wider than the 60pt default")
    func tripleStackOverDefault() {
        let width = group([
            mk(.bolus, 8), mk(.correction, 2), mk(.basal, 10),
            mk(.meal, 60), mk(.exercise, 45),
        ]).estimatedChipWidth(isScored: true)
        // widest row = insulin "8U"+"2Uc"+"10Ub" = 9 chars, 3 gaps:
        // 14 + 3×4 (12) + 9×7 (63) + 10 = 99
        // (scored meal row "★60g" = 5 effective chars → 14 + 4 + 35 + 10 = 63)
        #expect(width == 99)
        #expect(width > 60)
    }

    @Test("triple-stack estimates wider than a single small chip")
    func tripleWiderThanSingle() {
        let single = group([mk(.bolus, 5)]).estimatedChipWidth(isScored: false)
        let triple = group([
            mk(.bolus, 8), mk(.correction, 2), mk(.basal, 10),
            mk(.meal, 60), mk(.exercise, 45),
        ]).estimatedChipWidth(isScored: false)
        #expect(triple > single)
    }

    @Test("estimate is monotonic in label length")
    func monotonicInLabelLength() {
        // "5g" (2 chars) vs "500g" (4 chars) — longer label ⇒ wider chip.
        let short = group([mk(.meal, 5)]).estimatedChipWidth(isScored: false)
        let long = group([mk(.meal, 500)]).estimatedChipWidth(isScored: false)
        #expect(long > short)
    }

    @Test("the ★ score prefix widens the meal chip by two mono characters")
    func scorePrefixWidens() {
        // ★ renders from a fallback font wider than one mono advance → counts as 2.
        let g = group([mk(.meal, 60)])
        let plain = g.estimatedChipWidth(isScored: false)   // "60g"  (3 chars)
        let scored = g.estimatedChipWidth(isScored: true)   // "★60g" (3 + 2 effective chars)
        #expect(scored == plain + 2 * ConsolidatedMarkerGroup.chipMonoCharWidth)
    }
}
