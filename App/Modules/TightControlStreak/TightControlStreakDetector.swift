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

/// Fixed detection thresholds (KTD5). The 80–120 mg/dL band is fixed by design
/// (DMNC-1317) — do NOT make bandLow/bandHigh user-configurable.
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

    /// Gap threshold = two missed readings at the sensor interval, floored at 12 min
    /// to absorb delivery jitter (KTD5). All other thresholds are fixed — this is the
    /// single source of those literals; `.default` derives from it.
    static func resolved(sensorIntervalMinutes: Int) -> TightControlConfig {
        let gapSeconds = max(2 * sensorIntervalMinutes * 60, 12 * 60)
        return TightControlConfig(
            bandLow: 80,   // fixed by design — DMNC-1317
            bandHigh: 120, // fixed by design — DMNC-1317
            requiredDuration: 2 * 60 * 60,
            gapThreshold: TimeInterval(gapSeconds),
            hysteresisMargin: 5,
            rearmReadings: 2
        )
    }

    /// Default for tests and default parameters. A 6-min interval yields the 12-min gap
    /// floor (`max(2×6, 12)`), matching the production minimum.
    static let `default` = TightControlConfig.resolved(sensorIntervalMinutes: 6)

    /// Formatted band range for display (e.g. "80–120" or "4.4–6.7"). Unit-aware single
    /// source of truth — call sites must not inline this formatting.
    func bandDescription(glucoseUnit: GlucoseUnit) -> String {
        "\(bandLow.asGlucose(glucoseUnit: glucoseUnit))–\(bandHigh.asGlucose(glucoseUnit: glucoseUnit))"
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
        guard let startIndex = contiguousInBandRunStartIndex(sorted: sorted, config: config) else {
            return (false, nil)
        }

        let runStart = sorted[startIndex].timestamp
        let runEnd = sorted[sorted.count - 1].timestamp

        // The run must span the required continuous duration.
        guard runEnd.timeIntervalSince(runStart) >= config.requiredDuration else {
            return (false, nil)
        }

        // The run must reach the present (see `runExtendsToNow`).
        guard runExtendsToNow(runStart: runStart, runEnd: runEnd, now: now, config: config) else {
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

    /// The start of the contiguous in-band run currently ending at the latest reading
    /// and extending to `now`, regardless of its duration — or nil if there is no live
    /// in-band run. Used to "consume" the in-progress run when Celebrations is
    /// re-enabled so re-enabling cannot insta-fire mid-run (AE9).
    static func currentRunStart(
        readings: [SensorGlucose],
        now: Date,
        config: TightControlConfig = .default
    ) -> Date? {
        let sorted = readings.sorted { $0.timestamp < $1.timestamp }
        guard let startIndex = contiguousInBandRunStartIndex(sorted: sorted, config: config) else {
            return nil
        }
        let runStart = sorted[startIndex].timestamp
        let runEnd = sorted[sorted.count - 1].timestamp
        guard runExtendsToNow(runStart: runStart, runEnd: runEnd, now: now, config: config) else {
            return nil
        }
        return runStart
    }

    // MARK: Helpers

    /// Index of the start of the contiguous in-band run ending at the latest reading,
    /// breaking on the first out-of-band reading or a gap beyond the threshold. nil if
    /// there are no readings or the latest reading is out of band.
    private static func contiguousInBandRunStartIndex(sorted: [SensorGlucose], config: TightControlConfig) -> Int? {
        guard let lastIndex = sorted.indices.last, isInBand(sorted[lastIndex].intGlucoseValue, config) else {
            return nil
        }
        var startIndex = lastIndex
        var index = lastIndex
        while index > 0 {
            let gap = sorted[index].timestamp.timeIntervalSince(sorted[index - 1].timestamp)
            if gap < 0 || gap > config.gapThreshold { break }
            if !isInBand(sorted[index - 1].intGlucoseValue, config) { break }
            startIndex = index - 1
            index -= 1
        }
        return startIndex
    }

    /// The run reaches the present: `now` is at or after the run start (else the clock
    /// moved backward) and the latest reading is no older than the gap threshold (else
    /// this is a stale/historical window, not a live streak).
    private static func runExtendsToNow(runStart: Date, runEnd: Date, now: Date, config: TightControlConfig) -> Bool {
        now >= runStart && now.timeIntervalSince(runEnd) <= config.gapThreshold
    }

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
