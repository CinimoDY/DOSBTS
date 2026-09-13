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

// MARK: - ResidualAnchors

/// Everything already logged that could explain an excursion. Points are
/// instants (a meal, a bolus, a note); intervals are things with a duration (a
/// workout), which explain a move anywhere inside them — a 90-minute ride that
/// starts an hour early and ends after the move still explains it.
struct ResidualAnchors: Equatable {
    let points: [Date]
    let intervals: [ClosedRange<Date>]

    init(points: [Date] = [], intervals: [ClosedRange<Date>] = []) {
        self.points = points
        self.intervals = intervals
    }
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

    // MARK: Anchors

    /// The ONE place the anchor set is built, so the chart's `?` marks and the
    /// row that opens the note can never disagree about what counts as logged.
    static func anchors(
        meals: [MealEntry],
        insulin: [InsulinDelivery],
        exercise: [ExerciseEntry],
        notes: [JournalNote]
    ) -> ResidualAnchors {
        ResidualAnchors(
            points: meals.map(\.timestamp)
                + insulin.map(\.starts)
                + notes.map(\.timestamp),
            // A workout is a window, not a moment. Ordered defensively: a
            // mis-entered entry with `endTime` before `startTime` must not trap
            // in `ClosedRange`.
            intervals: exercise.map {
                Swift.min($0.startTime, $0.endTime) ... Swift.max($0.startTime, $0.endTime)
            }
        )
    }

    // MARK: Detection

    static func detect(
        readings: [SensorGlucose],
        anchors: ResidualAnchors,
        regimes: [RegimeBand]
    ) -> [ResidualSegment] {
        let sorted = readings.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= minReadings else { return [] }

        // The tightest candidate from each start: the FIRST later reading that
        // crosses the threshold, and then the LATEST start that still reaches
        // it. Without that second step the segment begins at whatever flat
        // reading happened to be within 90 minutes — the `?` covers dead trace,
        // the note opens at the wrong time, and anchor suppression goes wide.
        var candidates: [Candidate] = []
        for i in sorted.indices {
            var j = i + 1
            while j < sorted.count,
                  sorted[j].timestamp.timeIntervalSince(sorted[i].timestamp) <= maxSpanSeconds {
                if abs(sorted[j].glucoseValue - sorted[i].glucoseValue) >= minDeltaMgDL {
                    var start = i
                    while start + 1 < j,
                          abs(sorted[j].glucoseValue - sorted[start + 1].glucoseValue) >= minDeltaMgDL {
                        start += 1
                    }
                    candidates.append(Candidate(
                        start: start,
                        end: j,
                        isRising: sorted[j].glucoseValue > sorted[start].glucoseValue
                    ))
                    break
                }
                j += 1
            }
        }
        guard !candidates.isEmpty else { return [] }

        // One excursion, one `?` — but only in the SAME direction. Merging a
        // rise into the fall that follows it produces a segment whose ends
        // happen to match, i.e. `UNEXPLAINED +0`, which says nothing.
        var merged: [Candidate] = []
        for candidate in candidates.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last,
               last.isRising == candidate.isRising,
               candidate.start <= last.end {
                merged[merged.count - 1].end = Swift.max(last.end, candidate.end)
            } else {
                merged.append(candidate)
            }
        }

        return merged.compactMap { range -> ResidualSegment? in
            let slice = Array(sorted[range.start ... range.end])
            guard slice.count >= minReadings, !hasNoiseStep(slice) else { return nil }
            guard let first = slice.first else { return nil }

            // Measured to the EXTREMUM in the direction of the move, never to
            // the last reading: a spike that comes back down inside the window
            // is still a +45 excursion.
            let extremum = range.isRising
                ? slice.max(by: { $0.glucoseValue < $1.glucoseValue })
                : slice.min(by: { $0.glucoseValue < $1.glucoseValue })
            guard let extremum else { return nil }

            let delta = extremum.glucoseValue - first.glucoseValue
            // Merging can only widen a window, so the threshold is re-checked
            // against what the merged segment actually claims.
            guard abs(delta) >= minDeltaMgDL else { return nil }

            let from = first.timestamp
            let to = extremum.timestamp
            let explainedFrom = from.addingTimeInterval(-anchorLookbackSeconds)

            // Anything logged in (or overlapping) the window IS the explanation.
            guard !anchors.points.contains(where: { $0 >= explainedFrom && $0 <= to }) else { return nil }
            guard !anchors.intervals.contains(where: {
                $0.lowerBound <= to && $0.upperBound >= explainedFrom
            }) else { return nil }
            guard !regimes.contains(where: { $0.start <= to && $0.end >= explainedFrom }) else { return nil }

            return ResidualSegment(
                id: "residual-\(Int(from.timeIntervalSince1970))",
                start: from,
                end: to,
                deltaMgDL: delta,
                n: sorted.filter { $0.timestamp >= from && $0.timestamp <= to }.count
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

    /// A candidate excursion, as indices into the sorted readings.
    private struct Candidate {
        let start: Int
        var end: Int
        let isRising: Bool
    }

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
