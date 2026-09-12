//
//  ChartHighlights.swift
//  DOSBTS
//
//  Chart Lab (DMNC-1500 / P5): the offline highlights engine. It turns the
//  window the user is looking at into a ranked list of id-carrying FACTS — each
//  one anchored on a real timestamp and carrying the sample it came from.
//
//  Pure: no store, no database, no network, no `Date()` except the injected
//  `now`. The same shape as `TightControlStreakDetector` — an App-level pure
//  detector reached from tests by `@testable import DOSBTSApp`.
//
//  Nothing here advises. Every string is a restatement of something the user's
//  own data already says: what happened, when, how much, and out of how many
//  readings. The later AI leg can only ever narrate these facts, which is the
//  whole point of shipping the deterministic half first.
//

import Foundation

// MARK: - ChartFact

/// One thing the lab can state about the visible window, on the record.
struct ChartFact: Identifiable, Equatable {
    enum Kind: Equatable {
        case hypoOnset
        case mealResponse
        case stackedBolus
        case exerciseDrop
        case tightControlRun
        /// P4 feeds this (band exits against the personal 30-day band).
        case bandExit
        /// P2 feeds this (regime overlap).
        case regimeOverlap
    }

    /// Stable across rebuilds — a card can be tapped, the series can rebuild
    /// underneath it, and the same card is still the same card.
    let id: String
    let kind: Kind
    /// Where the pin lands on the x axis, and where a tapped card scrolls to.
    let anchor: Date
    /// The far end of the episode, when it has one.
    let end: Date?
    /// Rendered by `LabCaption`, joined with the DOS separator. Items, not a
    /// String: a mg/dL number baked into a title would lie to a mmol/L user.
    let title: [LabFactItem]
    let lines: [[LabFactItem]]
    /// 3 hypo · 2 stacked bolus / large excursion · 1 informational.
    let severity: Int
}

// MARK: - ChartFeatureSheet

/// The one-line feature sheet under the chart: what this window IS, in counts.
struct ChartFeatureSheet: Equatable {
    let window: DateInterval
    let readings: Int
    let median: LabFigure
    let p95: LabFigure
    let hypoEpisodes: Int
    let meals: Int
    let cleanMeals: Int
    let notes: Int

    /// `24H · n=288 · MEDIAN 138 · P95 214 · 1 HYPO · 4 MEALS · 3 CLEAN`
    func items() -> [LabFactItem] {
        var items: [LabFactItem] = [
            .observation(label: windowLabel, value: nil, n: 1),
            .figure(LabFigure(
                kind: .sampleCount,
                value: Double(readings),
                unit: "",
                n: readings,
                citesSampleSize: false
            )),
            .figure(median),
            .figure(p95),
            .figure(count(hypoEpisodes, unit: "HYPO")),
            .figure(count(meals, unit: "MEALS")),
            .figure(count(cleanMeals, unit: "CLEAN"))
        ]
        if notes > 0 {
            items.append(.figure(count(notes, unit: "NOTES")))
        }
        return items
    }

    // MARK: Private

    private var windowLabel: String {
        "\(Int((window.duration / 3600).rounded()))H"
    }

    private func count(_ value: Int, unit: String) -> LabFigure {
        // `n` is the window's readings: the sample every one of these counts was
        // derived from. Counting kinds print at zero — `0 HYPO` is a fact.
        LabFigure(kind: .count, value: Double(value), unit: unit, n: readings, citesSampleSize: false)
    }
}

// MARK: - LabFactsSnapshot

/// What the chart computed, handed up to the tab that draws the cards, so the
/// pins, the sheet line and the cards can never be built from different numbers.
struct LabFactsSnapshot: Equatable {
    let facts: [ChartFact]
    let sheet: ChartFeatureSheet?

    static let empty = LabFactsSnapshot(facts: [], sheet: nil)
}

// MARK: - ChartHighlights

enum ChartHighlights {
    // MARK: Configuration

    /// More than five cards is a feed, not a finding.
    static let maxFacts = 5
    /// The post-meal window every meal number is derived over — the same two
    /// hours `MealImpact` uses, so the lab and the meal overlay agree.
    static let mealWindow: TimeInterval = 2 * 60 * 60
    /// Two boluses closer than this confound each other's attribution
    /// (`RatioEstimator.correctionStackLookbackMinutes`, reused rather than
    /// re-invented).
    static let stackingWindow = TimeInterval(RatioEstimator.correctionStackLookbackMinutes * 60)
    /// Carbs within this of each other count as "similar meals".
    static let similarCarbsGrams: Double = 15
    /// A drop this big (mg/dL) inside `exerciseDropWindow` of an exercise start
    /// is worth stating.
    static let exerciseDropThresholdMgDL = 30
    static let exerciseDropWindow: TimeInterval = 60 * 60
    /// How far around an onset heart rate is read.
    static let heartRateWindow: TimeInterval = 30 * 60
    /// How far back a journal note still counts as context for an onset.
    static let noteLookback: TimeInterval = 12 * 60 * 60
    /// An IOB sample this close to an instant IS that instant's IOB (the lab
    /// samples IOB once a minute).
    static let iobTolerance: TimeInterval = 5 * 60

    // MARK: Facts

    /// Ranked by severity, then recency, capped at `maxFacts`.
    static func facts(
        readings: [SensorGlucose],
        deliveries: [InsulinDelivery] = [],
        meals: [MealEntry] = [],
        exercise: [ExerciseEntry] = [],
        notes: [JournalNote] = [],
        iob: [IOBSample] = [],
        heartRate: [HeartRateSample] = [],
        now: Date = Date()
    ) -> [ChartFact] {
        let sorted = readings.sorted { $0.timestamp < $1.timestamp }

        var facts: [ChartFact] = []
        facts += hypoFacts(
            readings: sorted,
            deliveries: deliveries,
            exercise: exercise,
            notes: notes,
            iob: iob,
            heartRate: heartRate
        )
        facts += mealFacts(readings: sorted, deliveries: deliveries, meals: meals, exercise: exercise, now: now)
        facts += stackedBolusFacts(deliveries: deliveries)
        facts += exerciseDropFacts(readings: sorted, exercise: exercise)
        facts += tightControlFacts(readings: sorted)

        return Array(
            facts
                .sorted { lhs, rhs in
                    lhs.severity == rhs.severity ? lhs.anchor > rhs.anchor : lhs.severity > rhs.severity
                }
                .prefix(maxFacts)
        )
    }

    // MARK: Feature sheet

    static func sheet(
        readings: [SensorGlucose],
        meals: [MealEntry] = [],
        deliveries: [InsulinDelivery] = [],
        exercise: [ExerciseEntry] = [],
        notes: [JournalNote] = [],
        window: DateInterval
    ) -> ChartFeatureSheet {
        let inWindow = readings.filter { window.contains($0.timestamp) }
        let values = inWindow.map(\.glucoseValue).sorted()
        let mealsInWindow = meals.filter { window.contains($0.timestamp) }

        return ChartFeatureSheet(
            window: window,
            readings: inWindow.count,
            median: LabFigure(
                kind: .median,
                value: Double(ClinicReportBuilder.percentile(values, 0.5)),
                unit: "",
                n: inWindow.count,
                label: "MEDIAN",
                citesSampleSize: false
            ),
            p95: LabFigure(
                kind: .percentile,
                value: Double(ClinicReportBuilder.percentile(values, 0.95)),
                unit: "",
                n: inWindow.count,
                label: "P95",
                citesSampleSize: false
            ),
            hypoEpisodes: ClinicReportBuilder.hypoEpisodeIntervals(from: inWindow).count,
            meals: mealsInWindow.count,
            cleanMeals: mealsInWindow.filter {
                detectMealConfounders(
                    meal: $0,
                    insulinDeliveryValues: deliveries,
                    exerciseEntryValues: exercise,
                    mealEntryValues: meals
                ).isClean
            }.count,
            notes: notes.filter { window.contains($0.timestamp) }.count
        )
    }

    // MARK: - Hypo onset (the Black Box)

    private static func hypoFacts(
        readings: [SensorGlucose],
        deliveries: [InsulinDelivery],
        exercise: [ExerciseEntry],
        notes: [JournalNote],
        iob: [IOBSample],
        heartRate: [HeartRateSample]
    ) -> [ChartFact] {
        ClinicReportBuilder.hypoEpisodeIntervals(from: readings).map { interval in
            let onset = interval.start
            let episode = readings.filter { interval.contains($0.timestamp) }
            let n = episode.count
            let minutes = Int(interval.duration / 60)

            let title: [LabFactItem] = [
                .observation(label: "BLACK BOX", value: nil, n: 1),
                .observation(label: "HYPO", value: onset.toLocalTime(), n: 1),
                .figure(LabFigure(kind: .duration, value: Double(minutes), unit: "MIN", n: n, citesSampleSize: false))
            ]

            return ChartFact(
                id: "hypo-\(isoString(onset))",
                kind: .hypoOnset,
                anchor: onset,
                end: interval.end,
                title: title,
                lines: [
                    blackBoxState(onset: onset, episode: episode, iob: iob),
                    blackBoxHistory(onset: onset, deliveries: deliveries, exercise: exercise),
                    blackBoxContext(onset: onset, notes: notes, heartRate: heartRate)
                ],
                severity: 3
            )
        }
    }

    /// `T-0 62 · IOB 1.8U · COB —`
    private static func blackBoxState(onset: Date, episode: [SensorGlucose], iob: [IOBSample]) -> [LabFactItem] {
        let onsetValue = episode.first { $0.timestamp == onset } ?? episode.first
        let sample = iob
            .filter { abs($0.date.timeIntervalSince(onset)) <= iobTolerance }
            .min { abs($0.date.timeIntervalSince(onset)) < abs($1.date.timeIntervalSince(onset)) }

        return [
            .figure(LabFigure(
                kind: .glucose,
                value: Double(onsetValue?.glucoseValue ?? 0),
                unit: "",
                n: onsetValue == nil ? 0 : episode.count,
                label: "T-0",
                citesSampleSize: false
            )),
            .figure(LabFigure(
                kind: .iob,
                value: sample?.total ?? 0,
                unit: "U",
                n: sample == nil ? 0 : 1,
                label: "IOB",
                citesSampleSize: false
            )),
            // COB is a placeholder until W2 ships carb absorption: n=0, so it
            // renders `COB —` and never an invented zero.
            .figure(LabFigure(kind: .cob, value: 0, unit: "g", n: 0, label: "COB", citesSampleSize: false))
        ]
    }

    /// `LAST BOLUS T-4h10 7.0U · EXERCISE T-9h 30m RUN`
    private static func blackBoxHistory(
        onset: Date,
        deliveries: [InsulinDelivery],
        exercise: [ExerciseEntry]
    ) -> [LabFactItem] {
        let lastBolus = deliveries
            .filter { $0.type != .basal && $0.starts <= onset }
            .max { $0.starts < $1.starts }

        let lastExercise = exercise
            .filter { $0.startTime <= onset }
            .max { $0.startTime < $1.startTime }

        let exerciseValue = lastExercise.map {
            "\(offsetLabel(from: $0.startTime, to: onset)) \(Int($0.durationMinutes))m \($0.activityType.uppercased())"
        }

        return [
            .figure(LabFigure(
                kind: .insulin,
                value: lastBolus?.units ?? 0,
                unit: "U",
                n: lastBolus == nil ? 0 : 1,
                label: lastBolus.map { "LAST BOLUS \(offsetLabel(from: $0.starts, to: onset))" } ?? "LAST BOLUS",
                citesSampleSize: false
            )),
            .observation(label: "EXERCISE", value: exerciseValue, n: lastExercise == nil ? 0 : 1)
        ]
    }

    /// `HR 71→96 · TAG SICK`
    private static func blackBoxContext(
        onset: Date,
        notes: [JournalNote],
        heartRate: [HeartRateSample]
    ) -> [LabFactItem] {
        let around = heartRate
            .filter { abs($0.time.timeIntervalSince(onset)) <= heartRateWindow }
            .sorted { $0.time < $1.time }

        let heartRateValue: String? = {
            guard let first = around.first, let last = around.last else { return nil }
            let start = Int(first.bpm.rounded())
            let end = Int(last.bpm.rounded())
            return start == end ? "\(start)" : "\(start)→\(end)"
        }()

        let tagged = notes
            .filter { $0.tag != nil && $0.timestamp <= onset && onset.timeIntervalSince($0.timestamp) <= noteLookback }
            .max { $0.timestamp < $1.timestamp }

        return [
            .observation(label: "HR", value: heartRateValue, n: around.count),
            .observation(
                label: "TAG",
                value: tagged?.tag?.rawValue.uppercased(),
                n: tagged == nil ? 0 : 1
            )
        ]
    }

    // MARK: - Meal response

    private static func mealFacts(
        readings: [SensorGlucose],
        deliveries: [InsulinDelivery],
        meals: [MealEntry],
        exercise: [ExerciseEntry],
        now: Date
    ) -> [ChartFact] {
        meals.compactMap { meal -> ChartFact? in
            // A window that has not closed yet has no peak to state.
            guard meal.timestamp.addingTimeInterval(mealWindow) <= now else { return nil }

            let overlay = computeMealOverlayDelta(
                meal: meal,
                isInProgress: false,
                sensorGlucoseValues: readings
            )
            guard let delta = overlay.delta else { return nil }

            let windowEnd = meal.timestamp.addingTimeInterval(mealWindow)
            let inWindow = readings.filter { $0.timestamp >= meal.timestamp && $0.timestamp <= windowEnd }
            guard let peak = inWindow.max(by: { $0.glucoseValue < $1.glucoseValue }) else { return nil }

            let confounders = detectMealConfounders(
                meal: meal,
                insulinDeliveryValues: deliveries,
                exerciseEntryValues: exercise,
                mealEntryValues: meals
            )
            let similar = meals.filter {
                abs(($0.carbsGrams ?? 0) - (meal.carbsGrams ?? 0)) <= similarCarbsGrams
            }.count

            var title: [LabFactItem] = []
            if let carbs = meal.carbsGrams {
                title.append(.figure(LabFigure(
                    kind: .carbs,
                    value: carbs,
                    unit: "g",
                    n: 1,
                    label: shortName(meal),
                    citesSampleSize: false
                )))
            } else {
                title.append(.observation(label: shortName(meal), value: nil, n: 1))
            }
            title.append(.figure(LabFigure(
                kind: .delta,
                value: Double(delta),
                unit: "",
                n: inWindow.count,
                citesSampleSize: false
            )))
            title.append(.figure(LabFigure(
                kind: .peakMinutes,
                value: (peak.timestamp.timeIntervalSince(meal.timestamp) / 60).rounded(),
                unit: "MIN",
                n: inWindow.count,
                label: "PEAK",
                citesSampleSize: false
            )))

            return ChartFact(
                id: "meal-\(meal.id.uuidString)",
                kind: .mealResponse,
                anchor: meal.timestamp,
                end: windowEnd,
                title: title,
                lines: [[
                    .figure(LabFigure(
                        kind: .count,
                        value: Double(similar),
                        unit: "SIMILAR MEALS",
                        n: similar,
                        label: "1 OF",
                        citesSampleSize: false
                    )),
                    .observation(label: confounders.isClean ? "CLEAN" : "CONFOUNDED", value: nil, n: 1),
                    .figure(LabFigure(
                        kind: .sampleCount,
                        value: Double(inWindow.count),
                        unit: "RDG",
                        n: inWindow.count,
                        citesSampleSize: false
                    ))
                ]],
                severity: abs(delta) >= 60 ? 2 : 1
            )
        }
    }

    private static func shortName(_ meal: MealEntry) -> String {
        let trimmed = meal.mealDescription.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? "MEAL" : String(trimmed.prefix(14))
    }

    // MARK: - Stacked bolus

    private static func stackedBolusFacts(deliveries: [InsulinDelivery]) -> [ChartFact] {
        let boluses = deliveries
            .filter { $0.type != .basal }
            .sorted { $0.starts < $1.starts }
        guard boluses.count > 1 else { return [] }

        return (1 ..< boluses.count).compactMap { index -> ChartFact? in
            let previous = boluses[index - 1]
            let dose = boluses[index]
            let gap = dose.starts.timeIntervalSince(previous.starts)
            guard gap <= stackingWindow else { return nil }

            return ChartFact(
                id: "stack-\(dose.id.uuidString)",
                kind: .stackedBolus,
                anchor: dose.starts,
                end: nil,
                title: [
                    .observation(label: "STACKED BOLUS", value: nil, n: 2),
                    .figure(LabFigure(
                        kind: .duration,
                        value: (gap / 60).rounded(),
                        unit: "MIN APART",
                        n: 2,
                        citesSampleSize: false
                    ))
                ],
                lines: [[
                    .figure(LabFigure(kind: .insulin, value: previous.units, unit: "U", n: 1, label: "FIRST", citesSampleSize: false)),
                    .figure(LabFigure(kind: .insulin, value: dose.units, unit: "U", n: 1, label: "THEN", citesSampleSize: false))
                ]],
                severity: 2
            )
        }
    }

    // MARK: - Exercise-adjacent drop

    private static func exerciseDropFacts(readings: [SensorGlucose], exercise: [ExerciseEntry]) -> [ChartFact] {
        exercise.compactMap { entry -> ChartFact? in
            let windowEnd = entry.startTime.addingTimeInterval(exerciseDropWindow)
            let inWindow = readings.filter { $0.timestamp >= entry.startTime && $0.timestamp <= windowEnd }
            guard let start = inWindow.first,
                  let nadir = inWindow.min(by: { $0.glucoseValue < $1.glucoseValue })
            else { return nil }

            let drop = start.glucoseValue - nadir.glucoseValue
            guard drop >= exerciseDropThresholdMgDL else { return nil }

            return ChartFact(
                id: "exercise-\(entry.id.uuidString)",
                kind: .exerciseDrop,
                anchor: entry.startTime,
                end: entry.endTime,
                title: [
                    .observation(label: "EXERCISE", value: entry.activityType.uppercased(), n: 1),
                    .figure(LabFigure(
                        kind: .duration,
                        value: entry.durationMinutes.rounded(),
                        unit: "MIN",
                        n: 1,
                        citesSampleSize: false
                    ))
                ],
                lines: [[
                    .figure(LabFigure(kind: .glucose, value: Double(start.glucoseValue), unit: "", n: inWindow.count, label: "START", citesSampleSize: false)),
                    .figure(LabFigure(kind: .glucose, value: Double(nadir.glucoseValue), unit: "", n: inWindow.count, label: "LOW", citesSampleSize: false)),
                    .figure(LabFigure(kind: .delta, value: Double(-drop), unit: "", n: inWindow.count, citesSampleSize: false)),
                    .figure(LabFigure(kind: .sampleCount, value: Double(inWindow.count), unit: "RDG", n: inWindow.count, citesSampleSize: false))
                ]],
                severity: 1
            )
        }
    }

    // MARK: - Tight control

    private static func tightControlFacts(readings: [SensorGlucose]) -> [ChartFact] {
        let config = TightControlConfig.default
        var facts: [ChartFact] = []
        var runStart: SensorGlucose?
        var previous: SensorGlucose?
        var count = 0

        func close(at last: SensorGlucose?) {
            defer {
                runStart = nil
                count = 0
            }
            guard let runStart, let last, count > 1 else { return }
            let duration = last.timestamp.timeIntervalSince(runStart.timestamp)
            guard duration >= config.requiredDuration else { return }

            facts.append(ChartFact(
                id: "tight-\(isoString(runStart.timestamp))",
                kind: .tightControlRun,
                anchor: runStart.timestamp,
                end: last.timestamp,
                title: [
                    .observation(label: "TIGHT CONTROL", value: nil, n: 1),
                    .figure(LabFigure(
                        kind: .duration,
                        value: (duration / 60).rounded(),
                        unit: "MIN",
                        n: count,
                        citesSampleSize: false
                    ))
                ],
                lines: [[
                    .figure(LabFigure(
                        kind: .band,
                        value: Double(config.bandLow + config.bandHigh) / 2,
                        unit: "",
                        n: count,
                        spread: Double(config.bandLow) ... Double(config.bandHigh),
                        label: "BAND",
                        citesSampleSize: false
                    )),
                    .figure(LabFigure(
                        kind: .sampleCount,
                        value: Double(count),
                        unit: "RDG",
                        n: count,
                        citesSampleSize: false
                    ))
                ]],
                severity: 1
            ))
        }

        for reading in readings {
            let inBand = reading.glucoseValue >= config.bandLow && reading.glucoseValue <= config.bandHigh
            let gapBroken = previous.map {
                reading.timestamp.timeIntervalSince($0.timestamp) > config.gapThreshold
            } ?? false

            if !inBand || gapBroken {
                close(at: previous)
            }

            if inBand {
                if runStart == nil { runStart = reading }
                count += 1
            }
            previous = inBand ? reading : nil
        }
        close(at: previous)

        return facts
    }

    // MARK: - Shared helpers

    /// `T-4h10` / `T-9h` / `T-25m` — how long before the anchor something happened.
    static func offsetLabel(from earlier: Date, to reference: Date) -> String {
        let minutes = max(0, Int(reference.timeIntervalSince(earlier) / 60))
        let hours = minutes / 60
        let remainder = minutes % 60

        if hours == 0 { return "T-\(remainder)m" }
        return remainder == 0 ? "T-\(hours)h" : "T-\(hours)h\(String(format: "%02d", remainder))"
    }

    /// Fixed, locale-independent — ids are identity, never display.
    private static let idFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static func isoString(_ date: Date) -> String {
        idFormatter.string(from: date)
    }
}
