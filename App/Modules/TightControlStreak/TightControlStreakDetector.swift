//
//  TightControlStreakDetector.swift
//  DOSBTS
//
//  U2 (DMNC-772): the pure, replay-safe detection engine for tight-control
//  streak celebrations. A single function over (readings, marker, now, config)
//  re-derives the current in-band run and re-arm eligibility from the readings
//  on every call — no detector state is stored except the dedup marker, so
//  re-processing the same history with the same marker yields no new celebration
//  (KTD2). Mirrors the IOBCalculator pure-engine pattern. App-only: its single
//  consumer is TightControlStreakMiddleware, and tests reach it via
//  `@testable import DOSBTSApp`.
//

import Foundation

// MARK: - TightControlConfig

/// Fixed detection thresholds (KTD5). Not user-configurable.
struct TightControlConfig {
    /// Inclusive lower bound of the tight-control band (mg/dL, internal value).
    let bandLow: Int
    /// Inclusive upper bound of the band (mg/dL).
    let bandHigh: Int
    /// Continuous in-band duration required to qualify (seconds).
    let requiredDuration: TimeInterval
    /// A gap between consecutive readings longer than this breaks the run (seconds).
    let gapThreshold: TimeInterval
    /// Hysteresis margin (mg/dL): a run must exceed the band by at least this much,
    /// for `rearmReadings` consecutive readings, before a new run can fire after a
    /// celebration.
    let hysteresisMargin: Int
    /// Consecutive beyond-margin readings required to re-arm.
    let rearmReadings: Int

    static let `default` = TightControlConfig(
        bandLow: 80,
        bandHigh: 120,
        requiredDuration: 2 * 60 * 60,
        gapThreshold: 12 * 60,
        hysteresisMargin: 5,
        rearmReadings: 2
    )

    /// Gap threshold = two missed readings at the sensor interval, floored at 12 min
    /// to absorb delivery jitter (KTD5). All other thresholds are fixed.
    static func resolved(sensorIntervalMinutes: Int) -> TightControlConfig {
        let gapSeconds = max(2 * sensorIntervalMinutes * 60, 12 * 60)
        return TightControlConfig(
            bandLow: 80,
            bandHigh: 120,
            requiredDuration: 2 * 60 * 60,
            gapThreshold: TimeInterval(gapSeconds),
            hysteresisMargin: 5,
            rearmReadings: 2
        )
    }
}

// MARK: - TightControlStreakDetector

enum TightControlStreakDetector {

    /// Returns whether a new qualifying streak should be celebrated, and that run's
    /// start (the dedup identity). Pure: `now` is injected — the engine never calls
    /// `Date()`. All time comparisons use reading timestamps.
    static func evaluate(
        readings: [SensorGlucose],
        lastCelebratedStreakStart: Date?,
        now: Date,
        config: TightControlConfig = .default
    ) -> (shouldCelebrate: Bool, celebratedStreakStart: Date?) {
        let sorted = readings.sorted { $0.timestamp < $1.timestamp }

        // The run must currently be in band and end at the latest reading.
        guard let last = sorted.last, isInBand(last.intGlucoseValue, config) else {
            return (false, nil)
        }

        // Walk backward to find the contiguous in-band run ending at `last`,
        // breaking on the first out-of-band reading or a gap beyond the threshold.
        var startIndex = sorted.count - 1
        var index = sorted.count - 1
        while index > 0 {
            let current = sorted[index]
            let previous = sorted[index - 1]
            let gap = current.timestamp.timeIntervalSince(previous.timestamp)
            if gap < 0 || gap > config.gapThreshold { break }
            if !isInBand(previous.intGlucoseValue, config) { break }
            startIndex = index - 1
            index -= 1
        }

        let runStart = sorted[startIndex].timestamp
        let runEnd = last.timestamp

        // The run must span the required continuous duration.
        guard runEnd.timeIntervalSince(runStart) >= config.requiredDuration else {
            return (false, nil)
        }

        // The run must reach the present: `now` is at or after the run start (else
        // the clock moved backward), and the latest reading is no older than the gap
        // threshold (else this is a stale/historical window, not a live streak).
        guard now >= runStart, now.timeIntervalSince(runEnd) <= config.gapThreshold else {
            return (false, nil)
        }

        // Dedup: the same run (identified by its start) celebrates at most once.
        if let marker = lastCelebratedStreakStart, marker == runStart {
            return (false, nil)
        }

        // Hysteresis re-arm: after a prior celebration, require `rearmReadings`
        // consecutive beyond-margin readings between the celebrated run and this one.
        // No prior fire → eligible immediately.
        if let marker = lastCelebratedStreakStart,
           !hasRearmed(sorted: sorted, marker: marker, runStart: runStart, config: config) {
            return (false, nil)
        }

        return (true, runStart)
    }

    // MARK: Helpers

    private static func isInBand(_ value: Int, _ config: TightControlConfig) -> Bool {
        value >= config.bandLow && value <= config.bandHigh
    }

    private static func isBeyondMargin(_ value: Int, _ config: TightControlConfig) -> Bool {
        value < config.bandLow - config.hysteresisMargin || value > config.bandHigh + config.hysteresisMargin
    }

    /// True if at least `rearmReadings` consecutive readings strictly between the
    /// celebrated run's start (`marker`) and the new run's start are beyond the margin.
    private static func hasRearmed(sorted: [SensorGlucose], marker: Date, runStart: Date, config: TightControlConfig) -> Bool {
        var consecutive = 0
        for reading in sorted where reading.timestamp > marker && reading.timestamp < runStart {
            if isBeyondMargin(reading.intGlucoseValue, config) {
                consecutive += 1
                if consecutive >= config.rearmReadings { return true }
            } else {
                consecutive = 0
            }
        }
        return false
    }
}
