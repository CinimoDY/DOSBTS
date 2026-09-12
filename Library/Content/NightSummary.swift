//
//  NightSummary.swift
//  DOSBTS
//
//  Chart Lab P1 (DMNC-1506) — the night, reduced to numbers and to the marks
//  the lab chart draws behind the trace.
//
//  Everything here is pure: the summary maths, the window definition and the
//  chart context are all testable without HealthKit, GRDB or a view. Shared
//  (`Library/` compiles into the widget), so no SwiftUI and no HealthKit.
//

import Foundation

// MARK: - NightWindow

/// The one window the lab's night tab asks for: the evening before at 20:00
/// through 10:00 on the chosen day. No shipping loader can produce this — meals
/// and insulin use the selected day or a rolling 24 h, notes and heart rate use
/// an exact day — which is the whole reason the window loader exists.
enum NightWindow {
    static let startHour = 20
    static let endHour = 10

    static func interval(for day: Date, calendar: Calendar = .current) -> DateInterval {
        let morning = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .hour, value: endHour, to: morning) ?? morning
        let evening = calendar.date(byAdding: .day, value: -1, to: morning) ?? morning
        let start = calendar.date(byAdding: .hour, value: startHour, to: evening) ?? evening
        return DateInterval(start: start, end: max(start, end))
    }

    /// Midnight inside the window, or nil if the window somehow does not cross
    /// one (it always does at 20:00 → 10:00, but the caller is not asked to
    /// trust that).
    static func midnight(in interval: DateInterval, calendar: Calendar = .current) -> Date? {
        let candidate = calendar.startOfDay(for: interval.end)
        guard candidate > interval.start, candidate < interval.end else { return nil }
        return candidate
    }
}

// MARK: - NightSummary

/// The night's headline numbers. Every glucose figure carries its `n`.
struct NightSummary: Equatable {
    let inBed: Date?
    let asleep: Date?
    let wake: Date?
    /// Minutes actually asleep — awake gaps removed, overlapping spans merged.
    let asleepMinutes: Int
    /// Awakenings BETWEEN falling asleep and waking. An awake span before you
    /// fell asleep is not an awakening.
    let awakeCount: Int
    let glucoseAtSleep: LabFigure?
    let glucoseAtWake: LabFigure?
    let riseByWake: LabFigure?

    static let empty = NightSummary(
        inBed: nil, asleep: nil, wake: nil, asleepMinutes: 0, awakeCount: 0,
        glucoseAtSleep: nil, glucoseAtWake: nil, riseByWake: nil
    )

    /// `unit` is the DISPLAY unit: the figures come out converted, with the
    /// unit string to match, so no caller has to convert a second time.
    static func make(sleep: [SleepSample], readings: [SensorGlucose], unit: GlucoseUnit) -> NightSummary {
        let asleepSpans = merge(sleep.filter { $0.stage.isAsleep }.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) })

        let inBed = sleep.map(\.start).min()
        let asleep = asleepSpans.first?.start
        let wake = asleepSpans.last?.end
        let asleepMinutes = Int(asleepSpans.reduce(0) { $0 + $1.duration } / 60)

        let awakeCount: Int
        if let asleep, let wake {
            awakeCount = sleep.filter { $0.stage == .awake && $0.start >= asleep && $0.end <= wake }.count
        } else {
            awakeCount = 0
        }

        guard let asleep, let wake, wake > asleep else {
            return NightSummary(
                inBed: inBed, asleep: asleep, wake: wake,
                asleepMinutes: asleepMinutes, awakeCount: awakeCount,
                glucoseAtSleep: nil, glucoseAtWake: nil, riseByWake: nil
            )
        }

        let between = readings
            .filter { $0.timestamp >= asleep && $0.timestamp <= wake }
            .sorted { $0.timestamp < $1.timestamp }

        let atSleep = nearest(to: asleep, in: readings)
        let atWake = nearest(to: wake, in: readings)
        let window = DateInterval(start: asleep, end: wake)

        return NightSummary(
            inBed: inBed,
            asleep: asleep,
            wake: wake,
            asleepMinutes: asleepMinutes,
            awakeCount: awakeCount,
            glucoseAtSleep: atSleep.map { figure(.glucose, mgdL: Double($0.glucoseValue), unit: unit, n: 1) },
            glucoseAtWake: atWake.map { figure(.glucose, mgdL: Double($0.glucoseValue), unit: unit, n: 1) },
            riseByWake: {
                guard let atSleep, let atWake, !between.isEmpty else { return nil }
                let delta = Double(atWake.glucoseValue - atSleep.glucoseValue)
                return figure(.delta, mgdL: delta, unit: unit, n: between.count, window: window)
            }()
        )
    }

    // MARK: Private

    /// Nearest reading within half an hour — a night's edges are soft, but not
    /// so soft that a reading two hours away can stand in for one.
    private static func nearest(to date: Date, in readings: [SensorGlucose], toleranceMinutes: Int = 30) -> SensorGlucose? {
        let tolerance = TimeInterval(toleranceMinutes * 60)
        return readings
            .filter { abs($0.timestamp.timeIntervalSince(date)) <= tolerance }
            .min { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) }
    }

    private static func figure(
        _ kind: LabFigure.Kind,
        mgdL: Double,
        unit: GlucoseUnit,
        n: Int,
        window: DateInterval? = nil
    ) -> LabFigure {
        LabFigure(
            kind: kind,
            value: unit == .mmolL ? mgdL.toMmolL() : mgdL,
            unit: unit.localizedDescription,
            n: n,
            window: window
        )
    }

    /// Union of overlapping spans, so two overlapping HealthKit samples cannot
    /// inflate the time asleep.
    static func merge(_ spans: [DateInterval]) -> [DateInterval] {
        let sorted = spans.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return [] }

        var merged: [DateInterval] = []
        for span in sorted.dropFirst() {
            if span.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, span.end))
            } else {
                merged.append(current)
                current = span
            }
        }
        merged.append(current)
        return merged
    }
}

// MARK: - LabNightHypoMark

/// The night's first low, labelled the way the prototype does: `T-0 62`.
struct LabNightHypoMark: Equatable {
    let time: Date
    /// Already in the display unit.
    let value: Double
    let label: String
}

// MARK: - LabMealRibbon

/// A meal's two-hour response, carried across the window's left edge when the
/// meal itself happened before it (the evening's dinner, on a night window).
struct LabMealRibbon: Equatable, Identifiable {
    let id: String
    /// Clamped into the drawn domain; `mealTime` keeps the truth.
    let start: Date
    let end: Date
    let mealTime: Date
    /// `+38 · 24 RDG` — the delta and the readings behind it, never a bare delta.
    let label: String
}

// MARK: - LabNightContext

/// Everything the `.nightContext` overlay arm draws, computed once, purely.
struct LabNightContext: Equatable {
    let sleepBand: DateInterval?
    let awakeGaps: [DateInterval]
    let midnight: Date?
    let hypo: LabNightHypoMark?

    static let empty = LabNightContext(sleepBand: nil, awakeGaps: [], midnight: nil, hypo: nil)

    /// - Parameters:
    ///   - alarmLow: the active profile's low, in mg/dL (the stored unit).
    ///   - glucoseUnit: the display unit the hypo label is rendered in.
    static func make(
        sleep: [SleepSample],
        readings: [SensorGlucose],
        interval: DateInterval,
        glucoseUnit: GlucoseUnit,
        alarmLow: Int,
        calendar: Calendar = .current
    ) -> LabNightContext {
        let asleepSpans = NightSummary.merge(
            sleep.filter { $0.stage.isAsleep }.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
        )

        let band: DateInterval? = {
            guard let first = asleepSpans.first, let last = asleepSpans.last else { return nil }
            return DateInterval(start: first.start, end: last.end)
        }()

        let gaps: [DateInterval] = {
            guard let band else { return [] }
            return sleep
                .filter { $0.stage == .awake && $0.start >= band.start && $0.end <= band.end && $0.end > $0.start }
                .map { DateInterval(start: $0.start, end: $0.end) }
                .sorted { $0.start < $1.start }
        }()

        let hypo: LabNightHypoMark? = readings
            .filter { interval.contains($0.timestamp) }
            .sorted { $0.timestamp < $1.timestamp }
            .first { $0.glucoseValue < alarmLow }
            .map { reading in
                LabNightHypoMark(
                    time: reading.timestamp,
                    value: glucoseUnit == .mmolL ? reading.glucoseValue.toMmolL() : Double(reading.glucoseValue),
                    label: "T-0 \(reading.glucoseValue.asGlucose(glucoseUnit: glucoseUnit))"
                )
            }

        return LabNightContext(
            sleepBand: band,
            awakeGaps: gaps,
            midnight: NightWindow.midnight(in: interval, calendar: calendar),
            hypo: hypo
        )
    }
}
