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
    private enum Config {
        /// The stage lane's tallest cell, as a fraction of the y domain.
        static let stageLaneHeight: Double = 0.06
    }

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
            // P4 (DMNC-1503) — the user's own hourly band, ghosted under today.
            if let band = series.patternBand {
                ghostBand(band, yMax: yMax)
            }
        case .factPins:
            LabFactPins.marks(facts: series.facts, series: series, yMax: yMax)
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

        // The sleep-stage lane, drawn IN the chart so it shares the x scale
        // exactly — deepest sleep tallest, anchored to the plot floor.
        ForEach(Array(context.stageCells.enumerated()), id: \.offset) { _, cell in
            RectangleMark(
                xStart: .value("Stage start", cell.start),
                xEnd: .value("Stage end", cell.end),
                yStart: .value("Bottom", 0),
                yEnd: .value("Stage depth", yMax * Config.stageLaneHeight * cell.stage.laneWeight)
            )
            .foregroundStyle(AmberTheme.cgaCyan.opacity(cell.stage.laneWeight))
        }

        // Awakenings, carved back out of it.
        ForEach(Array(context.awakeGaps.enumerated()), id: \.offset) { _, gap in
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

    // MARK: - P4 · ghost band

    private enum GhostBand {
        /// The prototype's two washes (artboard 5): the outer p5–p95 must stay
        /// faint enough that today's trace never competes with it.
        static let outerOpacity: Double = 0.07
        static let innerOpacity: Double = 0.16
        static let medianOpacity: Double = 0.5
        static let medianStyle: StrokeStyle = .init(lineWidth: 1)
        static let dashedStyle: StrokeStyle = .init(lineWidth: 1, dash: [3, 3])
        static let tickStyle: StrokeStyle = .init(lineWidth: 3)
        /// The out-of-band tick's height, as a fraction of the plot.
        static let tickHeight: Double = 0.035
        static let markerSymbolSize: CGFloat = 60
    }

    /// Pure rendering: every position, value and unit conversion was decided by
    /// `PatternBandBuilder`. This arm chooses colours and nothing else.
    @ChartContentBuilder
    private static func ghostBand(_ band: PatternBandLayer, yMax: Double) -> some ChartContent {
        // The `series:` labels are load-bearing — without them the three loops
        // auto-group into one stack and only the last renders.
        ForEach(band.points, id: \.time) { point in
            AreaMark(
                x: .value("Time", point.time),
                yStart: .value("P5", point.p5),
                yEnd: .value("P95", point.p95),
                series: .value("Band", "p5p95")
            )
            .foregroundStyle(AmberTheme.amber.opacity(GhostBand.outerOpacity))
            .interpolationMethod(.monotone)
        }

        ForEach(band.points, id: \.time) { point in
            AreaMark(
                x: .value("Time", point.time),
                yStart: .value("P25", point.p25),
                yEnd: .value("P75", point.p75),
                series: .value("Band", "p25p75")
            )
            .foregroundStyle(AmberTheme.amber.opacity(GhostBand.innerOpacity))
            .interpolationMethod(.monotone)
        }

        ForEach(band.points, id: \.time) { point in
            LineMark(
                x: .value("Time", point.time),
                y: .value("Usual", point.median),
                series: .value("Band", "median")
            )
            .foregroundStyle(AmberTheme.amber.opacity(GhostBand.medianOpacity))
            .lineStyle(GhostBand.medianStyle)
            .interpolationMethod(.monotone)
        }

        // The hour this person is least predictable in — a question, not a verdict.
        if let span = band.patternHourSpan, let hour = band.patternHour {
            RectangleMark(
                xStart: .value("From", span.lowerBound),
                xEnd: .value("To", span.upperBound),
                yStart: .value("Bottom", 0),
                yEnd: .value("Top", yMax)
            )
            .foregroundStyle(AmberTheme.surfaceTint)

            RuleMark(x: .value("Pattern hour", span.lowerBound))
                .foregroundStyle(AmberTheme.borderSubtle)
                .lineStyle(GhostBand.dashedStyle)

            RuleMark(x: .value("Pattern hour", span.upperBound))
                .foregroundStyle(AmberTheme.borderSubtle)
                .lineStyle(GhostBand.dashedStyle)
                .annotation(
                    position: .top,
                    alignment: .trailing,
                    // `y: .disabled` draws above the plot, where it is clipped
                    // away (P0 errata).
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    Text(PatternCopy.patternHourLabel(days: hour.days))
                        .font(DOSTypography.micro)
                        .foregroundStyle(AmberTheme.amberDark)
                        .monospacedDigit()
                }
        }

        // Hours where today left the band: a tick on the axis, and one card.
        ForEach(band.outOfBand) { marker in
            RuleMark(
                x: .value("Time", marker.time),
                yStart: .value("Bottom", 0),
                yEnd: .value("Tick", yMax * GhostBand.tickHeight)
            )
            .foregroundStyle(AmberTheme.amber)
            .lineStyle(GhostBand.tickStyle)
        }

        // Every departure gets its dot; only the ones far enough apart to be
        // read get the card (`PatternBandBuilder.cardSpacingHours`).
        ForEach(band.outOfBand) { marker in
            PointMark(
                x: .value("Time", marker.time),
                y: .value("Glucose", marker.todayValue)
            )
            .symbolSize(GhostBand.markerSymbolSize)
            .foregroundStyle(AmberTheme.amberLight)
            .annotation(
                position: .top,
                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
            ) {
                if marker.showsCard {
                    Text(marker.cardText)
                        .font(DOSTypography.micro)
                        .foregroundStyle(AmberTheme.amber)
                        .monospacedDigit()
                        .dosCard(.toast, padding: DOSSpacing.xxs)
                }
            }
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
