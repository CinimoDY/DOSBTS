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

// MARK: - LabInsulinDose

/// An insulin delivery at its TRUE time.
///
/// `InsulinDatapoint` deliberately clamps `starts`/`ends` into the chart domain
/// so an out-of-domain basal bar still draws inside the plot — which means it
/// lies about when a dose happened. Summaries and detents read this instead, or
/// a sensor gap piles every earlier bolus onto the domain's first minute.
struct LabInsulinDose: Equatable {
    let id: String
    let starts: Date
    let units: Double
    let type: InsulinType
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
    /// Journal notes are context for a fact, never a series: the Black Box card
    /// states the tag that was standing when a hypo started.
    let journalNotes: [JournalNote]
    let sleep: [SleepSample]
    /// The night window forces heart rate on; the day path follows the setting.
    let showHeartRate: Bool
    /// When set, the chart's x domain is THIS, not the span of the data — the
    /// only way a window can show a period with no readings in part of it
    /// (a sensor gap at 03:00 must still leave 03:00 on the axis).
    let domainOverride: DateInterval?
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
        self.journalNotes = state.journalNoteValues
        self.sleep = []
        self.showHeartRate = state.showHeartRateOverlay
        self.domainOverride = nil
        self.glucoseUnit = state.glucoseUnit
        self.alarmLow = state.alarmLow
        self.alarmHigh = state.alarmHigh
        self.bolusPreset = state.bolusInsulinPreset
        self.basalDIAMinutes = state.basalDIAMinutes
        let showSmoothed = DirectConfig.showSmoothedGlucose && state.showSmoothedGlucose
        self.showSmoothed = showSmoothed
        // `state.smoothThreshold` is `Date() - n`, i.e. a different value on every
        // read. Floored to the minute it can still move an equality check, but at
        // most once a minute instead of on every render — and when smoothing is
        // off it is not read at all, so a fixed sentinel keeps those users off the
        // once-a-minute rebuild entirely.
        self.smoothThreshold = showSmoothed
            ? state.smoothThreshold.toRounded(on: 1, .minute)
            : Date(timeIntervalSince1970: 0)
        self.selectedDate = state.selectedDate
        self.overlays = overlays
    }

    /// The whole-system window path (DMNC-1506): the series comes from ONE
    /// `LabWindowSnapshot` and the domain is the window itself, not the span of
    /// whatever rows came back. Formatting still comes from the store — a lab
    /// tab shows the user's units and the user's thresholds like every other.
    init(window: LabWindowSnapshot, state: DirectState, overlays: Set<ChartLabOverlay>) {
        self.sensorGlucose = window.readings
        self.bloodGlucose = window.bloodGlucose
        self.meals = window.meals
        self.insulin = window.deliveries
        self.iobDeliveries = window.iobDeliveries
        self.exercise = window.exercise
        self.journalNotes = window.notes
        self.heartRate = window.heartRate
        self.sleep = window.sleep
        // The night is the one window where heart rate is part of the story, so
        // it is not behind the day chart's overlay toggle.
        self.showHeartRate = true
        self.domainOverride = window.interval
        self.glucoseUnit = state.glucoseUnit
        self.alarmLow = state.alarmLow
        self.alarmHigh = state.alarmHigh
        self.bolusPreset = state.bolusInsulinPreset
        self.basalDIAMinutes = state.basalDIAMinutes
        let showSmoothed = DirectConfig.showSmoothedGlucose && state.showSmoothedGlucose
        self.showSmoothed = showSmoothed
        self.smoothThreshold = showSmoothed
            ? state.smoothThreshold.toRounded(on: 1, .minute)
            : Date(timeIntervalSince1970: 0)
        // A fixed window never scrolls to "now", so the day path's selected-date
        // domain rule does not apply — the override is the whole story.
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
        journalNotes: [JournalNote] = [],
        sleep: [SleepSample] = [],
        showHeartRate: Bool = true,
        domainOverride: DateInterval? = nil,
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
        self.journalNotes = journalNotes
        self.sleep = sleep
        self.showHeartRate = showHeartRate
        self.domainOverride = domainOverride
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

// MARK: - LabReadoutSegment

/// One run of the A→B readout line, with the role that decides its colour.
struct LabReadoutSegment: Equatable {
    enum Emphasis: Equatable {
        case value
        case delta
        case sampleSize
    }

    let text: String
    let emphasis: Emphasis
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

    /// The A→B line, in reading order, with `n` always last.
    ///
    /// Pure and unit-agnostic (the caller supplies its own formatters) so the
    /// line's CONTENT is pinned by tests, and so the view can render it as ONE
    /// `Text`: an `HStack` of separate `Text`s truncates its children
    /// individually under pressure (`G 6,2… · MA…`) instead of scaling the line
    /// down as a whole.
    func readoutSegments(format: (Double) -> String, units: (Double) -> String) -> [LabReadoutSegment] {
        var segments: [LabReadoutSegment] = []

        if let first, let last {
            segments.append(LabReadoutSegment(text: "G \(format(first))→\(format(last))", emphasis: .value))
            if let delta {
                let sign = delta > 0 ? "+" : ""
                segments.append(LabReadoutSegment(text: "(\(sign)\(format(delta)))", emphasis: .delta))
            }
        }
        if let min, let max {
            segments.append(LabReadoutSegment(text: "MIN \(format(min)) · MAX \(format(max))", emphasis: .value))
        }
        if insulinUnits > 0 {
            segments.append(LabReadoutSegment(text: "IN \(units(insulinUnits))", emphasis: .value))
        }
        if carbsGrams > 0 {
            segments.append(LabReadoutSegment(text: "CARBS \(Int(carbsGrams))g", emphasis: .value))
        }
        // Every derived number ships with its sample size — last, always.
        segments.append(LabReadoutSegment(text: "n=\(readings)", emphasis: .sampleSize))

        return segments
    }

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
    /// Clamped to the domain — for DRAWING only.
    var insulin: [InsulinDatapoint]
    /// Unclamped — for every number and every detent.
    var insulinDoses: [LabInsulinDose]
    var iob: [IOBSample]
    var meals: [MealDatapoint]
    var exercise: [ExerciseDatapoint]
    var heartRate: [HeartRateSample]
    /// Drawn by the chart's own heart-rate block; the night forces it on.
    var showsHeartRate: Bool
    /// Filled only when `.nightContext` is one of the overlays.
    var nightContext: LabNightContext
    /// Post-meal response ribbons carried across the window's left edge. P2 owns
    /// `.mealResponseRibbons`; until it merges, the night arm draws these.
    var mealRibbons: [LabMealRibbon]

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
            insulinDoses: [],
            iob: [],
            meals: [],
            exercise: [],
            heartRate: [],
            showsHeartRate: false,
            nightContext: .empty,
            mealRibbons: []
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

    /// What the cursor is sitting on, or nil for open ground. Event ids beat
    /// alarm bounds: crossing a meal you logged is more informative than
    /// crossing a threshold you set.
    func detentKey(at date: Date, alarmLow: Double, alarmHigh: Double, window: TimeInterval) -> String? {
        if let meal = meals.first(where: { abs($0.time.timeIntervalSince(date)) <= window }) {
            return "meal-\(meal.id)"
        }
        if let dose = insulinDoses.first(where: { abs($0.starts.timeIntervalSince(date)) <= window }) {
            return "insulin-\(dose.id)"
        }
        if let exercise = exercise.first(where: { abs($0.startTime.timeIntervalSince(date)) <= window }) {
            return "exercise-\(exercise.id)"
        }
        if let reading = nearestGlucose(at: date) {
            if reading.value <= alarmLow { return LabDetent.lowKey }
            if reading.value >= alarmHigh { return LabDetent.highKey }
        }
        return nil
    }

    /// Aggregate for the A/B readout — every number carries its `n`.
    func summary(over range: ClosedRange<Date>) -> LabRangeSummary {
        let inside = glucose.filter { range.contains($0.time) }
        let values = inside.map(\.value)
        let carbs = meals
            .filter { range.contains($0.time) }
            .compactMap(\.carbs)
            .reduce(0, +)
        let units = insulinDoses
            .filter { range.contains($0.starts) && $0.type != .basal }
            .map(\.units)
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

        let domainStart: Date
        let domainEnd: Date

        if let window = inputs.domainOverride {
            // The window IS the domain. A night with a sensor gap from 02:00 to
            // 04:00 still shows those hours; deriving the domain from the data
            // would quietly shrink the night to the part that has readings.
            domainStart = window.start
            domainEnd = window.end
        } else {
            guard let first = timestamps.min(), let last = timestamps.max() else {
                return LabChartSeries.blank(at: now)
            }

            domainStart = first
            // The live view runs 15 minutes past the newest reading so the trace
            // has somewhere to grow into; a picked day stops at its last reading
            // (ChartView.swift:725-755).
            domainEnd = inputs.selectedDate == nil
                ? last.addingTimeInterval(15 * 60)
                : last
        }

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
        let insulinDoses = inputs.insulin.map {
            LabInsulinDose(id: $0.id.uuidString, starts: $0.starts, units: $0.units, type: $0.type)
        }

        return LabChartSeries(
            domainStart: domainStart,
            domainEnd: domainEnd,
            glucose: glucose,
            glucoseSegments: segmentGlucoseSeries(glucose),
            glucoseByMinute: glucoseByMinute,
            bloodGlucose: bloodGlucose,
            insulin: insulin,
            insulinDoses: insulinDoses,
            iob: iobSamples(inputs, from: domainStart, to: domainEnd),
            meals: inputs.meals.map { $0.toDatapoint() },
            exercise: inputs.exercise.map { $0.toDatapoint() },
            heartRate: inputs.heartRate.sorted { $0.time < $1.time },
            showsHeartRate: inputs.showHeartRate,
            nightContext: nightContext(inputs, domain: DateInterval(start: domainStart, end: max(domainStart, domainEnd))),
            mealRibbons: mealRibbons(inputs, domainStart: domainStart, domainEnd: domainEnd)
        )
    }

    /// Only the night tab pays for this — every other tab's `.nightContext` is
    /// `.empty` and the arm draws nothing.
    private static func nightContext(_ inputs: LabChartInputs, domain: DateInterval) -> LabNightContext {
        guard inputs.overlays.contains(.nightContext) else { return .empty }

        return LabNightContext.make(
            sleep: inputs.sleep,
            readings: inputs.sensorGlucose,
            interval: domain,
            glucoseUnit: inputs.glucoseUnit,
            alarmLow: inputs.alarmLow
        )
    }

    /// A meal's two-hour response, clamped into the domain so a dinner logged
    /// before the window's left edge still draws its ribbon from that edge —
    /// while `mealTime` keeps the truth about when it actually happened.
    ///
    /// The delta comes from the SHIPPING `computeMealOverlayDelta`, so the lab
    /// and the meal-impact overlay can never disagree about a number.
    private static func mealRibbons(_ inputs: LabChartInputs, domainStart: Date, domainEnd: Date) -> [LabMealRibbon] {
        guard inputs.overlays.contains(.nightContext) else { return [] }

        let responseWindow: TimeInterval = 2 * 60 * 60

        return inputs.meals.compactMap { meal -> LabMealRibbon? in
            let end = meal.timestamp.addingTimeInterval(responseWindow)
            // Entirely outside the drawn domain — nothing to say.
            guard end > domainStart, meal.timestamp < domainEnd else { return nil }

            let delta = computeMealOverlayDelta(
                meal: meal,
                isInProgress: false,
                sensorGlucoseValues: inputs.sensorGlucose
            )
            let readings = inputs.sensorGlucose.filter {
                $0.timestamp >= meal.timestamp && $0.timestamp <= end
            }.count

            // No delta and no readings behind it is not a fact the lab may draw.
            guard let value = delta.delta, readings > 0 else { return nil }

            // `computeMealOverlayDelta` works in mg/dL (the storage unit); the
            // LABEL is the user's unit, so an mmol/L user reads `+2,1`, not `+38`.
            // Sign comes off the raw value so a rounded-to-zero delta still
            // shows the direction it went.
            let sign = value > 0 ? "+" : ""
            let magnitude = inputs.glucoseUnit == .mmolL
                ? (GlucoseFormatters.mmolLFormatter.string(from: Double(value).toMmolL() as NSNumber) ?? "\(value)")
                : "\(value)"
            return LabMealRibbon(
                id: meal.id.uuidString,
                start: max(domainStart, meal.timestamp),
                end: min(domainEnd, end),
                mealTime: meal.timestamp,
                label: "\(sign)\(magnitude) · \(readings) RDG"
            )
        }
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
