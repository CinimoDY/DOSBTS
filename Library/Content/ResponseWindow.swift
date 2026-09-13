//
//  ResponseWindow.swift
//  DOSBTS
//
//  Chart Lab (DMNC-1501) cause→effect kernel. One anchor-agnostic window
//  summariser that the meal ribbons use today and exercise / sleep / regime
//  bands can use tomorrow without a second copy of the same arithmetic.
//
//  Pure Foundation on purpose: no SwiftUI, no store, no database — both targets
//  compile `Library/`, and the whole point of lifting this out of
//  `MealOverlayLogic.swift` is that it can be pinned by unit tests.
//
//  The meal case is a PORT, not a rewrite: `computeMealOverlayDelta` delegates
//  here and its numbers must not move (pinned by `MealOverlayDeltaParityTests`).
//
//  Nothing here is dosing advice — it measures what happened after a thing.
//

import Foundation

// MARK: - ResponseWindow

/// Anchor-agnostic cause→effect window.
///
/// Meals take the `.max` over 2 h; exercise will take the `.min` over 3 h; a
/// sleep or regime band reads its `.slope`. The shape is the same every time:
/// a short lookback for the baseline, a longer window for the effect, and one
/// rule for what "the effect" means.
struct ResponseWindow: Equatable {
    /// How the window's effect is read off the trace.
    enum Summary: Equatable {
        /// The window's highest (meals) or lowest (exercise) reading.
        case extremum(Extremum)
        /// The window's LAST reading — a band's drift rather than its peak.
        case slope
    }

    enum Extremum: Equatable {
        case max
        case min
    }

    /// The event the window hangs off.
    let anchor: Date
    /// Baseline lookback before the anchor. Meals: 15 min.
    let lead: TimeInterval
    /// Window length after the anchor. Meals: 2 h.
    let lag: TimeInterval
    let summary: Summary

    /// The shipping meal window: 15 min of lead, 2 h of lag, read at its peak.
    static func meal(at anchor: Date) -> ResponseWindow {
        ResponseWindow(
            anchor: anchor,
            lead: ResponseKernel.mealLeadSeconds,
            lag: ResponseKernel.mealLagSeconds,
            summary: .extremum(.max)
        )
    }
}

// MARK: - ResponseSummary

/// What a window measured. Every number ships with the `n` it came from — a lab
/// number without its sample size is a claim, and the lab never makes claims.
struct ResponseSummary: Equatable {
    /// Last reading in `[anchor − lead, anchor)`; `nil` when the CGM had a gap
    /// there (the window then references its own first reading instead).
    let baseline: Int?
    /// The window's max / min / last, per `ResponseWindow.Summary`.
    let extremum: Int?
    /// `extremum − reference`, where the reference is `baseline` when there is
    /// one and the first in-window reading otherwise. Signed.
    let delta: Int?
    /// Minutes from the anchor to the reading `extremum` came from.
    let timeToExtremumMinutes: Int?
    /// Readings inside `[anchor, end]`.
    let n: Int
    /// Too few readings to trust the shape — NOT the same as no readings at all
    /// (see `ResponseKernel.lowConfidenceReadings`).
    let isLowConfidence: Bool
    /// The window has not closed yet: `now` is still inside `[anchor, anchor + lag)`.
    let isInProgress: Bool
    /// `min(anchor + lag, now)` — where the window currently stops.
    let end: Date

    /// Nothing measurable at `end`.
    static func empty(end: Date, isInProgress: Bool) -> ResponseSummary {
        ResponseSummary(
            baseline: nil,
            extremum: nil,
            delta: nil,
            timeToExtremumMinutes: nil,
            n: 0,
            isLowConfidence: false,
            isInProgress: isInProgress,
            end: end
        )
    }
}

// MARK: - ResponseKernel

enum ResponseKernel {
    // MARK: Thresholds (test-pinned)

    /// Meal baseline lookback.
    static let mealLeadSeconds: TimeInterval = 15 * 60
    /// Meal effect window.
    static let mealLagSeconds: TimeInterval = 2 * 60 * 60
    /// Fewer in-window readings than this and the shape is not trustworthy.
    /// Carried over verbatim from `MealOverlayLogic`'s `readings.count < 4`.
    static let lowConfidenceReadings = 4

    // MARK: Summarising

    /// Summarise `readings` over `window`.
    ///
    /// `readings` is used in the order it arrives (callers hand over
    /// time-sorted store arrays); the baseline is the LAST qualifying element,
    /// exactly as the shipping meal overlay read it.
    static func summarize(
        _ window: ResponseWindow,
        readings: [SensorGlucose],
        now: Date = Date()
    ) -> ResponseSummary {
        let closesAt = window.anchor.addingTimeInterval(window.lag)
        let isInProgress = now < closesAt
        let end = min(closesAt, now)

        let inWindow = readings.filter { $0.timestamp >= window.anchor && $0.timestamp <= end }

        guard !inWindow.isEmpty else {
            // No readings is not "low confidence" — it is no measurement at
            // all, and `delta == nil` is what says so. Collapsing the two would
            // also change `computeMealOverlayDelta`, which returns
            // `isLowConfidence: false` on this path.
            return .empty(end: end, isInProgress: isInProgress)
        }

        let baselineStart = window.anchor.addingTimeInterval(-window.lead)
        let baseline = readings
            .filter { $0.timestamp >= baselineStart && $0.timestamp < window.anchor }
            .last

        let reference = baseline?.glucoseValue ?? inWindow[0].glucoseValue

        let summarised: SensorGlucose? = {
            switch window.summary {
            case .extremum(.max):
                return inWindow.max(by: { $0.glucoseValue < $1.glucoseValue })
            case .extremum(.min):
                return inWindow.min(by: { $0.glucoseValue < $1.glucoseValue })
            case .slope:
                return inWindow.last
            }
        }()

        guard let summarised else {
            return .empty(end: end, isInProgress: isInProgress)
        }

        let minutes = summarised.timestamp.timeIntervalSince(window.anchor) / 60

        return ResponseSummary(
            baseline: baseline?.glucoseValue,
            extremum: summarised.glucoseValue,
            delta: summarised.glucoseValue - reference,
            timeToExtremumMinutes: Int(minutes.rounded()),
            n: inWindow.count,
            isLowConfidence: inWindow.count < lowConfidenceReadings,
            isInProgress: isInProgress,
            end: end
        )
    }
}
