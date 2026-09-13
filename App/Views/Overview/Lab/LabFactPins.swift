//
//  LabFactPins.swift
//  DOSBTS
//
//  Chart Lab (DMNC-1500 / P5): the numbered pins that tie a fact card to the
//  place on the curve it is talking about. Marks only — they draw, they never
//  hit-test (P0's errata: a `.chartOverlay` that claims the plot swallows both
//  the scroll and the selection). Tapping happens on the CARDS, which are
//  ordinary views under the chart.
//
//  The layout half is pure so the "two pins never sit on top of each other"
//  rule is pinned by tests rather than by eye.
//

import Charts
import SwiftUI

// MARK: - LabFactPin

struct LabFactPin: Identifiable, Equatable {
    let id: String
    /// 1-based, in the order the facts were RANKED — the same number the card
    /// carries, so "pin 2" and "card 2" are the same claim.
    let index: Int
    let fact: ChartFact
    /// Horizontal nudge (pt) for the number, so a crowd of anchors stays legible.
    let labelShift: CGFloat
}

// MARK: - LabFactPins

enum LabFactPins {
    // MARK: Configuration

    /// Anchors closer together than this would collide on screen at 24 h.
    static let crowdingWindow: TimeInterval = 20 * 60
    /// How far apart crowded labels are pushed.
    static let shiftStep: CGFloat = 10
    /// Where the pin heads sit, as a fraction of the y domain — just under the
    /// exercise strip (which owns 0.95…1.0).
    static let headPosition: Double = 0.93
    /// Gap between the reading and the foot of the stem, as a fraction of the y
    /// domain. A fraction, not a fixed 10: ten mg/dL and ten mmol/L are not the
    /// same distance.
    static let stemClearance: Double = 0.04
    static let headSymbolSize: CGFloat = 200

    // MARK: Layout (pure)

    /// Numbers the facts in rank order, then nudges any cluster of anchors that
    /// would overlap so the numbers stay readable. The nudge is symmetric about
    /// the cluster's centre, so a pair straddles its anchors rather than
    /// drifting off one of them.
    static func layout(_ facts: [ChartFact]) -> [LabFactPin] {
        guard !facts.isEmpty else { return [] }

        let ranked = facts.enumerated().map { (index: $0.offset + 1, fact: $0.element) }
        let byTime = ranked.sorted { $0.fact.anchor < $1.fact.anchor }

        var shifts: [String: CGFloat] = [:]
        var cluster: [(index: Int, fact: ChartFact)] = []

        func flush() {
            defer { cluster = [] }
            guard cluster.count > 1 else {
                if let only = cluster.first { shifts[only.fact.id] = 0 }
                return
            }
            let centre = Double(cluster.count - 1) / 2
            for (position, member) in cluster.enumerated() {
                shifts[member.fact.id] = CGFloat(Double(position) - centre) * shiftStep
            }
        }

        for entry in byTime {
            if let last = cluster.last,
               entry.fact.anchor.timeIntervalSince(last.fact.anchor) > crowdingWindow {
                flush()
            }
            cluster.append(entry)
        }
        flush()

        return ranked.map {
            LabFactPin(id: $0.fact.id, index: $0.index, fact: $0.fact, labelShift: shifts[$0.fact.id] ?? 0)
        }
    }

    /// Hypo onsets get their own full-height rule: the onset is the moment the
    /// whole Black Box card is reasoning about.
    static func isOnsetRule(_ fact: ChartFact) -> Bool {
        fact.kind == .hypoOnset
    }

    // MARK: Marks

    @ChartContentBuilder
    static func marks(facts: [ChartFact], series: LabChartSeries, yMax: Double) -> some ChartContent {
        ForEach(layout(facts)) { pin in
            // The nudge moves the STEM and the HEAD together, so a crowd of
            // anchors stays legible without the digit drifting off its own pin.
            // Offsetting only the annotation (what this PR did first) left two
            // heads drawn on top of each other with their numbers beside them.
            RuleMark(
                x: .value("Fact", pin.fact.anchor),
                yStart: .value("From", stemFoot(pin, series: series, yMax: yMax)),
                yEnd: .value("To", yMax * headPosition)
            )
            .foregroundStyle(AmberTheme.amber)
            .lineStyle(StrokeStyle(lineWidth: 1))
            .offset(x: pin.labelShift)

            PointMark(
                x: .value("Fact", pin.fact.anchor),
                y: .value("Pin", yMax * headPosition)
            )
            .symbolSize(headSymbolSize)
            .foregroundStyle(AmberTheme.amber)
            .offset(x: pin.labelShift)
            .annotation(
                position: .overlay,
                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
            ) {
                Text("\(pin.index)")
                    .font(DOSTypography.microLabel)
                    .foregroundStyle(AmberTheme.inkOnAmber)
                    .monospacedDigit()
            }

            if isOnsetRule(pin.fact) {
                RuleMark(x: .value("Onset", pin.fact.anchor))
                    .foregroundStyle(AmberTheme.cgaRed)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
    }

    // MARK: Private

    /// Just above the reading the pin is pointing at, or the floor when the
    /// anchor has no reading under it.
    private static func stemFoot(_ pin: LabFactPin, series: LabChartSeries, yMax: Double) -> Double {
        guard let reading = series.nearestGlucose(at: pin.fact.anchor) else { return 0 }
        return min(reading.value + yMax * stemClearance, yMax * headPosition)
    }
}
