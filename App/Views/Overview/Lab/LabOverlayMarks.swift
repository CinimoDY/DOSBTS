//
//  LabOverlayMarks.swift
//  DOSBTS
//
//  The one switch every Chart Lab overlay goes through. P0 ships all seven arms
//  empty; P1/P2/P4/P5 each fill their own arm and nothing else in this file, so
//  the parallel branches never collide. Keep the switch exhaustive — the
//  compiler is what tells a later worker that a new case needs marks.
//

import Charts
import SwiftUI

enum LabOverlayMarks {
    @ChartContentBuilder
    static func marks(for overlay: ChartLabOverlay, series: LabChartSeries, yMax: Double) -> some ChartContent {
        switch overlay {
        case .carbSizedMeals:
            noMarks // P2 fills this arm — carb-sized meal marks.
        case .mealResponseRibbons:
            noMarks // P2 fills this arm — post-meal response ribbons.
        case .residualMarks:
            noMarks // P2 fills this arm — residual (predicted vs actual) marks.
        case .regimeBands:
            noMarks // P2 fills this arm — regime bands.
        case .nightContext:
            noMarks // P1 fills this arm — sleep stages, HR, cross-midnight ribbon.
        case .ghostBand:
            noMarks // P4 fills this arm — the personal 30-day band.
        case .factPins:
            noMarks // P5 fills this arm — fact pins.
        }
    }

    /// "This overlay draws nothing yet." Charts exposes no public
    /// `EmptyChartContent`, so an empty `ForEach` is the cheapest legal no-op.
    private static var noMarks: some ChartContent {
        ForEach([Int](), id: \.self) { _ in
            RuleMark(y: .value("", 0))
        }
    }
}
