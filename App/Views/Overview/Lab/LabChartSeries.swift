//
//  LabChartSeries.swift
//  DOSBTS
//
//  Chart Lab (DMNC-1500) series model + builder. Pure: no SwiftUI, no store, no
//  database. `LabChartInputs` is the ONE place the lab reads `DirectState` for
//  series data, taken as a main-actor snapshot; `LabChartSeriesBuilder.build`
//  then runs safely on a background queue (the chart models are not `Sendable`,
//  so the snapshot pattern from ChartView.swift:880-923 is what crosses the
//  queue boundary — never `Task.detached`).
//

import Foundation

// MARK: - HeartRateSample

/// `state.heartRateSeries` is `[(Date, Double)]`; tuples are not `Equatable`
/// enough to drive a single `.onChange(of: inputs)`, so the lab carries a named
/// struct instead.
struct HeartRateSample: Equatable {
    let time: Date
    let bpm: Double
}

// MARK: - IOBSample

struct IOBSample: Equatable {
    let date: Date
    let total: Double
    let mealSnack: Double
    let corrBasal: Double
}

// MARK: - LabChartInputs

/// Main-actor snapshot of everything the lab chart draws from. `Equatable` so a
/// single `.onChange(of:)` replaces the shipping chart's nine.
struct LabChartInputs: Equatable {
    let sensorGlucose: [SensorGlucose]
    let bloodGlucose: [BloodGlucose]
    let meals: [MealEntry]
    let insulin: [InsulinDelivery]
    let iobDeliveries: [InsulinDelivery]
    let exercise: [ExerciseEntry]
    let heartRate: [HeartRateSample]
    let glucoseUnit: GlucoseUnit
    let alarmLow: Int
    let alarmHigh: Int
    let bolusPreset: InsulinPreset
    let basalDIAMinutes: Int
    /// `DirectConfig.showSmoothedGlucose && state.showSmoothedGlucose`
    let showSmoothed: Bool
    let smoothThreshold: Date
    let selectedDate: Date?
    let overlays: Set<ChartLabOverlay>

    /// The ONLY place the lab reads `store.state` for series data.
    init(state: DirectState, overlays: Set<ChartLabOverlay>) {
        self.sensorGlucose = state.sensorGlucoseValues
        self.bloodGlucose = state.bloodGlucoseValues
        self.meals = state.mealEntryValues
        self.insulin = state.insulinDeliveryValues
        self.iobDeliveries = state.iobDeliveries
        self.exercise = state.exerciseEntryValues
        self.heartRate = state.heartRateSeries.map { HeartRateSample(time: $0.0, bpm: $0.1) }
        self.glucoseUnit = state.glucoseUnit
        self.alarmLow = state.alarmLow
        self.alarmHigh = state.alarmHigh
        self.bolusPreset = state.bolusInsulinPreset
        self.basalDIAMinutes = state.basalDIAMinutes
        self.showSmoothed = DirectConfig.showSmoothedGlucose && state.showSmoothedGlucose
        // `state.smoothThreshold` is `Date() - n`, i.e. a different value on every
        // read. Floored to the minute it can still move an equality check, but at
        // most once a minute instead of on every render.
        self.smoothThreshold = state.smoothThreshold.toRounded(on: 1, .minute)
        self.selectedDate = state.selectedDate
        self.overlays = overlays
    }

    /// Memberwise init for tests and previews.
    init(
        sensorGlucose: [SensorGlucose],
        bloodGlucose: [BloodGlucose],
        meals: [MealEntry],
        insulin: [InsulinDelivery],
        iobDeliveries: [InsulinDelivery],
        exercise: [ExerciseEntry],
        heartRate: [HeartRateSample],
        glucoseUnit: GlucoseUnit,
        alarmLow: Int,
        alarmHigh: Int,
        bolusPreset: InsulinPreset,
        basalDIAMinutes: Int,
        showSmoothed: Bool,
        smoothThreshold: Date,
        selectedDate: Date?,
        overlays: Set<ChartLabOverlay>
    ) {
        self.sensorGlucose = sensorGlucose
        self.bloodGlucose = bloodGlucose
        self.meals = meals
        self.insulin = insulin
        self.iobDeliveries = iobDeliveries
        self.exercise = exercise
        self.heartRate = heartRate
        self.glucoseUnit = glucoseUnit
        self.alarmLow = alarmLow
        self.alarmHigh = alarmHigh
        self.bolusPreset = bolusPreset
        self.basalDIAMinutes = basalDIAMinutes
        self.showSmoothed = showSmoothed
        self.smoothThreshold = smoothThreshold
        self.selectedDate = selectedDate
        self.overlays = overlays
    }
}

// MARK: - LabRangeSummary

/// Aggregate behind the A→B readout. Every derived number ships with the sample
/// size it came from (`readings`) — a lab number without its `n` is a claim, and
/// the lab never makes claims.
struct LabRangeSummary: Equatable {
    /// All glucose values are in the user's display unit, as plotted.
    let first: Double?
    let last: Double?
    let min: Double?
    let max: Double?
    let delta: Double?
    let readings: Int
    let carbsGrams: Double
    /// Bolus units inside the window. Basal is excluded — it is a background
    /// rate, not something "taken in" at a point in time.
    let insulinUnits: Double
    let heartRateFirst: Double?
    let heartRateLast: Double?

    static let none = LabRangeSummary(
        first: nil, last: nil, min: nil, max: nil, delta: nil,
        readings: 0, carbsGrams: 0, insulinUnits: 0,
        heartRateFirst: nil, heartRateLast: nil
    )
}

// MARK: - LabChartSeries

struct LabChartSeries {
    var domainStart: Date
    var domainEnd: Date
    /// Flat, time-sorted glucose trace. Kept alongside the segments because the
    /// segments deliberately duplicate boundary points (`segmentGlucoseSeries`),
    /// which would inflate the readout's `n`.
    var glucose: [GlucoseDatapoint]
    var glucoseSegments: [GlucoseSegment]
    /// Minute-rounded keys, first wins (mirrors ChartView.swift:829-833).
    var glucoseByMinute: [Date: GlucoseDatapoint]
    var bloodGlucose: [GlucoseDatapoint]
    var insulin: [InsulinDatapoint]
    var iob: [IOBSample]
    var meals: [MealDatapoint]
    var exercise: [ExerciseDatapoint]
    var heartRate: [HeartRateSample]

    var readingCount: Int { glucose.count }

    var isEmpty: Bool { glucoseSegments.isEmpty && bloodGlucose.isEmpty }

    static let empty = LabChartSeries.blank(at: Date())

    static func blank(at date: Date) -> LabChartSeries {
        LabChartSeries(
            domainStart: date,
            domainEnd: date.addingTimeInterval(60 * 60),
            glucose: [],
            glucoseSegments: [],
            glucoseByMinute: [:],
            bloodGlucose: [],
            insulin: [],
            iob: [],
            meals: [],
            exercise: [],
            heartRate: []
        )
    }

    /// ±tolerance minute probe, nearest first — same shape as
    /// `ChartView.nearestHeartRate` (:1011-1024).
    func nearestGlucose(at date: Date, toleranceMinutes: Int = 5) -> GlucoseDatapoint? {
        let rounded = date.toRounded(on: 1, .minute)
        for offset in 0...max(0, toleranceMinutes) {
            if let hit = glucoseByMinute[rounded.addingTimeInterval(TimeInterval(-offset * 60))] {
                return hit
            }
            if offset > 0, let hit = glucoseByMinute[rounded.addingTimeInterval(TimeInterval(offset * 60))] {
                return hit
            }
        }
        return nil
    }

    /// Nearest IOB sample (sampled every 60 s, so a 1-minute probe is exact).
    func iobValue(at date: Date) -> Double? {
        guard !iob.isEmpty else { return nil }
        let rounded = date.toRounded(on: 1, .minute)
        return iob.min(by: {
            abs($0.date.timeIntervalSince(rounded)) < abs($1.date.timeIntervalSince(rounded))
        })?.total
    }

    /// Aggregate for the A/B readout — every number carries its `n`.
    func summary(over range: ClosedRange<Date>) -> LabRangeSummary {
        let inside = glucose.filter { range.contains($0.time) }
        let values = inside.map(\.value)
        let carbs = meals
            .filter { range.contains($0.time) }
            .compactMap(\.carbs)
            .reduce(0, +)
        let units = insulin
            .filter { range.contains($0.starts) && $0.type != .basal }
            .map(\.value)
            .reduce(0, +)
        let heartRates = heartRate.filter { range.contains($0.time) }

        let delta: Double? = {
            guard let first = values.first, let last = values.last else { return nil }
            return last - first
        }()

        return LabRangeSummary(
            first: values.first,
            last: values.last,
            min: values.min(),
            max: values.max(),
            delta: delta,
            readings: inside.count,
            carbsGrams: carbs,
            insulinUnits: units,
            heartRateFirst: heartRates.first?.bpm,
            heartRateLast: heartRates.last?.bpm
        )
    }
}

// MARK: - LabChartSeriesBuilder

enum LabChartSeriesBuilder {
    /// Pure; safe off the main actor with a snapshot.
    static func build(_ inputs: LabChartInputs, now: Date = Date()) -> LabChartSeries {
        let timestamps = inputs.sensorGlucose.map(\.timestamp) + inputs.bloodGlucose.map(\.timestamp)

        guard let first = timestamps.min(), let last = timestamps.max() else {
            return LabChartSeries.blank(at: now)
        }

        let domainStart = first
        // The live view runs 15 minutes past the newest reading so the trace has
        // somewhere to grow into; a picked day stops at its last reading
        // (ChartView.swift:725-755).
        let domainEnd = inputs.selectedDate == nil
            ? last.addingTimeInterval(15 * 60)
            : last

        let glucose = inputs.sensorGlucose
            .sorted { $0.timestamp < $1.timestamp }
            .map { value -> GlucoseDatapoint in
                if inputs.showSmoothed, value.timestamp < inputs.smoothThreshold {
                    return value.toSmoothDatapoint(
                        glucoseUnit: inputs.glucoseUnit,
                        alarmLow: inputs.alarmLow,
                        alarmHigh: inputs.alarmHigh
                    )
                }
                return value.toDatapoint(
                    glucoseUnit: inputs.glucoseUnit,
                    alarmLow: inputs.alarmLow,
                    alarmHigh: inputs.alarmHigh
                )
            }

        var glucoseByMinute: [Date: GlucoseDatapoint] = [:]
        for point in glucose {
            let key = point.time.toRounded(on: 1, .minute)
            if glucoseByMinute[key] == nil {
                glucoseByMinute[key] = point
            }
        }

        let bloodGlucose = inputs.bloodGlucose
            .sorted { $0.timestamp < $1.timestamp }
            .map {
                $0.toDatapoint(
                    glucoseUnit: inputs.glucoseUnit,
                    alarmLow: inputs.alarmLow,
                    alarmHigh: inputs.alarmHigh
                )
            }

        let insulin = inputs.insulin.map { $0.toDatapoint(minDate: domainStart, maxDate: domainEnd) }

        return LabChartSeries(
            domainStart: domainStart,
            domainEnd: domainEnd,
            glucose: glucose,
            glucoseSegments: segmentGlucoseSeries(glucose),
            glucoseByMinute: glucoseByMinute,
            bloodGlucose: bloodGlucose,
            insulin: insulin,
            iob: iobSamples(inputs, from: domainStart, to: domainEnd),
            meals: inputs.meals.map { $0.toDatapoint() },
            exercise: inputs.exercise.map { $0.toDatapoint() },
            heartRate: inputs.heartRate.sorted { $0.time < $1.time }
        )
    }

    /// 60 s sampling across the domain, inclusive of both ends — the cadence the
    /// shipping IOB area uses (ChartView.swift:895-916), which is what stops the
    /// area from showing visible steps when a bolus lands between two samples.
    private static func iobSamples(_ inputs: LabChartInputs, from start: Date, to end: Date) -> [IOBSample] {
        guard !inputs.iobDeliveries.isEmpty, start <= end else { return [] }

        let bolusModel = ExponentialInsulinModel.bolus(preset: inputs.bolusPreset)
        let basalModel = ExponentialInsulinModel.basal(diaMinutes: inputs.basalDIAMinutes)

        var samples: [IOBSample] = []
        var current = start
        while current <= end {
            let result = computeIOB(
                deliveries: inputs.iobDeliveries,
                bolusModel: bolusModel,
                basalModel: basalModel,
                at: current
            )
            samples.append(IOBSample(
                date: current,
                total: result.total,
                mealSnack: result.mealSnackIOB,
                corrBasal: result.correctionBasalIOB
            ))
            current = current.addingTimeInterval(60)
        }
        return samples
    }
}
