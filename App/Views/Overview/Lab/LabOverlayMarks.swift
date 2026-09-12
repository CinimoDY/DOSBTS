//
//  LabOverlayMarks.swift
//  DOSBTS
//
//  The one switch every Chart Lab overlay goes through. P0 shipped all seven
//  arms empty; P1/P2/P4/P5 each fill their own arm and nothing else in this
//  file, so the parallel branches never collide. Keep the switch exhaustive —
//  the compiler is what tells a later worker that a new case needs marks.
//
//  P2 (DMNC-1501) fills the four meal arms. Nothing drawn here is dosing
//  advice: every ribbon carries its reading count, the bracket is a pairing and
//  never a ratio, and an excluded window names what was missing rather than
//  blaming the plate.
//

import Charts
import SwiftUI

enum LabOverlayMarks {
    @ChartContentBuilder
    static func marks(for overlay: ChartLabOverlay, series: LabChartSeries, yMax: Double) -> some ChartContent {
        switch overlay {
        case .carbSizedMeals:
            carbSizedMeals(series: series)
        case .mealResponseRibbons:
            mealResponseRibbons(series: series, yMax: yMax)
        case .residualMarks:
            residualMarks(series: series, yMax: yMax)
        case .regimeBands:
            regimeBands(series: series, yMax: yMax)
        case .nightContext:
            noMarks // P1 fills this arm — sleep stages, HR, cross-midnight ribbon.
        case .ghostBand:
            noMarks // P4 fills this arm — the personal 30-day band.
        case .factPins:
            noMarks // P5 fills this arm — fact pins.
        }
    }

    // MARK: - P2 · carb-sized meal dots

    /// The meal itself: a dot ON the curve whose AREA is its carb load, with the
    /// `60g ⟷ 5U` pairing under it when both halves were logged.
    @ChartContentBuilder
    private static func carbSizedMeals(series: LabChartSeries) -> some ChartContent {
        ForEach(series.mealResponses) { response in
            PointMark(
                x: .value("Time", response.mealTime),
                y: .value("Glucose", series.nearestGlucose(at: response.mealTime)?.value ?? 0)
            )
            .symbolSize(ChartLabSizing.mealSymbolSize(carbs: response.carbs))
            // A meal with no carbs recorded still happened — it just cannot say
            // how much, so it draws at the floor size and dimmer.
            .foregroundStyle(EventMarkerType.meal.color.opacity(response.carbs == nil ? 0.35 : 0.6))
            .annotation(
                position: .bottom,
                alignment: .center,
                spacing: 2,
                // Charts pulls a label that would run off the plot back inside,
                // which is what keeps the last meal's bracket out of the axis.
                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
            ) {
                if let bracket = response.bracketLabel {
                    VStack(spacing: 1) {
                        // The prototype's little elbow: this label belongs to
                        // the dot above it, not to the trace it sits on.
                        Rectangle()
                            .fill(AmberTheme.borderStrong)
                            .frame(width: 1, height: 5)
                        Text(bracket)
                            .font(DOSTypography.micro)
                            .foregroundStyle(
                                response.hasPairing ? AmberTheme.amberDark : EventMarkerType.meal.color
                            )
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 2)
                            .background(AmberTheme.dosBlack.opacity(0.6))
                    }
                }
            }
        }
    }

    // MARK: - P2 · two-hour response ribbons

    /// The window after the meal, tinted by the delta tier it produced — or
    /// hatched-dim and tagged when the window is not a fair comparison.
    @ChartContentBuilder
    private static func mealResponseRibbons(series: LabChartSeries, yMax: Double) -> some ChartContent {
        let lanes = MealResponseDatapoint.labelLanes(series.mealResponses)

        ForEach(series.mealResponses) { response in
            RectangleMark(
                xStart: .value("Meal", response.mealTime),
                xEnd: .value("Window end", response.windowEnd),
                yStart: .value("Bottom", 0),
                yEnd: .value("Top", yMax)
            )
            .foregroundStyle(ribbonFill(response))
            // `position: .top` with BOTH axes fitted, never `.overlay`: an
            // overlay annotation is laid out inside the mark's own width, so a
            // label longer than its two-hour ribbon truncates to `+47 · 39 MI…`
            // — and `n` is the part that would vanish.
            .annotation(
                position: .top,
                alignment: .leading,
                spacing: 0,
                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
            ) {
                Text(response.ribbonLabel(glucoseUnit: series.glucoseUnit))
                    .font(DOSTypography.micro)
                    .foregroundStyle(ribbonInk(response))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 2)
                    .background(AmberTheme.dosBlack.opacity(0.75))
                    // Overlapping windows stack their labels instead of
                    // printing on top of each other.
                    .padding(.top, CGFloat(lanes[response.id] ?? 0) * Config.labelRowHeight)
            }
        }

        // The remainder of a window that has not closed yet. Charts cannot
        // stroke a RectangleMark, so the dotted outline of the prototype is a
        // faint fill plus a dashed rule where the window WILL close.
        ForEach(series.mealResponses.filter { $0.stubEnd != nil }) { response in
            RectangleMark(
                xStart: .value("Now", response.windowEnd),
                xEnd: .value("Closes", response.stubEnd ?? response.windowEnd),
                yStart: .value("Bottom", 0),
                yEnd: .value("Top", yMax)
            )
            .foregroundStyle(AmberTheme.amberDark.opacity(0.05))
        }

        ForEach(series.mealResponses.filter { $0.stubEnd != nil }) { response in
            RuleMark(x: .value("Closes", response.stubEnd ?? response.windowEnd))
                .foregroundStyle(AmberTheme.borderStrong)
                .lineStyle(Config.stubStyle)
        }
    }

    // MARK: - P2 · residuals

    /// An excursion with nothing logged against it. A question, never a guess.
    @ChartContentBuilder
    private static func residualMarks(series: LabChartSeries, yMax: Double) -> some ChartContent {
        ForEach(series.residuals) { residual in
            RectangleMark(
                xStart: .value("Start", residual.start),
                xEnd: .value("End", residual.end),
                yStart: .value("Bottom", 0),
                yEnd: .value("Top", yMax)
            )
            .foregroundStyle(AmberTheme.amber.opacity(0.05))
            // A MARK, not a control. Views inside a scrollable Chart's
            // annotations never receive taps — the scroll and selection
            // gestures consume them (proven on the simulator: neither a
            // `Button` nor an `.onTapGesture` here ever fired). The affordance
            // is `LabResidualPromptRow`, a sibling BELOW the chart that claims
            // only its own frame, so nothing in here has to win a gesture.
            .annotation(position: .overlay, alignment: .center) {
                Text(verbatim: "?")
                    .font(DOSTypography.mono(size: 13, weight: .bold))
                    .foregroundStyle(AmberTheme.amber)
                    .frame(width: 22, height: 22)
                    .background(AmberTheme.scrimHeavy)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - P2 · regime bands

    /// A stretch of day a tagged note says was not normal. Derived from the
    /// notes every build; nothing about a regime is stored.
    @ChartContentBuilder
    private static func regimeBands(series: LabChartSeries, yMax: Double) -> some ChartContent {
        ForEach(series.regimes.filter { $0.end >= series.domainStart && $0.start <= series.domainEnd }) { band in
            RectangleMark(
                // An open band runs past the chart; it is clamped so it draws,
                // but the LABEL still names the band's own hours.
                xStart: .value("Start", max(band.start, series.domainStart)),
                xEnd: .value("End", min(band.end, series.domainEnd)),
                yStart: .value("Bottom", 0),
                yEnd: .value("Top", yMax)
            )
            .foregroundStyle(AmberTheme.surfaceTint)
            // Same reason as the ribbon labels: an overlay annotation is
            // clipped to the mark, and a band that starts off-screen would show
            // `ESSED 14→18`.
            .annotation(
                position: .top,
                alignment: .center,
                spacing: 0,
                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
            ) {
                Text(band.label)
                    .font(DOSTypography.micro)
                    .foregroundStyle(AmberTheme.amberLight)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(AmberTheme.scrimHeavy)
                    // Under the exercise strip, which owns the top of the plot.
                    .padding(.top, Config.regimeLabelDrop)
            }
        }
    }

    // MARK: - Private

    private enum Config {
        /// The prototype's stagger between overlapping ribbon labels.
        static let labelRowHeight: CGFloat = 12
        /// How many rows the ribbon labels cycle through before wrapping.
        static let labelRows: CGFloat = 4
        // The plot's top band is shared: ribbon labels take the first four
        // rows, then the regime label. Stacking them explicitly is what stops
        // `STRESSED 14→18` printing over `NO BOLUS`, which is exactly what
        // happened on the first simulator pass.
        static let regimeLabelDrop: CGFloat = labelRowHeight * labelRows + 4
        static let stubStyle: StrokeStyle = .init(lineWidth: 1, dash: [3, 3])
    }

    /// Tier tint for a fair window, dim for an excluded one. The opacity is
    /// PARAMETRIC (it encodes confidence), which is the sanctioned reason to
    /// dim a palette token in a view rather than reach for a fixed tier.
    private static func ribbonFill(_ response: MealResponseDatapoint) -> Color {
        if response.isExcluded { return AmberTheme.amberDark.opacity(0.10) }
        guard let delta = response.summary.delta else { return AmberTheme.amberDark.opacity(0.06) }
        return mealImpactDeltaColor(delta: delta).opacity(response.summary.isLowConfidence ? 0.05 : 0.12)
    }

    private static func ribbonInk(_ response: MealResponseDatapoint) -> Color {
        guard !response.isExcluded, let delta = response.summary.delta else { return AmberTheme.amberDark }
        return mealImpactDeltaColor(delta: delta)
    }

    /// "This overlay draws nothing yet." Charts exposes no public
    /// `EmptyChartContent`, so an empty `ForEach` is the cheapest legal no-op.
    private static var noMarks: some ChartContent {
        ForEach([Int](), id: \.self) { _ in
            RuleMark(y: .value("", 0))
        }
    }
}
