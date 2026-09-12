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
            nightContext(series: series, yMax: yMax)
        case .ghostBand:
            noMarks // P4 fills this arm — the personal 30-day band.
        case .factPins:
            noMarks // P5 fills this arm — fact pins.
        }
    }

    // MARK: - P1 — night context (DMNC-1506)

    /// What the night adds UNDER the trace: the sleep band with its awake gaps
    /// carved out, the carried-in meal-response ribbons, the midnight rule, and
    /// the night's first low.
    ///
    /// Heart rate is deliberately NOT here — `LabChartView` already draws it,
    /// gated by `series.showsHeartRate`, which the window path forces on. Two
    /// draws would mean two lines.
    ///
    /// No glow anywhere: shadows inside a `Chart{}` are a documented
    /// performance trap.
    @ChartContentBuilder
    private static func nightContext(series: LabChartSeries, yMax: Double) -> some ChartContent {
        let context = series.nightContext

        // Time asleep, as a wash the trace reads through.
        if let band = context.sleepBand {
            RectangleMark(
                xStart: .value("Asleep", band.start),
                xEnd: .value("Wake", band.end),
                yStart: .value("Bottom", 0),
                yEnd: .value("Top", yMax)
            )
            .foregroundStyle(AmberTheme.cgaCyan.opacity(0.05))
        }

        // Awakenings, carved back out of it.
        ForEach(context.awakeGaps, id: \.start) { gap in
            RectangleMark(
                xStart: .value("Awake", gap.start),
                xEnd: .value("Asleep again", gap.end),
                yStart: .value("Bottom", 0),
                yEnd: .value("Top", yMax)
            )
            .foregroundStyle(AmberTheme.cgaCyan.opacity(0.25))
        }

        // The evening meal's two-hour response, carried across the left edge.
        ForEach(series.mealRibbons) { ribbon in
            RectangleMark(
                xStart: .value("Meal", ribbon.start),
                xEnd: .value("Response end", ribbon.end),
                yStart: .value("Bottom", 0),
                yEnd: .value("Top", yMax)
            )
            .foregroundStyle(AmberTheme.amber.opacity(0.1))
            .annotation(
                position: .top,
                alignment: .leading,
                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
            ) {
                Text(ribbon.label)
                    .font(DOSTypography.micro)
                    .foregroundStyle(AmberTheme.amber)
                    .monospacedDigit()
                    .labelHalo()
            }
        }

        // The date boundary no shipping window can show.
        if let midnight = context.midnight {
            RuleMark(x: .value("Midnight", midnight))
                .foregroundStyle(AmberTheme.amberDark)
                .lineStyle(StrokeStyle(lineWidth: 1))
                .annotation(
                    position: .bottom,
                    alignment: .leading,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    Text(verbatim: "00:00")
                        .font(DOSTypography.micro)
                        .foregroundStyle(AmberTheme.amberDark)
                        .monospacedDigit()
                        .labelHalo()
                }
        }

        // The night's first low, labelled with the value itself.
        if let hypo = context.hypo {
            PointMark(
                x: .value("Time", hypo.time),
                y: .value("Glucose", hypo.value)
            )
            .symbolSize(0)
            .annotation(
                position: .bottom,
                spacing: 10,
                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
            ) {
                Text(hypo.label)
                    .font(DOSTypography.micro)
                    .foregroundStyle(AmberTheme.cgaRed)
                    .monospacedDigit()
                    .labelHalo()
            }
        }
    }

    // MARK: - Label halo

    /// "This overlay draws nothing yet." Charts exposes no public
    /// `EmptyChartContent`, so an empty `ForEach` is the cheapest legal no-op.
    private static var noMarks: some ChartContent {
        ForEach([Int](), id: \.self) { _ in
            RuleMark(y: .value("", 0))
        }
    }
}

// MARK: - In-plot label legibility

private extension View {
    /// A scrim behind an in-plot annotation, so a label sitting on top of the
    /// glucose trace stays readable. The prototype does this with
    /// `paint-order: stroke fill` and a black stroke; the basal-bar annotation
    /// in `LabChartView` already does it with a fill. Never a glow — shadows
    /// inside a `Chart{}` are a documented performance trap.
    func labelHalo() -> some View {
        padding(.horizontal, 2.5)
            .background(AmberTheme.scrimHeavy)
    }
}
