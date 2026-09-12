//
//  LabWindow.swift
//  DOSBTS
//
//  Chart Lab (DMNC-1506 / DMNC-1500) — the whole-system window.
//
//  One loader fetches EVERY stream for ONE interval and reports, per stream,
//  whether it is loaded, empty, unavailable or failed. That is what lets a lab
//  tab span midnight: the shipping loaders each use their own window rule
//  (selected day, rolling 24 h, exact day, DIA lookback), so no single existing
//  path can show a night whole.
//
//  Pure and target-shared: `Library/` compiles into the widget, so there is no
//  UIKit, no HealthKit and no SwiftUI in this file.
//

import Foundation

// MARK: - LabStream

/// One data stream the lab can ask for. The `label` is the POST strip's cell
/// name, so it is short and stable.
enum LabStream: String, CaseIterable, Codable {
    case glucose
    case bloodGlucose
    case meals
    case insulin
    case iob
    case exercise
    case heartRate
    case sleep
    case journalNotes
    case steps

    /// How a stream draws: a trace, a point in time, or a span.
    enum Shape {
        case continuous
        case event
        case interval
    }

    /// Where the rows come from. HealthKit streams can be denied; GRDB streams
    /// cannot, which is why only the HealthKit ones can report `.unavailable`.
    enum Source {
        case grdb
        case healthKit
    }

    var shape: Shape {
        switch self {
        case .glucose, .iob, .heartRate, .steps:
            return .continuous
        case .bloodGlucose, .meals, .insulin, .journalNotes:
            return .event
        case .exercise, .sleep:
            return .interval
        }
    }

    var source: Source {
        switch self {
        case .heartRate, .sleep, .steps:
            return .healthKit
        case .glucose, .bloodGlucose, .meals, .insulin, .iob, .exercise, .journalNotes:
            return .grdb
        }
    }

    /// POST strip cell name — at most five characters, unique across the set.
    var label: String {
        switch self {
        case .glucose: return "GLU"
        case .bloodGlucose: return "BG"
        case .meals: return "MEAL"
        case .insulin: return "INS"
        case .iob: return "IOB"
        case .exercise: return "EX"
        case .heartRate: return "HR"
        case .sleep: return "SLEEP"
        case .journalNotes: return "NOTES"
        case .steps: return "STEPS"
        }
    }
}

// MARK: - SleepSample

/// One HealthKit sleep-analysis span, reduced to what the lab draws.
struct SleepSample: Equatable, Codable, Identifiable {
    /// Raw values are stable so a sample can be persisted or logged.
    enum Stage: Int, Codable {
        case awake = 0
        case rem = 1
        case core = 2
        case deep = 3
        case inBed = 4
        case unspecified = 5

        /// `inBed` and `awake` are time in bed, not time asleep — the night's
        /// "ASLEEP" figure must not count them.
        var isAsleep: Bool {
            switch self {
            case .rem, .core, .deep, .unspecified: return true
            case .awake, .inBed: return false
            }
        }

        /// `HKCategoryValueSleepAnalysis` raw values: inBed 0, asleepUnspecified 1,
        /// awake 2, asleepCore 3, asleepDeep 4, asleepREM 5. Kept as an `Int`
        /// mapping so it is pure — `Library/` must not import HealthKit.
        init(healthKitValue: Int) {
            switch healthKitValue {
            case 0: self = .inBed
            case 1: self = .unspecified
            case 2: self = .awake
            case 3: self = .core
            case 4: self = .deep
            case 5: self = .rem
            default: self = .unspecified
            }
        }

        /// Lane cell height weight, deepest = tallest (the prototype's lane).
        var laneWeight: Double {
            switch self {
            case .deep: return 1.0
            case .core: return 0.7
            case .rem: return 0.45
            case .unspecified: return 0.7
            case .awake: return 0.25
            case .inBed: return 0.15
            }
        }
    }

    let start: Date
    let end: Date
    let stage: Stage

    var id: String { "\(start.timeIntervalSince1970)-\(stage.rawValue)" }

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

// MARK: - HeartRateSample

/// `state.heartRateSeries` is `[(Date, Double)]`; tuples are not `Equatable`
/// enough to drive a single `.onChange(of: inputs)`, so the lab carries a named
/// struct instead. Shared (not App-local) because the window snapshot is.
struct HeartRateSample: Equatable, Codable {
    let time: Date
    let bpm: Double
}

// MARK: - LabStreamStatus

/// What the POST strip says about one stream.
enum LabStreamStatus: Equatable {
    /// Rows came back; the interval is the span they actually cover.
    case loaded(DateInterval)
    /// The fetch succeeded and returned nothing.
    case empty
    /// Never asked for (HealthKit `.notDetermined`, or a stream this build does
    /// not read at all). HealthKit never reveals a READ denial, so once the user
    /// has answered the prompt a denial is indistinguishable from "no data" and
    /// shows as `.empty` — `.unavailable` means "we have not asked".
    case unavailable
    /// The fetch threw.
    case failed
}

// MARK: - LabStreamAvailability

/// What the caller knows about a HealthKit stream BEFORE looking at its rows.
enum LabStreamAvailability: Equatable {
    case available
    case unavailable
    case failed
}

// MARK: - LabWindowRaw

/// The GRDB half of a window, exactly as one `asyncRead` returns it.
struct LabWindowRaw: Equatable {
    let readings: [SensorGlucose]
    let bloodGlucose: [BloodGlucose]
    let meals: [MealEntry]
    let deliveries: [InsulinDelivery]
    /// Deliveries reaching back a full DIA so an evening bolus's IOB tail can
    /// be drawn across midnight.
    let iobDeliveries: [InsulinDelivery]
    let exercise: [ExerciseEntry]
    let notes: [JournalNote]

    static let empty = LabWindowRaw(
        readings: [], bloodGlucose: [], meals: [],
        deliveries: [], iobDeliveries: [], exercise: [], notes: []
    )
}

// MARK: - LabWindowSnapshot

/// Every stream for one interval, plus what happened to each of them.
struct LabWindowSnapshot: Equatable {
    let interval: DateInterval
    let readings: [SensorGlucose]
    let bloodGlucose: [BloodGlucose]
    let meals: [MealEntry]
    let deliveries: [InsulinDelivery]
    let iobDeliveries: [InsulinDelivery]
    let exercise: [ExerciseEntry]
    let notes: [JournalNote]
    let heartRate: [HeartRateSample]
    let sleep: [SleepSample]
    let status: [LabStream: LabStreamStatus]

    /// The span the returned rows actually cover, per stream. Absent for a
    /// stream with no rows. Compared against the requested interval, this is
    /// what catches a secondary fetch whose window is narrower than the primary
    /// one (grdb-mismatched-fetch-windows-silent-zero-result-20260704).
    var coverage: [LabStream: DateInterval] {
        var result: [LabStream: DateInterval] = [:]
        for (stream, state) in status {
            if case .loaded(let span) = state {
                result[stream] = span
            }
        }
        return result
    }

    static func empty(interval: DateInterval, status: LabStreamStatus = .empty) -> LabWindowSnapshot {
        var table: [LabStream: LabStreamStatus] = [:]
        for stream in LabStream.allCases {
            table[stream] = status
        }
        return LabWindowSnapshot(
            interval: interval,
            readings: [], bloodGlucose: [], meals: [], deliveries: [],
            iobDeliveries: [], exercise: [], notes: [],
            heartRate: [], sleep: [],
            status: table
        )
    }

    /// Pure assembly, so the coverage contract is testable without a database
    /// or a HealthKit authorisation dialog.
    static func assemble(
        raw: LabWindowRaw,
        interval: DateInterval,
        heartRate: [HeartRateSample],
        sleep: [SleepSample],
        heartRateAvailability: LabStreamAvailability,
        sleepAvailability: LabStreamAvailability
    ) -> LabWindowSnapshot {
        var status: [LabStream: LabStreamStatus] = [
            .glucose: span(raw.readings.map(\.timestamp)),
            .bloodGlucose: span(raw.bloodGlucose.map(\.timestamp)),
            .meals: span(raw.meals.map(\.timestamp)),
            .insulin: span(raw.deliveries.map(\.starts)),
            .iob: span(raw.iobDeliveries.map(\.starts)),
            .exercise: span(raw.exercise.flatMap { [$0.startTime, $0.endTime] }),
            .journalNotes: span(raw.notes.map(\.timestamp)),
            .heartRate: resolve(heartRateAvailability, times: heartRate.map(\.time)),
            .sleep: resolve(sleepAvailability, times: sleep.flatMap { [$0.start, $0.end] }),
            // Not read in this build at all — never asked, so never `.empty`.
            .steps: .unavailable,
        ]
        // Defensive: a case added to `LabStream` without a row here would make
        // its POST cell vanish rather than say something honest.
        for stream in LabStream.allCases where status[stream] == nil {
            status[stream] = .unavailable
        }

        return LabWindowSnapshot(
            interval: interval,
            readings: raw.readings,
            bloodGlucose: raw.bloodGlucose,
            meals: raw.meals,
            deliveries: raw.deliveries,
            iobDeliveries: raw.iobDeliveries,
            exercise: raw.exercise,
            notes: raw.notes,
            heartRate: heartRate,
            sleep: sleep,
            status: status
        )
    }

    private static func span(_ times: [Date]) -> LabStreamStatus {
        guard let first = times.min(), let last = times.max() else { return .empty }
        return .loaded(DateInterval(start: first, end: max(first, last)))
    }

    private static func resolve(_ availability: LabStreamAvailability, times: [Date]) -> LabStreamStatus {
        switch availability {
        case .unavailable: return .unavailable
        case .failed: return .failed
        case .available: return span(times)
        }
    }
}

// MARK: - LabCoverageCell

/// One POST-strip cell: which stream, what it says, and how loudly.
struct LabCoverageCell: Equatable, Identifiable {
    enum Tone: Equatable {
        case loaded
        case empty
        case unavailable
        case failed
    }

    let stream: LabStream
    let label: String
    let value: String
    let tone: Tone

    var id: String { stream.rawValue }

    /// `GLU 96%` — what the strip renders.
    var text: String { "\(label) \(value)" }
}

// MARK: - LabCoverage

/// The POST strip's model. Pure, so "what does the strip say" is a test, not a
/// screenshot.
enum LabCoverage {
    /// The prototype's order. Deliberately not `LabStream.allCases`: the strip
    /// is a reading order, not a declaration order.
    static let postOrder: [LabStream] = [
        .glucose, .insulin, .meals, .exercise, .heartRate, .sleep, .steps, .journalNotes,
    ]

    static func cells(snapshot: LabWindowSnapshot, sensorIntervalMinutes: Int) -> [LabCoverageCell] {
        postOrder.map { stream in
            let status = snapshot.status[stream] ?? .unavailable
            switch status {
            case .unavailable:
                return LabCoverageCell(stream: stream, label: stream.label, value: "n/a", tone: .unavailable)
            case .failed:
                return LabCoverageCell(stream: stream, label: stream.label, value: "!", tone: .failed)
            case .empty:
                return LabCoverageCell(stream: stream, label: stream.label, value: "—", tone: .empty)
            case .loaded:
                return LabCoverageCell(
                    stream: stream,
                    label: stream.label,
                    value: loadedValue(stream, snapshot: snapshot, sensorIntervalMinutes: sensorIntervalMinutes),
                    tone: .loaded
                )
            }
        }
    }

    /// Readings actually stored over the readings the interval could hold at the
    /// sensor's cadence. Clamped to 100%: a duplicate row is a data quirk, not a
    /// claim that the night was more than fully covered.
    static func glucosePercent(readings: Int, interval: DateInterval, sensorIntervalMinutes: Int) -> Int {
        let cadence = max(1, sensorIntervalMinutes)
        let expected = interval.duration / Double(cadence * 60)
        guard expected > 0 else { return 0 }
        let percent = (Double(readings) / expected * 100).rounded()
        return min(100, max(0, Int(percent)))
    }

    private static func loadedValue(
        _ stream: LabStream,
        snapshot: LabWindowSnapshot,
        sensorIntervalMinutes: Int
    ) -> String {
        switch stream {
        case .glucose:
            return "\(glucosePercent(readings: snapshot.readings.count, interval: snapshot.interval, sensorIntervalMinutes: sensorIntervalMinutes))%"
        case .insulin:
            return "\(snapshot.deliveries.count)"
        case .meals:
            return "\(snapshot.meals.count)"
        case .exercise:
            return "\(snapshot.exercise.count)"
        case .journalNotes:
            return "\(snapshot.notes.count)"
        case .bloodGlucose:
            return "\(snapshot.bloodGlucose.count)"
        case .iob:
            return "\(snapshot.iobDeliveries.count)"
        // Sampled streams: a count would be a cadence, not a coverage.
        case .heartRate, .sleep, .steps:
            return "✓"
        }
    }
}
