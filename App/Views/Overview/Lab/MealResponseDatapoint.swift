//
//  MealResponseDatapoint.swift
//  DOSBTS
//
//  Chart Lab P2 (DMNC-1501). One meal, one two-hour response window, and the
//  reason — if there is one — that the window does not make a fair comparison.
//
//  Pure: no SwiftUI, no store, no database. `LabChartSeriesBuilder` builds these
//  off the main actor and `LabOverlayMarks` only draws what comes back.
//
//  The exclusion is the lesson. A ribbon that reads `NO BOLUS` is not blaming
//  the plate — it is saying which part of the story was never written down.
//  Nothing here is dosing advice, and the bracket is a PAIRING (`60g ⟷ 5U`),
//  never a ratio and never a recommendation.
//

import Foundation

// MARK: - MealResponseDatapoint

struct MealResponseDatapoint: Identifiable, Equatable {
    /// `MealEntry.id.uuidString`.
    let id: String
    let mealTime: Date
    /// Where the drawn ribbon stops: the window's current end, clamped into the
    /// chart's domain.
    let windowEnd: Date
    /// Where the window WILL close, for the dotted remainder — `nil` once it has.
    let stubEnd: Date?
    let carbs: Double?
    let summary: ResponseSummary
    /// Meal/snack boluses within ±15 min (corrections excluded), via the Ratio
    /// Lab's own pairing helper so the two surfaces cannot disagree.
    let pairedBolusUnits: Double
    /// `nil` = a fair window. Otherwise the Ratio Lab's taxonomy, so the teaching
    /// tags read the same here as they do in the evidence table.
    let exclusion: MealExclusionReason?
    let confounders: MealConfounders

    /// Whether the ribbon should be drawn as excluded rather than graded.
    var isExcluded: Bool { exclusion != nil }

    /// The ribbon's one line. Always ends in its reading count — a lab number
    /// without its `n` is a claim.
    func ribbonLabel(glucoseUnit: GlucoseUnit) -> String {
        if let exclusion {
            return MealResponseTag.label(for: exclusion, confounders: confounders, glucoseUnit: glucoseUnit)
        }

        guard let delta = summary.delta else {
            return "— · \(summary.n) RDG"
        }

        let sign = delta < 0 ? "-" : "+"
        let magnitude = abs(delta).asGlucose(glucoseUnit: glucoseUnit)

        if summary.isInProgress {
            let elapsed = Int((summary.end.timeIntervalSince(mealTime) / 60).rounded())
            return "\(sign)\(magnitude) · \(elapsed) MIN · \(summary.n) RDG"
        }

        return "\(sign)\(magnitude) · PEAK \(summary.timeToExtremumMinutes ?? 0)m · \(summary.n) RDG"
    }

    /// `60g ⟷ 5U` — what was eaten alongside what was taken. Grams with no
    /// paired bolus render alone (`10g`); a meal with no carbs recorded has
    /// nothing to pair and renders nothing.
    ///
    /// Deliberately NOT a ratio: there is no `÷`, no `1:X`, and no "should".
    var bracketLabel: String? {
        guard let carbs, carbs > 0 else { return nil }
        let grams = "\(Int(carbs.rounded()))g"
        guard pairedBolusUnits > 0 else { return grams }
        return "\(grams) ⟷ \(MealResponseDatapoint.formatUnits(pairedBolusUnits))"
    }

    /// True when the label needs the little bracket rule under the dot.
    var hasPairing: Bool {
        carbs != nil && pairedBolusUnits > 0
    }

    /// Which stagger row each ribbon's label takes, so two windows that overlap
    /// on the x axis do not print their labels on top of each other.
    ///
    /// Classic interval-lane packing: the lowest row whose previous occupant has
    /// already ended. Pure and id-keyed so the marks function stays a function
    /// of the series — and so the rule is pinned by a test rather than by eye.
    static func labelLanes(_ responses: [MealResponseDatapoint], maxLanes: Int = 4) -> [String: Int] {
        var laneEnds: [Date] = []
        var lanes: [String: Int] = [:]

        for response in responses.sorted(by: { $0.mealTime < $1.mealTime }) {
            let occupiedUntil = response.stubEnd ?? response.windowEnd

            if let free = laneEnds.indices.first(where: { laneEnds[$0] <= response.mealTime }) {
                laneEnds[free] = occupiedUntil
                lanes[response.id] = free
            } else if laneEnds.count < maxLanes {
                laneEnds.append(occupiedUntil)
                lanes[response.id] = laneEnds.count - 1
            } else {
                // More simultaneous windows than rows: reuse the one that frees
                // up soonest. Tight, but still readable — and four meals inside
                // one two-hour window is already the interesting story.
                let earliest = laneEnds.indices.min { laneEnds[$0] < laneEnds[$1] } ?? 0
                laneEnds[earliest] = occupiedUntil
                lanes[response.id] = earliest
            }
        }

        return lanes
    }

    /// Whole units read `5U`, part units `4.5U`. Deliberately not
    /// `Double.asInsulin()` (2-decimal and locale-comma — it renders `5,00U`
    /// next to a hero that says `5.0U`, the P0 unit-formatting learning).
    static func formatUnits(_ units: Double) -> String {
        units == units.rounded()
            ? String(format: "%.0fU", units)
            : String(format: "%.1fU", units)
    }
}

// MARK: - MealResponseTag

enum MealResponseTag {
    /// The teaching tag a ribbon shows instead of a delta. Strings mirror
    /// `RatioLabView`'s evidence-row tags so a user who has seen one recognises
    /// the other; `.confounded` is resolved to the confounder that caused it,
    /// which the evidence table cannot do.
    static func label(
        for reason: MealExclusionReason,
        confounders: MealConfounders,
        glucoseUnit: GlucoseUnit
    ) -> String {
        switch reason {
        case .confounded:
            if confounders.hasCorrectionBolus { return "CORR" }
            if confounders.hasExercise { return "EXERCISE" }
            if confounders.hasStackedMeal { return "STACKED" }
            return "CONFOUNDED"
        case .noBolus:
            return "NO BOLUS"
        case .tinyBolus:
            return "TINY BOLUS"
        case .noBaseline:
            return "NO BASELINE"
        case .baselineOutOfRange:
            // The lab classifier never emits this (it does not gate on the
            // baseline band); the arm exists so the taxonomy stays exhaustive.
            return "ODD START"
        case .smallMeal:
            return "SMALL MEAL"
        case .didNotReturnToBaseline(let delta):
            let sign = delta >= 0 ? "+" : "-"
            return "ENDED \(sign)\(abs(delta).asGlucose(glucoseUnit: glucoseUnit))"
        case .hypoInWindow:
            return "HYPO"
        case .implausibleRatio:
            return "ODD RATIO"
        case .insufficientData:
            return "NO CGM"
        }
    }
}

// MARK: - MealResponseClassifier

/// Why this window is not a fair comparison.
///
/// A deliberately SHORTER ladder than `RatioEstimator.score`: the Ratio Lab is
/// picking meals to estimate a ratio from, so it also rejects an odd baseline, a
/// tiny bolus and a CGM gap. The lab chart only wants to stop a ribbon from
/// blaming the plate for something else, so it keeps the five criteria a user
/// can see on the chart — in the estimator's own precedence order, so the tag
/// points at the earliest unmet requirement.
enum MealResponseClassifier {
    static func classify(
        meal: MealEntry,
        summary: ResponseSummary,
        pairedBolusUnits: Double,
        confounders: MealConfounders,
        readings: [SensorGlucose]
    ) -> MealExclusionReason? {
        // 1 — something else was happening in the window.
        if !confounders.isClean { return .confounded }

        // 2 — the insulin half of the pairing was never written down.
        if pairedBolusUnits <= 0 { return .noBolus }

        // 3 — too small for a ±5 g estimate to mean anything.
        if (meal.carbsGrams ?? 0) < RatioEstimator.minCarbsGrams { return .smallMeal }

        // 4 — a hypo we can SEE always wins: it is the safety-critical lesson.
        if let minInWindow = RatioEstimator.minGlucoseInWindow(
            mealTimestamp: meal.timestamp,
            readings: readings
        ), minInWindow < RatioEstimator.hypoThresholdMgDL {
            return .hypoInWindow
        }

        // 5 — where it ENDED is only knowable once the window has closed. A live
        //     ribbon is never judged on a number it does not have yet.
        guard !summary.isInProgress else { return nil }

        if let baseline = summary.baseline,
           let endGlucose = RatioEstimator.endGlucose(mealTimestamp: meal.timestamp, readings: readings) {
            let delta = endGlucose - baseline
            if abs(delta) > RatioEstimator.returnToBaselineToleranceMgDL {
                return .didNotReturnToBaseline(deltaMgDL: delta)
            }
        }

        return nil
    }
}

// MARK: - Builder

/// Build one response per meal that can show on the chart.
///
/// `meals` is the FULL entry list: the domain filter decides what is drawn, but
/// stacked-meal detection has to see the neighbours either side of the edge.
func buildMealResponses(
    meals: [MealEntry],
    readings: [SensorGlucose],
    deliveries: [InsulinDelivery],
    exercise: [ExerciseEntry],
    domainStart: Date,
    domainEnd: Date,
    now: Date = Date()
) -> [MealResponseDatapoint] {
    // A meal up to one window-length before the domain still has a ribbon
    // reaching into it.
    let earliest = domainStart.addingTimeInterval(-ResponseKernel.mealLagSeconds)
    let sortedReadings = readings.sorted { $0.timestamp < $1.timestamp }

    return meals
        .filter { $0.timestamp >= earliest && $0.timestamp <= domainEnd }
        .sorted { $0.timestamp < $1.timestamp }
        .map { meal in
            let summary = ResponseKernel.summarize(
                .meal(at: meal.timestamp),
                readings: sortedReadings,
                now: now
            )
            let paired = RatioEstimator.pairedBolusUnits(
                mealTimestamp: meal.timestamp,
                deliveries: deliveries
            )
            let confounders = detectMealConfounders(
                meal: meal,
                insulinDeliveryValues: deliveries,
                exerciseEntryValues: exercise,
                mealEntryValues: meals
            )
            let closesAt = meal.timestamp.addingTimeInterval(ResponseKernel.mealLagSeconds)

            return MealResponseDatapoint(
                id: meal.id.uuidString,
                mealTime: meal.timestamp,
                windowEnd: min(summary.end, domainEnd),
                stubEnd: summary.isInProgress ? min(closesAt, domainEnd) : nil,
                carbs: meal.carbsGrams,
                summary: summary,
                pairedBolusUnits: paired,
                exclusion: MealResponseClassifier.classify(
                    meal: meal,
                    summary: summary,
                    pairedBolusUnits: paired,
                    confounders: confounders,
                    readings: sortedReadings
                ),
                confounders: confounders
            )
        }
}
