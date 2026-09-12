//
//  LabResidualDetector.swift
//  DOSBTS
//
//  Chart Lab P2 (DMNC-1501). A residual is an excursion with nothing logged
//  against it — a rise or fall big enough to matter, inside a span short enough
//  to have a cause, with no meal, bolus, exercise, note or regime anywhere near
//  it. The chart draws it as a `?`, and tapping the `?` opens the note sheet at
//  the excursion's start.
//
//  It is a QUESTION, never a diagnosis. The lab does not guess why.
//
//  Pure Foundation: no SwiftUI, no store.
//

import Foundation

// MARK: - ResidualSegment

struct ResidualSegment: Identifiable, Equatable {
    let id: String
    let start: Date
    let end: Date
    /// Signed, mg/dL — the raw sensor scale, converted only at render time.
    let deltaMgDL: Int
    /// Readings inside `[start, end]`. Shipped on the label with every number.
    let n: Int
}

// MARK: - ResidualDetector

enum ResidualDetector {
    // MARK: Thresholds (test-pinned)

    /// Smaller than this is a wobble, not an excursion.
    static let minDeltaMgDL = 40
    /// Longer than this and "the cause" stops being a single thing.
    static let maxSpanSeconds: TimeInterval = 90 * 60
    /// An anchor slightly BEFORE the excursion still explains it (a meal starts
    /// working before the trace moves).
    static let anchorLookbackSeconds: TimeInterval = 30 * 60
    /// Fewer readings than this is a sensor artefact, not a shape.
    static let minReadings = 4
    /// A step bigger than this per 5 minutes is compression or a restart, not
    /// physiology. Longer gaps get proportionally more allowance.
    static let maxStepMgDLPer5Min = 25.0

    // MARK: Detection

    static func detect(
        readings: [SensorGlucose],
        anchors: [Date],
        regimes: [RegimeBand]
    ) -> [ResidualSegment] {
        let sorted = readings.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= minReadings else { return [] }

        // The tightest candidate from each start: the FIRST later reading that
        // crosses the threshold, so one long ramp does not also produce every
        // longer superset of itself.
        var candidates: [(start: Int, end: Int)] = []
        for i in sorted.indices {
            var j = i + 1
            while j < sorted.count,
                  sorted[j].timestamp.timeIntervalSince(sorted[i].timestamp) <= maxSpanSeconds {
                if abs(sorted[j].glucoseValue - sorted[i].glucoseValue) >= minDeltaMgDL {
                    candidates.append((start: i, end: j))
                    break
                }
                j += 1
            }
        }
        guard !candidates.isEmpty else { return [] }

        // One excursion, one `?`. Candidates arrive in ascending start order.
        var merged: [(start: Int, end: Int)] = []
        for candidate in candidates {
            if let last = merged.last, candidate.start <= last.end {
                merged[merged.count - 1].end = max(last.end, candidate.end)
            } else {
                merged.append(candidate)
            }
        }

        return merged.compactMap { range -> ResidualSegment? in
            let slice = Array(sorted[range.start ... range.end])
            guard slice.count >= minReadings, !hasNoiseStep(slice) else { return nil }

            guard let first = slice.first, let last = slice.last else { return nil }
            let from = first.timestamp
            let to = last.timestamp
            let explainedFrom = from.addingTimeInterval(-anchorLookbackSeconds)

            // Anything logged in (or overlapping) the window IS the explanation.
            guard !anchors.contains(where: { $0 >= explainedFrom && $0 <= to }) else { return nil }
            guard !regimes.contains(where: { $0.start <= to && $0.end >= explainedFrom }) else { return nil }

            return ResidualSegment(
                id: "residual-\(Int(from.timeIntervalSince1970))",
                start: from,
                end: to,
                deltaMgDL: last.glucoseValue - first.glucoseValue,
                n: slice.count
            )
        }
    }

    /// The label, always carrying its `n`. `TAP TO NOTE` is an invitation, not
    /// an instruction about treatment.
    static func label(for segment: ResidualSegment, glucoseUnit: GlucoseUnit) -> String {
        let sign = segment.deltaMgDL < 0 ? "-" : "+"
        let magnitude = abs(segment.deltaMgDL).asGlucose(glucoseUnit: glucoseUnit)
        return "UNEXPLAINED \(sign)\(magnitude) · \(segment.n) RDG · TAP TO NOTE"
    }

    // MARK: Private

    /// True when any consecutive pair moves further than the sensor plausibly
    /// can in the time between them.
    private static func hasNoiseStep(_ slice: [SensorGlucose]) -> Bool {
        for index in 1 ..< slice.count {
            let gapMinutes = slice[index].timestamp.timeIntervalSince(slice[index - 1].timestamp) / 60
            let allowance = maxStepMgDLPer5Min * max(1, gapMinutes / 5)
            if Double(abs(slice[index].glucoseValue - slice[index - 1].glucoseValue)) > allowance {
                return true
            }
        }
        return false
    }
}
