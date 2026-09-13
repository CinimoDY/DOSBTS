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
    private enum Config {
        /// The stage lane's tallest cell, as a fraction of the y domain.
        static let stageLaneHeight: Double = 0.06
        /// P2: the prototype's stagger between overlapping ribbon labels.
        static let labelRowHeight: CGFloat = 12
        /// P2: the dashed rule where a live response window will close.
        static let stubStyle: StrokeStyle = .init(lineWidth: 1, dash: [3, 3])
    }

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

        // Only when the real +2 h is ON the chart. `stubEnd` is clamped into
        // the domain, so an unclamped rule would draw at the domain's edge for
        // every live ribbon — "closes in 12 min" next to a `42 MIN` label.
        ForEach(series.mealResponses.filter { closingRuleDate(for: $0, series: series) != nil }) { response in
            RuleMark(x: .value("Closes", closingRuleDate(for: response, series: series) ?? response.windowEnd))
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
            //
            // `.bottom`, not `.top`: the y-fit pulls it to the plot FLOOR, which
            // is the one horizontal strip the trace never occupies (glucose is
            // clamped ≥ 40), and it frees the top band entirely for the ribbon
            // labels instead of stacking a fifth row on them.
            .annotation(
                position: .bottom,
                alignment: .center,
                // `y: .fit(to: .plot)`, not `.chart`: fitting to the chart lets
                // it settle over the hour labels: the PLOT floor is inside the
                // frame the trace lives in, which is where it belongs.
                spacing: 0,
                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .plot))
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
            }
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

    // MARK: - Private

    /// Where a live window will close, but only when that instant is actually
    /// on the chart — otherwise the clamped `stubEnd` sits at the domain edge
    /// and lies about when the window ends.
    private static func closingRuleDate(
        for response: MealResponseDatapoint,
        series: LabChartSeries
    ) -> Date? {
        guard let stub = response.stubEnd, stub < series.domainEnd else { return nil }
        return stub
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
