//
//  MealSweep.swift
//  DOSBTS
//
//  Pure model + statistics for `LAB: SWEEP` (DMNC-1503, Chart Lab P3). A sweep is
//  one meal's glucose response re-plotted against minutes-since-the-meal and
//  change-from-the-pre-meal-baseline, so every meal in the period can be laid over
//  every other one at t=0. No UI, no Redux, no I/O — the same "pure logic,
//  exhaustively unit-tested" shape as `RatioEstimator` and `ClinicReportBuilder`.
//
//  WHY THE BASELINE/PEAK RULES ARE RESTATED HERE RATHER THAN CALLED
//  ----------------------------------------------------------------
//  `App/Views/Overview/MealOverlayLogic.swift` owns the shipping versions
//  (`computeMealOverlayDelta` :31-67, `detectMealConfounders` :78-103). This file
//  lives in `Library/`, which the **widget target also compiles**, while
//  `MealOverlayLogic` lives under `App/` and imports SwiftUI — so calling it from
//  here would break `DOSBTSWidget`. The rules below are therefore restated, and
//  `ChartLabSweepTests`' "Sweep parity with MealOverlayLogic" suite runs both over
//  the same fixtures and fails the moment they disagree.
//
//  The rules, verbatim from the shipping helpers:
//   • baseline  = the LAST reading in [t−15 min, t); if there is none, the first
//                 reading in the response window stands in as the reference and the
//                 sweep is marked `.noBaseline` (it can still be drawn, never binned).
//   • peak      = the maximum reading in [t, windowEnd], windowEnd = now for an
//                 in-progress meal, else t+2h.
//   • delta     = peak − reference.
//   • confounded = a correction bolus in [t, t+2h], OR exercise overlapping it, OR
//                 another meal logged inside it.
//   • n < 4 readings in the window is `isLowConfidence` upstream; here it is
//                 `.insufficientData` and keeps the sweep out of the median/wash.
//
//  Nothing in this file prescribes a dose. It describes what happened.
//

import Foundation

// MARK: - CarbBucket

/// The meal-size chips on the sweep tab: `ALL · ≤15 · 16–45 · 46–80 · >80`.
/// Edges are inclusive-upper (15 → `.upTo15`, 16 → `.from16to45`, …) so a meal
/// never falls between two buckets.
enum CarbBucket: String, CaseIterable, Equatable {
    case upTo15
    case from16to45
    case from46to80
    case over80
    case unknown

    /// Chip label. `.unknown` has no chip — a meal logged without carbs cannot be
    /// compared by size, and saying so is more honest than bucketing it as small.
    var label: String {
        switch self {
        case .upTo15: return "≤15"
        case .from16to45: return "16–45"
        case .from46to80: return "46–80"
        case .over80: return ">80"
        case .unknown: return "?"
        }
    }

    /// The four chips the UI offers, in artboard order. `.unknown` is deliberately
    /// not selectable.
    static var selectable: [CarbBucket] { [.upTo15, .from16to45, .from46to80, .over80] }

    static func bucket(forCarbs carbs: Double?) -> CarbBucket {
        guard let carbs else { return .unknown }
        if carbs <= 15 { return .upTo15 }
        if carbs <= 45 { return .from16to45 }
        if carbs <= 80 { return .from46to80 }
        return .over80
    }
}

// MARK: - SweepPoint

/// One sample on a sweep: `minute` is the offset from the meal (−30…+240, on a
/// 5-minute grid), `delta` the change from the sweep's reference glucose, in mg/dL.
/// The view converts for display; the model stays in the stored unit.
struct SweepPoint: Equatable {
    let minute: Int
    let delta: Int
}

// MARK: - MealSweep

/// One meal's response, event-locked at t=0.
struct MealSweep: Identifiable, Equatable {
    /// The `MealEntry.id` this sweep was built from.
    let id: UUID
    let mealTime: Date
    let mealDescription: String
    let carbs: Double?
    /// Whole days between the meal's day and today — drives the age fade.
    let ageDays: Int
    /// Minutes past local midnight, resolved once at build time with the injected
    /// calendar so every downstream consumer (the twin finder) stays pure.
    let minutesOfDay: Int
    /// The pre-meal reference reading, when there was one in [t−15 min, t).
    let baseline: Int?
    let points: [SweepPoint]
    /// Clean = no confounder, a real baseline, and enough readings to mean anything.
    /// Only clean sweeps feed the median and the p25–p75 wash.
    let isClean: Bool
    /// Why this sweep is not clean — the teaching tag, `nil` when it is.
    let exclusion: MealExclusionReason?
    /// The 2 h response window has not closed yet.
    let isInProgress: Bool
    /// Peak − reference over the response window, mg/dL.
    let delta: Int?
    /// Minutes from the meal to the peak reading.
    let peakMinutes: Int?
    /// Readings inside the response window — every caption that quotes this sweep
    /// carries it.
    let n: Int

    var carbBucket: CarbBucket { CarbBucket.bucket(forCarbs: carbs) }
}

// MARK: - SweepBin

/// The clean sweeps' spread at one 5-minute offset. `n` is how many sweeps had a
/// point there — it varies across the window (a CGM gap thins a bin) and is why
/// the band is never quoted without it.
struct SweepBin: Equatable {
    let minute: Int
    let p25: Int
    let p50: Int
    let p75: Int
    let n: Int
}

// MARK: - LabSweepEvidence

/// The transient payload `LAB: SWEEP` renders. Carries the window it answers so
/// the view can tell "still loading the 90-day set" from "the 7-day set is what
/// you are looking at".
struct LabSweepEvidence: Equatable {
    let days: Int
    let sweeps: [MealSweep]
    let loadedAt: Date
}

// MARK: - SweepStatistics

enum SweepStatistics {

    // MARK: Thresholds (test-pinned)

    /// The trace starts 30 minutes before the meal, so the pre-meal flat is visible.
    static let windowStartMinutes = -30
    /// …and runs four hours past it, as the artboard's axis does.
    static let windowEndMinutes = 240
    static let stepMinutes = 5
    /// A grid point takes the nearest reading within this much of its target; past
    /// it the point is dropped, so a real CGM dropout shows as a gap in the sweep
    /// rather than a straight line across it.
    static let nearestToleranceSeconds: TimeInterval = 5 * 60
    /// The response window the delta, the peak and `n` are measured over.
    static let responseWindowMinutes = 120
    /// The pre-meal baseline search window.
    static let baselineWindowMinutes = 15
    /// Fewer readings than this in the response window and the sweep cannot carry a
    /// number — the same gate `computeMealOverlayDelta` calls `isLowConfidence`.
    static let minReadingsForClean = 4
    /// Below this many clean sweeps there is no median and no wash to draw.
    static let minSweepsForBand = 3
    /// Drawn sweeps are capped; the newest survive.
    static let maxDrawnSweeps = 120

    // MARK: Build

    /// Turn the period's raw rows into sweeps, newest first.
    ///
    /// `now` is injected (never `Date()`) so the result is a pure function of its
    /// inputs and the in-progress cut is testable.
    static func build(
        meals: [MealEntry],
        readings: [SensorGlucose],
        deliveries: [InsulinDelivery],
        exercise: [ExerciseEntry],
        now: Date,
        calendar: Calendar = .current
    ) -> [MealSweep] {
        guard !meals.isEmpty else { return [] }

        let sortedReadings = readings.sorted { $0.timestamp < $1.timestamp }
        let responseSeconds = TimeInterval(responseWindowMinutes * 60)
        let baselineSeconds = TimeInterval(baselineWindowMinutes * 60)
        let today = calendar.startOfDay(for: now)

        return meals
            .sorted { $0.timestamp > $1.timestamp }
            .map { meal in
                let mealTime = meal.timestamp
                let confounderEnd = mealTime.addingTimeInterval(responseSeconds)
                let isInProgress = now < confounderEnd
                // The delta window is capped at `now` for a meal still unfolding —
                // `computeMealOverlayDelta` does the same with `Date()`.
                let windowEnd = isInProgress ? now : confounderEnd

                let baseline = sortedReadings.last {
                    $0.timestamp >= mealTime.addingTimeInterval(-baselineSeconds) && $0.timestamp < mealTime
                }
                let windowReadings = sortedReadings.filter {
                    $0.timestamp >= mealTime && $0.timestamp <= windowEnd
                }
                let reference = baseline?.glucoseValue ?? windowReadings.first?.glucoseValue

                let peak = windowReadings.max { $0.glucoseValue < $1.glucoseValue }
                let delta: Int? = {
                    guard let reference, let peak else { return nil }
                    return peak.glucoseValue - reference
                }()
                let peakMinutes = peak.map { Int($0.timestamp.timeIntervalSince(mealTime) / 60) }

                let points = reference.map {
                    samplePoints(
                        mealTime: mealTime,
                        reference: $0,
                        readings: sortedReadings,
                        limit: isInProgress ? now : nil
                    )
                } ?? []

                let confounded = isConfounded(
                    meal: meal,
                    windowEnd: confounderEnd,
                    deliveries: deliveries,
                    exercise: exercise,
                    meals: meals
                )

                let exclusion: MealExclusionReason?
                if confounded {
                    exclusion = .confounded
                } else if baseline == nil {
                    exclusion = .noBaseline
                } else if windowReadings.count < minReadingsForClean {
                    exclusion = .insufficientData
                } else {
                    exclusion = nil
                }

                let mealDay = calendar.startOfDay(for: mealTime)
                let ageDays = calendar.dateComponents([.day], from: mealDay, to: today).day ?? 0
                let components = calendar.dateComponents([.hour, .minute], from: mealTime)

                return MealSweep(
                    id: meal.id,
                    mealTime: mealTime,
                    mealDescription: meal.mealDescription,
                    carbs: meal.carbsGrams,
                    ageDays: max(0, ageDays),
                    minutesOfDay: (components.hour ?? 0) * 60 + (components.minute ?? 0),
                    baseline: baseline?.glucoseValue,
                    points: points,
                    isClean: exclusion == nil,
                    exclusion: exclusion,
                    isInProgress: isInProgress,
                    delta: delta,
                    peakMinutes: peakMinutes,
                    n: windowReadings.count
                )
            }
    }

    /// The newest `maxDrawnSweeps`. Input is expected newest-first (what `build`
    /// returns); the cap exists so a 90-day power user cannot push thousands of
    /// line marks into one `Chart`.
    static func capped(_ sweeps: [MealSweep]) -> [MealSweep] {
        Array(sweeps.prefix(maxDrawnSweeps))
    }

    /// The meal the LAPS card compares — the newest one that actually has a trace.
    ///
    /// Falling straight to `sweeps.first` would blank the card for the few minutes
    /// between logging a meal and the first reading landing after it; the newest
    /// *drawable* sweep is what the user can see on the chart.
    static func lapsSubject(_ sweeps: [MealSweep]) -> MealSweep? {
        sweeps.first(where: { !$0.points.isEmpty }) ?? sweeps.first
    }

    // MARK: Bins

    /// The p25/p50/p75 envelope, one entry per 5-minute offset that at least one
    /// sweep reached.
    ///
    /// In-progress sweeps are skipped unconditionally: the live trace is the thing
    /// being compared against the band, so letting it into the band would compare
    /// it with itself.
    static func bins(_ sweeps: [MealSweep], cleanOnly: Bool) -> [SweepBin] {
        let source = sweeps.filter { sweep in
            !sweep.isInProgress && (!cleanOnly || sweep.isClean)
        }
        guard !source.isEmpty else { return [] }

        var result: [SweepBin] = []
        for minute in stride(from: windowStartMinutes, through: windowEndMinutes, by: stepMinutes) {
            let values = source.compactMap { sweep in
                sweep.points.first(where: { $0.minute == minute })?.delta
            }
            guard !values.isEmpty else { continue }
            let sorted = values.sorted()
            result.append(SweepBin(
                minute: minute,
                p25: ClinicReportBuilder.percentile(sorted, 0.25),
                p50: ClinicReportBuilder.percentile(sorted, 0.5),
                p75: ClinicReportBuilder.percentile(sorted, 0.75),
                n: sorted.count
            ))
        }
        return result
    }

    // MARK: Filter

    static func filter(_ sweeps: [MealSweep], bucket: CarbBucket?, cleanOnly: Bool) -> [MealSweep] {
        sweeps.filter { sweep in
            if let bucket, sweep.carbBucket != bucket { return false }
            if cleanOnly, !sweep.isClean { return false }
            return true
        }
    }

    // MARK: Private

    /// One point per 5-minute step, taking the reading nearest that step's target
    /// time if one lies within `nearestToleranceSeconds`.
    private static func samplePoints(
        mealTime: Date,
        reference: Int,
        readings: [SensorGlucose],
        limit: Date?
    ) -> [SweepPoint] {
        var points: [SweepPoint] = []
        for minute in stride(from: windowStartMinutes, through: windowEndMinutes, by: stepMinutes) {
            let target = mealTime.addingTimeInterval(TimeInterval(minute * 60))
            if let limit, target > limit { break }

            let nearest = readings
                .filter { abs($0.timestamp.timeIntervalSince(target)) <= nearestToleranceSeconds }
                .min { abs($0.timestamp.timeIntervalSince(target)) < abs($1.timestamp.timeIntervalSince(target)) }

            guard let nearest else { continue }
            points.append(SweepPoint(minute: minute, delta: nearest.glucoseValue - reference))
        }
        return points
    }

    /// `detectMealConfounders` (MealOverlayLogic.swift:78-103), restated — see the
    /// file header for why it is restated rather than called.
    private static func isConfounded(
        meal: MealEntry,
        windowEnd: Date,
        deliveries: [InsulinDelivery],
        exercise: [ExerciseEntry],
        meals: [MealEntry]
    ) -> Bool {
        let hasCorrectionBolus = deliveries.contains { delivery in
            delivery.starts >= meal.timestamp && delivery.starts <= windowEnd && delivery.type == .correctionBolus
        }
        let hasExercise = exercise.contains { entry in
            entry.startTime <= windowEnd && entry.endTime >= meal.timestamp
        }
        let hasStackedMeal = meals.contains { other in
            other.id != meal.id && other.timestamp >= meal.timestamp && other.timestamp <= windowEnd
        }
        return hasCorrectionBolus || hasExercise || hasStackedMeal
    }
}

// MARK: - SweepChartMath

enum SweepChartMath {
    /// The artboard's axis, `−20 … +100` mg/dL — but as a FLOOR in both directions,
    /// not a fixed domain (P0's errata: a fixed ceiling clips real data). A meal
    /// followed by a hypo runs well below −20 and must stay visible.
    ///
    /// Every plotted series feeds this — the sweeps, the p25–p75 band, the median
    /// and today's trace — so there is exactly one y scale.
    /// Axis ticks across the domain, 20 mg/dL apart and stepping coarser rather
    /// than crowding the plot once the domain grows past the artboard's range.
    static func yTicksMgdl(domain: ClosedRange<Int>) -> [Int] {
        let span = domain.upperBound - domain.lowerBound
        let base = 20
        var step = base
        while step > 0, span / step > 6 { step += base }
        return Array(stride(from: domain.lowerBound, through: domain.upperBound, by: step))
    }

    static func yDomainMgdl(deltas: [Int]) -> ClosedRange<Int> {
        let step = 20.0
        let maxDelta = Double(deltas.max() ?? 0)
        let minDelta = Double(deltas.min() ?? 0)
        let top = max(100, Int((maxDelta / step).rounded(.up)) * Int(step))
        let bottom = min(-20, Int((minDelta / step).rounded(.down)) * Int(step))
        return bottom...top
    }
}

// MARK: - TwinSummary

/// What a set of twins agrees on. Never surfaced under `TwinFinder.minTwins`.
struct TwinSummary: Equatable {
    let medianDelta: Int
    let medianPeakMinutes: Int
    let n: Int
}

// MARK: - TwinFinder

/// "Which of my other meals were like this one?" — the LAPS card's comparison set.
enum TwinFinder {
    /// A twin's carbs must be within ±25 % of the subject's.
    static let carbTolerance = 0.25
    /// …and its time of day within ±90 minutes, wrapping at midnight.
    static let timeOfDayToleranceMinutes = 90
    /// Under three twins there is no median worth printing.
    static let minTwins = 3
    static let maxTwins = 5

    static func twins(for meal: MealSweep, in sweeps: [MealSweep], max maxCount: Int = maxTwins) -> [MealSweep] {
        guard let carbs = meal.carbs, carbs > 0 else { return [] }
        let lower = carbs * (1 - carbTolerance)
        let upper = carbs * (1 + carbTolerance)

        return sweeps
            .filter { candidate in
                guard candidate.id != meal.id else { return false }
                // A twin has to have finished responding, and has to be clean —
                // an unfinished or confounded meal cannot be a comparison.
                guard candidate.isClean, !candidate.isInProgress else { return false }
                guard candidate.carbBucket == meal.carbBucket else { return false }
                guard let candidateCarbs = candidate.carbs,
                      candidateCarbs >= lower, candidateCarbs <= upper else { return false }
                return minuteOfDayDistance(candidate.minutesOfDay, meal.minutesOfDay) <= timeOfDayToleranceMinutes
            }
            .sorted { $0.mealTime > $1.mealTime }
            .prefix(maxCount)
            .map { $0 }
    }

    static func summary(of twins: [MealSweep]) -> TwinSummary? {
        let deltas = twins.compactMap(\.delta).sorted()
        let peaks = twins.compactMap(\.peakMinutes).sorted()
        guard deltas.count >= minTwins, peaks.count >= minTwins else { return nil }

        return TwinSummary(
            medianDelta: ClinicReportBuilder.percentile(deltas, 0.5),
            medianPeakMinutes: ClinicReportBuilder.percentile(peaks, 0.5),
            n: deltas.count
        )
    }

    /// Distance on a 24-hour clock face: 23:30 and 00:30 are 60 minutes apart, not
    /// 1380.
    static func minuteOfDayDistance(_ lhs: Int, _ rhs: Int) -> Int {
        let raw = abs(lhs - rhs)
        return min(raw, 1440 - raw)
    }
}

// MARK: - SweepLapsFormatter

/// The LAPS card's two strings. Pure — no `Date()`, no locale-dependent date
/// formatting — so the artboard line is pinned by a test.
enum SweepLapsFormatter {

    /// `LAPS · 80g DINNER`
    static func title(for sweep: MealSweep) -> String {
        let name = sweep.mealDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let subject = name.isEmpty ? "MEAL" : name

        guard let carbs = sweep.carbs, carbs > 0 else { return "LAPS · \(subject)" }
        return "LAPS · \(carbsLabel(carbs)) \(subject)"
    }

    /// `TODAY +47 (38 MIN) · TWINS MEDIAN +41 · PEAK 55 MIN (n=4)`
    static func line(
        subject: MealSweep,
        twins: TwinSummary?,
        glucoseUnit: GlucoseUnit,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        var head = subjectLabel(for: subject, now: now, calendar: calendar)

        if let delta = subject.delta {
            head += " \(signedDelta(delta, glucoseUnit: glucoseUnit))"
            if let peak = subject.peakMinutes {
                head += " (\(peak) MIN)"
            }
        } else {
            head += " —"
        }

        guard let twins else {
            return "\(head) · TWINS n<\(TwinFinder.minTwins) · KEEP LOGGING"
        }

        return "\(head) · TWINS MEDIAN \(signedDelta(twins.medianDelta, glucoseUnit: glucoseUnit))"
            + " · PEAK \(twins.medianPeakMinutes) MIN (n=\(twins.n))"
    }

    /// `+47` / `−12`, converted for mmol/L users. Deltas are pure differences, so
    /// the mg/dL→mmol/L exchange rate applies without an offset.
    static func signedDelta(_ mgdl: Int, glucoseUnit: GlucoseUnit) -> String {
        if glucoseUnit == .mmolL {
            let value = mgdl.toMmolL()
            let text = GlucoseFormatters.mmolLFormatter.string(from: value as NSNumber) ?? "\(value)"
            return value >= 0 ? "+\(text)" : text
        }
        return mgdl >= 0 ? "+\(mgdl)" : "\(mgdl)"
    }

    /// One expanded twin: `3D AGO · 78g · +38 (52 MIN) · CLEAN`. The tag is the
    /// lesson — a twin earns its place by being clean.
    static func twinRow(_ sweep: MealSweep, glucoseUnit: GlucoseUnit) -> String {
        var parts: [String] = [sweep.ageDays <= 0 ? "TODAY" : "\(sweep.ageDays)D AGO"]

        if let carbs = sweep.carbs, carbs > 0 {
            parts.append(carbsLabel(carbs))
        }
        if let delta = sweep.delta {
            var response = signedDelta(delta, glucoseUnit: glucoseUnit)
            if let peak = sweep.peakMinutes {
                response += " (\(peak) MIN)"
            }
            parts.append(response)
        }
        parts.append(sweep.isClean ? "CLEAN" : "CONFOUNDED")

        return parts.joined(separator: " · ")
    }

    /// The axis caption: `Δ mg/dL from −15 min`, unit-aware.
    static func axisCaption(glucoseUnit: GlucoseUnit) -> String {
        "Δ \(glucoseUnit.localizedDescription) from −\(SweepStatistics.baselineWindowMinutes) min"
    }

    /// `N=23 SWEEPS · 14 CLEAN` — every caption carries its N.
    static func countCaption(total: Int, clean: Int) -> String {
        "N=\(total) SWEEPS · \(clean) CLEAN"
    }

    // MARK: Private

    /// `TODAY`, else `2D AGO`. A formatted month name would make this — and its
    /// test — locale-dependent for no gain; the artboard only ever shows TODAY.
    private static func subjectLabel(for sweep: MealSweep, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: sweep.mealTime),
            to: calendar.startOfDay(for: now)
        ).day ?? sweep.ageDays

        return days <= 0 ? "TODAY" : "\(days)D AGO"
    }

    static func carbsLabel(_ carbs: Double) -> String {
        let rounded = carbs.rounded()
        if abs(carbs - rounded) < 0.05 {
            return "\(Int(rounded))g"
        }
        return String(format: "%.1fg", carbs)
    }
}
