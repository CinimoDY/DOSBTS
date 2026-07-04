//
//  RatioEstimator.swift
//  DOSBTS
//
//  Pure ICR (insulin-to-carb ratio) / ISF (insulin sensitivity factor) estimation
//  core for the Ratio Lab (DMNC-1291 track, WP-R1). No UI, no Redux, no I/O — the
//  same "pure logic, exhaustively unit-tested" shape as `IOBCalculator.swift` and
//  `TightControlStreakDetector`.
//
//  Clinical formulas (Walsh, *Using Insulin*):
//   • 500 rule:  ICR (g/U)      = 500 / TDD           — 500 is the rapid-analog constant
//                                                        (matches both `InsulinPreset` cases;
//                                                        the 450 variant is for regular insulin).
//   • 1800 rule: ISF (mg/dL/U)  = 1800 / TDD          — mmol/L display converts the mg/dL
//                                                        result via the existing exchange rate
//                                                        (equivalent to the "100 rule").
//   • Empirical ICR: median of carbs÷bolus over qualifying "clean" meals; spread = P25–P75.
//
//  This feature never emits dosing commands — it estimates and teaches. Every estimate
//  ships with its uncertainty (day count, meal count, spread) and is gated behind a
//  minimum sample size so a handful of days can't produce a confident-looking number.
//
//  See docs/plans/2026-07-03-ratio-lab-plan.md § WP-R1 for the full spec, clinical
//  rationale, and the test matrix that pins every threshold below.
//

import Foundation

// MARK: - TDDDay

/// One complete day's total daily insulin dose, split into basal and bolus.
/// `bolusUnits` is the sum of meal + snack + correction boluses.
struct TDDDay: Equatable {
    let date: Date
    let basalUnits: Double
    let bolusUnits: Double

    /// Total daily dose = basal + bolus.
    var totalUnits: Double { basalUnits + bolusUnits }
}

// MARK: - MealObservation

/// A single candidate meal for empirical-ICR estimation, with its glucose response
/// already resolved. `pairedBolusUnits`, `endGlucose`, and `minGlucoseInWindow` are
/// pre-computed by the wiring layer (WP-R2) via the pure helpers on `RatioEstimator`
/// (`pairedBolusUnits(mealTimestamp:deliveries:)`, `endGlucose(...)`, `minGlucoseInWindow(...)`),
/// so the estimator itself stays a pure function of already-resolved numbers.
struct MealObservation: Equatable {
    let meal: MealEntry
    let impact: MealImpact
    /// Sum of meal/snack boluses within ±15 min of `meal.timestamp` (correction boluses excluded).
    let pairedBolusUnits: Double
    /// Glucose reading nearest t+120 min (within t+105..t+135); `nil` when the CGM had a gap there.
    let endGlucose: Int?
    /// Minimum glucose in [t, t+2h]; `nil` when the CGM had no readings in the window.
    let minGlucoseInWindow: Int?
}

// MARK: - RatioEvidence

/// The full, pre-resolved input to `RatioEstimator.estimate(evidence:)`.
struct RatioEvidence: Equatable {
    let tddDays: [TDDDay]
    let mealObservations: [MealObservation]
}

// MARK: - MealExclusionReason

/// Why a candidate meal did not qualify for empirical-ICR estimation. These double as the
/// teaching tags the UI shows in the evidence table — the exclusion reason *is* the lesson.
enum MealExclusionReason: Equatable {
    /// The meal's glucose response is confounded (correction bolus in the pairing window,
    /// overlapping exercise, or a stacked meal) — `MealImpact.isClean == false`. This is the
    /// plan's meal criterion 1; the wiring layer (WP-R2) also pre-filters on it, but the
    /// estimator enforces it here too so a loader regression can't pollute the empirical median.
    case confounded
    /// No paired meal/snack bolus was logged (insulin not recorded).
    case noBolus
    /// No pre-meal baseline glucose was available.
    case noBaseline
    /// Baseline outside 70–180 mg/dL — a low start invites rescue carbs, a high start makes
    /// the bolus part-correction; either distorts the ratio.
    case baselineOutOfRange
    /// Meal too small (<15 g) — below that, ±5 g estimation error dominates the ratio.
    case smallMeal
    /// A bolus was logged but under 0.5 U — too small to attribute a ratio to reliably.
    case tinyBolus
    /// Glucose did not return near baseline by +2h (`|end − baseline| > 30 mg/dL`).
    /// `deltaMgDL` is signed (positive = ended high, negative = ended low).
    case didNotReturnToBaseline(deltaMgDL: Int)
    /// A hypo occurred within the 2h window — proves overshoot and likely unlogged rescue carbs.
    case hypoInWindow
    /// Computed ratio outside the 2–50 g/U sanity band.
    case implausibleRatio
    /// Not enough CGM data in the 2h window to score the meal (missing the +2h reading or the
    /// in-window minimum). The plan's criterion 6 excludes meals with a missing 2h reading; this
    /// case carries that exclusion since the original reason sketch had no data-gap tag.
    case insufficientData
}

// MARK: - ScoredMealObservation

/// A candidate meal after scoring: exactly one of `ratio` (qualified) or `exclusion` (rejected)
/// is non-nil. The full list of these — qualified and rejected — is surfaced to the evidence table.
struct ScoredMealObservation: Equatable {
    let observation: MealObservation
    /// Estimated ICR (g/U) when the meal qualifies; `nil` when excluded.
    let ratio: Double?
    /// Why the meal was excluded; `nil` when it qualifies.
    let exclusion: MealExclusionReason?
}

// MARK: - RatioEstimates

/// The estimator's output. Rule-based estimates are gated behind `minQualifyingDays`; the
/// empirical estimate behind `minQualifyingMeals`. `scoredObservations` carries every candidate
/// (qualified + rejected) for the evidence table.
///
/// Note on `Equatable`: the synthesized conformance chains through `MealEntry`/`MealImpact`,
/// whose `==` is *identity-only* (by `id`). Compare estimates field-by-field in tests rather
/// than relying on whole-struct `==` for two independently-built results.
struct RatioEstimates: Equatable {
    /// Median TDD over qualifying days; `nil` until the day gate is met.
    let averageTDD: Double?
    /// Number of days that qualified (≥1 basal AND ≥1 bolus) — reported even below the gate for the "n/5" counter.
    let qualifyingDayCount: Int
    /// 500-rule ICR (g/U); `nil` until ≥`minQualifyingDays` qualifying days.
    let fiveHundredRuleICR: Double?
    /// 1800-rule ISF (mg/dL per U); same gate. The view converts to mmol/L for display.
    let eighteenHundredRuleISFMgDL: Double?
    /// Empirical ICR = median carbs÷bolus over qualifying meals; `nil` until ≥`minQualifyingMeals`.
    let empiricalICR: Double?
    /// P25–P75 spread of the qualifying meal ratios; `nil` when `empiricalICR` is `nil`.
    let empiricalICRSpread: ClosedRange<Double>?
    /// All candidate meals, scored — for the evidence table.
    let scoredObservations: [ScoredMealObservation]
}

// MARK: - RatioEstimator

enum RatioEstimator {

    // MARK: Thresholds (test-pinned; see docs/plans/2026-07-03-ratio-lab-plan.md § WP-R1)

    /// TDD look-back: the last 14 *complete* days.
    static let tddLookbackDays: Int = 14
    /// Minimum qualifying days before any TDD-derived estimate is surfaced.
    static let minQualifyingDays: Int = 5
    /// Walsh "500 rule" numerator (rapid analogs): ICR = 500 / TDD.
    static let fiveHundredConstant: Double = 500
    /// Walsh "1800 rule" numerator: ISF(mg/dL) = 1800 / TDD.
    static let eighteenHundredConstant: Double = 1800
    /// Neutral pre-meal baseline band (mg/dL): low start → rescue carbs distort; high start → bolus is part-correction.
    static let baselineMinMgDL: Int = 70
    static let baselineMaxMgDL: Int = 180
    /// Minimum paired meal/snack bolus (U) to attribute a ratio.
    static let minPairedBolusUnits: Double = 0.5
    /// Pairing window (min) around the meal timestamp for meal/snack boluses.
    static let pairingWindowMinutes: Int = 15
    /// Minimum carbs (g) — below this, ±5 g estimation error dominates.
    static let minCarbsGrams: Double = 15
    /// Hypo threshold (mg/dL) inside the post-meal window.
    static let hypoThresholdMgDL: Int = 70
    /// Post-meal observation window (min) for the hypo check.
    static let hypoWindowMinutes: Int = 120
    /// Tolerance (mg/dL) for "returned near baseline" at +2h.
    static let returnToBaselineToleranceMgDL: Int = 30
    /// Target offset (min) for the end-of-window reading.
    static let endGlucoseTargetMinutes: Int = 120
    /// End-window bounds (min) — CGM-gap tolerant around the +120 target.
    static let endGlucoseWindowLowerMinutes: Int = 105
    static let endGlucoseWindowUpperMinutes: Int = 135
    /// Ratio sanity clamp (g/U).
    static let minRatioGramsPerUnit: Double = 2
    static let maxRatioGramsPerUnit: Double = 50
    /// Minimum qualifying meals before the empirical estimate is surfaced.
    static let minQualifyingMeals: Int = 5
    /// Maximum confounded (isClean == false) MealImpact rows the evidence loader surfaces
    /// in the table. Capped so a run of confounded meals cannot crowd out clean teaching rows;
    /// the most-recent N are selected by the loader.
    static let maxConfoundedEvidenceRows: Int = 3

    // MARK: Estimation

    static func estimate(evidence: RatioEvidence) -> RatioEstimates {
        // --- TDD-derived (500 / 1800 rules) ---
        // A day counts only with BOTH basal and bolus logged: basal-only or bolus-only is a
        // logging gap for an MDI user, not a genuinely low-insulin day.
        let qualifyingDays = evidence.tddDays.filter { $0.basalUnits > 0 && $0.bolusUnits > 0 }
        let qualifyingDayCount = qualifyingDays.count

        // Median, not mean: robust to a single forgotten bolus dragging the day's total down.
        let averageTDD: Double? = qualifyingDayCount >= minQualifyingDays
            ? median(qualifyingDays.map { $0.totalUnits })
            : nil
        let fiveHundredRuleICR = averageTDD.map { fiveHundredConstant / $0 }
        let eighteenHundredRuleISFMgDL = averageTDD.map { eighteenHundredConstant / $0 }

        // --- Empirical (carbs÷bolus over clean meals) ---
        let scored = evidence.mealObservations.map(score(_:))
        let qualifyingRatios = scored.compactMap { $0.ratio }.sorted()

        let empiricalICR: Double?
        let empiricalICRSpread: ClosedRange<Double>?
        if qualifyingRatios.count >= minQualifyingMeals {
            empiricalICR = percentile(qualifyingRatios, 0.5)
            empiricalICRSpread = percentile(qualifyingRatios, 0.25)...percentile(qualifyingRatios, 0.75)
        } else {
            empiricalICR = nil
            empiricalICRSpread = nil
        }

        return RatioEstimates(
            averageTDD: averageTDD,
            qualifyingDayCount: qualifyingDayCount,
            fiveHundredRuleICR: fiveHundredRuleICR,
            eighteenHundredRuleISFMgDL: eighteenHundredRuleISFMgDL,
            empiricalICR: empiricalICR,
            empiricalICRSpread: empiricalICRSpread,
            scoredObservations: scored
        )
    }

    /// Score a single candidate meal. Criteria are checked in the plan's numbered order
    /// (1 → 7); the first failing criterion wins, so the teaching tag points at the earliest
    /// unmet requirement. A *visible* hypo is checked before the CGM-coverage gate so a real
    /// low (the safety-critical lesson) is never masked by a missing +2h reading.
    static func score(_ observation: MealObservation) -> ScoredMealObservation {
        func excluded(_ reason: MealExclusionReason) -> ScoredMealObservation {
            ScoredMealObservation(observation: observation, ratio: nil, exclusion: reason)
        }

        let carbs = observation.meal.carbsGrams ?? 0 // nil = carbs never recorded → fails the size gate (criterion 4)
        let bolus = observation.pairedBolusUnits

        // 1 — the meal's glucose response must be unconfounded.
        if !observation.impact.isClean { return excluded(.confounded) }

        // 2 — baseline present and in the neutral band.
        guard let baseline = observation.impact.baselineGlucose else { return excluded(.noBaseline) }
        if baseline < baselineMinMgDL || baseline > baselineMaxMgDL { return excluded(.baselineOutOfRange) }

        // 3 — paired meal/snack bolus present and ≥ 0.5 U.
        if bolus <= 0 { return excluded(.noBolus) }
        if bolus < minPairedBolusUnits { return excluded(.tinyBolus) }

        // 4 — meal large enough to estimate against.
        if carbs < minCarbsGrams { return excluded(.smallMeal) }

        // 5 — a hypo we can see always wins, even if the +2h reading is missing.
        if let minInWindow = observation.minGlucoseInWindow, minInWindow < hypoThresholdMgDL {
            return excluded(.hypoInWindow)
        }

        // 5 / 6 — otherwise we need full CGM coverage: the in-window minimum (to rule out a hypo
        //         we can't see) and the +2h reading (to confirm return to baseline).
        guard observation.minGlucoseInWindow != nil, let endGlucose = observation.endGlucose else {
            return excluded(.insufficientData)
        }

        // 6 — returned near baseline by +2h (signed delta: positive = ended high, negative = ended low).
        let delta = endGlucose - baseline
        if abs(delta) > returnToBaselineToleranceMgDL {
            return excluded(.didNotReturnToBaseline(deltaMgDL: delta))
        }

        // 7 — ratio sanity clamp.
        let ratio = carbs / bolus
        if ratio < minRatioGramsPerUnit || ratio > maxRatioGramsPerUnit {
            return excluded(.implausibleRatio)
        }

        return ScoredMealObservation(observation: observation, ratio: ratio, exclusion: nil)
    }

    // MARK: Evidence builders (pure; wired by the WP-R2 DataStore/middleware)
    //
    // These live here — not in the wiring layer — so the derivations that feed `MealObservation`
    // and `TDDDay` are pinned by the same unit-test suite as the estimator itself.

    /// Bucket insulin deliveries into complete-day totals, restricted to the last
    /// `tddLookbackDays` complete days (today, still in progress, is excluded). Basal is
    /// attributed to its `starts` date (consistent with `DailyDigest`). Days that end up
    /// basal-only or bolus-only are still returned; `estimate(evidence:)` decides qualification.
    static func tddDays(from deliveries: [InsulinDelivery], asOf: Date, calendar: Calendar = .current) -> [TDDDay] {
        let startOfToday = calendar.startOfDay(for: asOf)
        guard let windowStart = calendar.date(byAdding: .day, value: -tddLookbackDays, to: startOfToday) else {
            return []
        }

        let inWindow = deliveries.filter { $0.starts >= windowStart && $0.starts < startOfToday }
        let byDay = Dictionary(grouping: inWindow) { calendar.startOfDay(for: $0.starts) }

        return byDay.map { day, items -> TDDDay in
            let basal: Double = items.filter { $0.type == .basal }.reduce(0.0) { $0 + $1.units }
            let bolus: Double = items.filter { $0.type != .basal }.reduce(0.0) { $0 + $1.units }
            return TDDDay(date: day, basalUnits: basal, bolusUnits: bolus)
        }
        .sorted { $0.date < $1.date }
    }

    /// Sum meal/snack boluses within ±`pairingWindowMinutes` of the meal timestamp. Uses a time
    /// window rather than timegroup equality — floor-rounding to a timegroup would split a
    /// 12:14 meal from a 12:16 bolus. Correction and basal deliveries are excluded (a correction
    /// covers a high, not the carbs).
    static func pairedBolusUnits(mealTimestamp: Date, deliveries: [InsulinDelivery]) -> Double {
        let window = TimeInterval(pairingWindowMinutes * 60)
        let paired = deliveries.filter {
            ($0.type == .mealBolus || $0.type == .snackBolus)
                && abs($0.starts.timeIntervalSince(mealTimestamp)) <= window
        }
        return paired.reduce(0.0) { $0 + $1.units }
    }

    /// The glucose reading nearest t+`endGlucoseTargetMinutes`, restricted to
    /// [t+lower, t+upper] to tolerate CGM gaps. On a distance tie the earlier reading wins.
    /// `nil` when no reading falls in the window.
    static func endGlucose(mealTimestamp: Date, readings: [SensorGlucose]) -> Int? {
        let target = mealTimestamp.addingTimeInterval(TimeInterval(endGlucoseTargetMinutes * 60))
        let lower = mealTimestamp.addingTimeInterval(TimeInterval(endGlucoseWindowLowerMinutes * 60))
        let upper = mealTimestamp.addingTimeInterval(TimeInterval(endGlucoseWindowUpperMinutes * 60))

        let candidates = readings
            .filter { $0.timestamp >= lower && $0.timestamp <= upper }
            .sorted { $0.timestamp < $1.timestamp }

        // `min(by:)` returns the first minimal element, so the earlier reading wins ties.
        return candidates.min {
            abs($0.timestamp.timeIntervalSince(target)) < abs($1.timestamp.timeIntervalSince(target))
        }?.glucoseValue
    }

    /// Minimum glucose in [t, t+`hypoWindowMinutes`]; `nil` when no reading falls in the window.
    static func minGlucoseInWindow(mealTimestamp: Date, readings: [SensorGlucose]) -> Int? {
        let upper = mealTimestamp.addingTimeInterval(TimeInterval(hypoWindowMinutes * 60))
        return readings
            .filter { $0.timestamp >= mealTimestamp && $0.timestamp <= upper }
            .map { $0.glucoseValue }
            .min()
    }

    // MARK: Display

    /// Canonical `1:X` ICR label (rounded whole grams-per-unit). Used by every
    /// surface that renders a ratio — the Ratio Lab estimates grid, evidence
    /// rows, and the Settings reference line — so the format can never drift
    /// between them. Non-finite input (a stray NaN/Inf from bad logged data)
    /// renders `—` rather than trapping in `Int(_:)`.
    static func icrLabel(_ ratio: Double) -> String {
        guard ratio.isFinite else { return "—" }
        return "1:\(Int(ratio.rounded()))"
    }

    // MARK: Statistics helpers

    /// Median via `percentile(_:0.5)`; `nil` for an empty sample.
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return percentile(values.sorted(), 0.5)
    }

    /// Linear-interpolation percentile (type-7 / numpy default / Excel `PERCENTILE.INC`):
    /// rank = p·(n−1), interpolating between the two nearest order statistics. `values` must be
    /// sorted ascending; an empty sample has no percentile and returns 0 (callers gate on sample size).
    static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard let first = values.first else { return 0 }
        if values.count == 1 { return first }
        let rank = p * Double(values.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = Int(rank.rounded(.up))
        if lower == upper { return values[lower] }
        let fraction = rank - Double(lower)
        return values[lower] + fraction * (values[upper] - values[lower])
    }
}
