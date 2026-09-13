//
//  LabSweepView.swift
//  DOSBTS
//
//  LAB: SWEEP (DMNC-1503, Chart Lab P3) — the event-locked response overlay.
//
//  Every meal in the window is one sweep, aligned at t=0 on an x axis of minutes
//  since the meal and a y axis of change from the −15-minute baseline. Older
//  sweeps fade, confounded ones are dashed, the clean ones raise a median and a
//  p25–p75 wash, and today's unfinished meal is drawn on top with its twins named
//  underneath.
//
//  This is its OWN `Chart` — numeric on both axes — not `LabChartView` (which is a
//  scrollable Date/glucose chart). It shares the lab's chrome (`LabLegendRow`,
//  `LabFooter`) and the report-row chip styling, nothing else.
//
//  The card is descriptive. It says what happened to this person after this meal
//  and what usually happens after meals like it. It never says what to do.
//

import Charts
import SwiftUI

struct LabSweepView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore

    var body: some View {
        VStack(spacing: 0) {
            captionRow

            GeometryReader { geo in
                plotArea(height: LabChartMath.chartHeight(
                    available: geo.size.height,
                    minimum: LabSweepConfig.minHeight,
                    maximum: LabSweepConfig.maxHeight
                ))
            }
            .frame(minHeight: LabSweepConfig.minHeight)

            lapsCard

            filterChips

            LabLegendRow(items: [
                LabLegendItem(glyph: "—", label: "OLDER · FAINTER", color: AmberTheme.textFaint),
                LabLegendItem(glyph: "╌", label: "CONFOUNDED", color: AmberTheme.amberDark),
                LabLegendItem(glyph: "▬", label: "P25–P75", color: AmberTheme.amber)
            ])

            LabFooter()
        }
        // No load dispatched from here: `labSweepMiddleware` owns the trigger set
        // (tab entry, scene activation, chips, log edits, live readings). A second
        // trigger here raced the toolbar's day-window normalise and could flash a
        // 3-day set under a 30d chip.
        .onAppear { rebuild() }
        .onChange(of: inputs) { rebuild() }
    }

    // MARK: Private

    /// Local, not Redux: a chip choice is view state that should not survive a tab
    /// switch, and nothing outside this screen reads it.
    @State private var bucket: CarbBucket?
    @State private var cleanOnly = false
    @State private var twinsExpanded = false
    @State private var model = SweepRenderModel.empty

    // MARK: Inputs

    /// The gate on rebuilding. `loadedAt` identifies a load without walking every
    /// sweep's points on each store publish (`MealSweep`'s `Equatable` would).
    private struct SweepInputs: Equatable {
        let loadedAt: Date?
        let days: Int?
        let bucket: CarbBucket?
        let cleanOnly: Bool
        let glucoseUnit: GlucoseUnit
    }

    private var inputs: SweepInputs {
        SweepInputs(
            loadedAt: currentEvidence?.loadedAt,
            days: currentEvidence?.days,
            bucket: bucket,
            cleanOnly: cleanOnly,
            glucoseUnit: store.state.glucoseUnit
        )
    }

    private var glucoseUnit: GlucoseUnit { store.state.glucoseUnit }

    /// The evidence in hand, but ONLY if it answers the window the chips are
    /// currently showing.
    ///
    /// `Store.dispatch` never cancels an in-flight publisher, so a slower 90 d read
    /// can land after a faster 7 d one; and on a chip change the previous window's
    /// evidence is still in state. Rendering it under the new chip would caption
    /// someone else's N. Same rule `mealHistoryResults` follows (CLAUDE.md → food
    /// history search): the payload carries the question it answers.
    private var currentEvidence: LabSweepEvidence? {
        guard let evidence = store.state.labSweeps,
              evidence.days == LabSweepStore.effectiveDays(store.state.statisticsDays)
        else { return nil }
        return evidence
    }

    /// Blank while a load is in flight — `N=0 SWEEPS` next to a loading pulse reads
    /// as a finding, and it is not one.
    private var countCaption: String {
        guard currentEvidence != nil else { return "" }
        return SweepLapsFormatter.countCaption(total: model.totalCount, clean: model.cleanCount)
    }

    // MARK: Caption

    private var captionRow: some View {
        HStack {
            Text(countCaption)
                .foregroundStyle(AmberTheme.amber)
            Spacer()
            Text(SweepLapsFormatter.axisCaption(glucoseUnit: glucoseUnit))
                .foregroundStyle(AmberTheme.amberLight)
        }
        .font(DOSTypography.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, DOSSpacing.sm)
        .padding(.bottom, DOSSpacing.xxs)
    }

    // MARK: Plot area

    @ViewBuilder
    private func plotArea(height: CGFloat) -> some View {
        if currentEvidence == nil {
            VStack {
                Spacer()
                FiguresLoadingView.inline
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
        } else if model.lines.isEmpty, model.today == nil {
            emptyState
                .frame(maxWidth: .infinity)
                .frame(height: height)
        } else {
            chart
                .frame(height: height)
                .padding(.horizontal, DOSSpacing.xs)
                .accessibilityLabel("Meal sweep chart")
                .accessibilityValue(model.lapsLine)
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: DOSSpacing.xxs) {
                Text(emptyHeadline)
                    .font(DOSTypography.bodySmall)
                    .foregroundStyle(AmberTheme.cgaCyan)
                Text("every logged meal becomes one sweep, aligned at t=0 · n=\(model.unfilteredCount)")
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.amberDark)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dosCard(.info)
            .padding(.horizontal, DOSSpacing.sm)
            Spacer()
        }
    }

    private var emptyHeadline: String {
        let days = currentEvidence?.days ?? LabSweepStore.effectiveDays(store.state.statisticsDays)
        if model.unfilteredCount > 0 {
            return "NO SWEEPS MATCH THIS FILTER · n=0"
        }
        return "NO MEALS IN THE LAST \(days) DAYS · n=0"
    }

    // MARK: Chart

    private var chart: some View {
        Chart {
            // MARK: t=0 — the event every sweep is locked to
            RuleMark(x: .value("MIN", 0))
                .lineStyle(LabSweepConfig.zeroRuleStyle)
                .foregroundStyle(AmberTheme.amberLight)

            // MARK: p25–p75 wash (clean sweeps only)
            ForEach(model.band) { bin in
                AreaMark(
                    x: .value("MIN", bin.minute),
                    yStart: .value("P25", bin.low),
                    yEnd: .value("P75", bin.high)
                )
                .foregroundStyle(AmberTheme.amber.opacity(LabSweepConfig.bandOpacity))
                .interpolationMethod(.monotone)
            }

            // MARK: The sweeps, oldest first so the recent ones paint on top
            ForEach(model.lines) { line in
                ForEach(line.points) { point in
                    LineMark(
                        x: .value("MIN", point.minute),
                        y: .value("DELTA", point.value),
                        series: .value("SWEEP", line.id.uuidString)
                    )
                    .foregroundStyle(line.color)
                    .lineStyle(StrokeStyle(
                        lineWidth: LabSweepConfig.sweepLineWidth,
                        dash: line.dashed ? LabSweepConfig.confoundedDash : []
                    ))
                    .interpolationMethod(.monotone)
                }
            }

            // MARK: The median of the clean sweeps
            ForEach(model.median) { point in
                LineMark(
                    x: .value("MIN", point.minute),
                    y: .value("DELTA", point.value),
                    series: .value("SWEEP", "median")
                )
                .foregroundStyle(AmberTheme.amber)
                .lineStyle(StrokeStyle(lineWidth: LabSweepConfig.medianLineWidth, lineCap: .round))
                .interpolationMethod(.monotone)
            }

            if let label = model.medianLabel {
                PointMark(
                    x: .value("MIN", label.minute),
                    y: .value("DELTA", label.value)
                )
                .symbolSize(0)
                .annotation(
                    position: .top,
                    alignment: .center,
                    spacing: 2,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    Text(model.medianCaption)
                        .font(DOSTypography.micro)
                        .foregroundStyle(AmberTheme.amber)
                        .padding(.horizontal, DOSSpacing.xxs)
                        .background(AmberTheme.dosBlack)
                }
            }

            // MARK: Today, still unfolding
            if let today = model.today {
                ForEach(today.points) { point in
                    LineMark(
                        x: .value("MIN", point.minute),
                        y: .value("DELTA", point.value),
                        series: .value("SWEEP", "today")
                    )
                    .foregroundStyle(AmberTheme.amberLight)
                    .lineStyle(StrokeStyle(lineWidth: LabSweepConfig.todayLineWidth, lineCap: .round))
                    .interpolationMethod(.monotone)
                }
            }

            if let end = model.todayEnd {
                PointMark(
                    x: .value("MIN", end.minute),
                    y: .value("DELTA", end.value)
                )
                .symbolSize(LabSweepConfig.todaySymbolSize)
                .foregroundStyle(AmberTheme.amberLight)
                .annotation(
                    position: .topTrailing,
                    alignment: .leading,
                    spacing: 2,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    Text(model.todayCaption)
                        .font(DOSTypography.micro)
                        .foregroundStyle(AmberTheme.amberLight)
                        .padding(.horizontal, DOSSpacing.xxs)
                        .background(AmberTheme.dosBlack)
                }
            }
        }
        // Both scales are explicit and numeric — the sweep axis is minutes since the
        // meal, never a date, and the y axis is a delta that must include zero.
        .chartXScale(domain: SweepStatistics.windowStartMinutes...SweepStatistics.windowEndMinutes)
        .chartYScale(domain: model.yDomain)
        .chartXAxis {
            AxisMarks(values: model.xTicks) { value in
                AxisGridLine()
                    .foregroundStyle(AmberTheme.borderSubtle)
                // `.disabled`: the +4h label sits under the trailing y-axis gutter
                // and `.automatic` silently DROPS it — the axis then stops saying
                // where the window ends.
                AxisValueLabel(
                    anchor: value.index == model.xTicks.count - 1 ? .topTrailing : .top,
                    collisionResolution: .disabled
                ) {
                    Text(xLabel(value.as(Int.self)))
                        .font(DOSTypography.micro)
                        .foregroundStyle(AmberTheme.amber)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: model.yTicks) { value in
                AxisGridLine()
                    .foregroundStyle(AmberTheme.borderSubtle)
                AxisValueLabel {
                    Text(yLabel(value.index))
                        .font(DOSTypography.micro)
                        .foregroundStyle(AmberTheme.amber)
                }
            }
        }
    }

    private func xLabel(_ minute: Int?) -> String {
        guard let minute else { return "" }
        if minute == 0 { return "t=0" }
        if minute % 60 == 0 { return "+\(minute / 60)h" }
        return "+\(minute)m"
    }

    private func yLabel(_ index: Int) -> String {
        guard index >= 0, index < model.yTicksMgdl.count else { return "" }
        return SweepLapsFormatter.signedDelta(model.yTicksMgdl[index], glucoseUnit: glucoseUnit)
    }

    // MARK: LAPS card

    @ViewBuilder
    private var lapsCard: some View {
        if model.subject != nil {
            VStack(alignment: .leading, spacing: DOSSpacing.xxs) {
                // The WHOLE header is the control, not the 13 pt `WHY THESE ›` label:
                // a full-width 44 pt target, and it costs the card ~24 pt of height
                // instead of the 44 pt a `minHeight` on the label alone did — which
                // was enough to push the safety footer off the bottom of the page.
                Button {
                    withAnimation(AnimationTokens.snappy) { twinsExpanded.toggle() }
                } label: {
                    HStack(spacing: DOSSpacing.xs) {
                        Text(model.lapsTitle)
                            .font(DOSTypography.label)
                            .foregroundStyle(AmberTheme.amberLight)
                            .lineLimit(1)

                        Spacer()

                        if !model.twins.isEmpty {
                            Text(twinsExpanded ? "HIDE ‹" : "WHY THESE ›")
                                .font(DOSTypography.label)
                                .foregroundStyle(AmberTheme.amberDark)
                        }
                    }
                    .frame(minHeight: LabSweepConfig.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.twins.isEmpty)
                .accessibilityLabel(twinsExpanded ? "Hide the twin meals" : "Show the twin meals")

                Text(model.lapsLine)
                    .font(DOSTypography.label)
                    .foregroundStyle(AmberTheme.amber)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if twinsExpanded {
                    // Bounded and scrollable: five expanded rows pushed the page
                    // past its height and sank the persistent bottom bar
                    // (docs/solutions/ui-bugs/swiftui-vstack-overflow-sinks-safeareainset).
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(model.twins) { twin in
                                Text(SweepLapsFormatter.twinRow(twin, glucoseUnit: glucoseUnit))
                                    .font(DOSTypography.micro)
                                    .foregroundStyle(AmberTheme.textFaint)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: LabSweepConfig.twinListMaxHeight)
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dosCard(.stat)
            .padding(.horizontal, DOSSpacing.sm)
            .padding(.top, DOSSpacing.xs)
        }
    }

    // MARK: Chips

    /// Meal size, then the clean toggle — both are filters on the same cloud, and
    /// giving each its own 44 pt row did not fit under the chart. The `●`/`○` prefix
    /// is what says the last chip is a toggle rather than a sixth size.
    private var filterChips: some View {
        HStack(spacing: DOSSpacing.sm) {
            LabChipButton(label: "ALL", isSelected: bucket == nil) {
                withAnimation(AnimationTokens.snappy) { bucket = nil }
            }
            ForEach(CarbBucket.selectable, id: \.self) { candidate in
                LabChipButton(label: candidate.label, isSelected: bucket == candidate) {
                    withAnimation(AnimationTokens.snappy) { bucket = candidate }
                }
            }
            LabChipButton(
                label: cleanOnly ? "● CLEAN" : "○ CLEAN",
                isSelected: cleanOnly,
                accessibilityLabel: "Clean sweeps only"
            ) {
                withAnimation(AnimationTokens.snappy) { cleanOnly.toggle() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DOSSpacing.xs)
    }

    // MARK: Rebuild

    /// Filtering + unit conversion only — `SweepStatistics.build` already ran off
    /// the main thread in `labSweepMiddleware`, so there is nothing heavy left to
    /// hop a queue for.
    private func rebuild() {
        guard let evidence = currentEvidence else {
            model = .empty
            return
        }
        model = SweepRenderModel.build(
            evidence: evidence,
            bucket: bucket,
            cleanOnly: cleanOnly,
            glucoseUnit: glucoseUnit,
            now: Date()
        )
    }
}

// MARK: - LabChipButton

/// The report row's chip treatment (`ChartToolbar.swift`'s `ChartTabButton`), which
/// is `private` there. Restated locally rather than widening a shared file five
/// parallel branches are also editing.
private struct LabChipButton: View {
    let label: String
    let isSelected: Bool
    var accessibilityLabel: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(isSelected ? DOSTypography.bodySmall.weight(.bold) : DOSTypography.bodySmall)
                .foregroundStyle(isSelected ? AmberTheme.amber : AmberTheme.amberDark)
                .lineLimit(1)
                // Six chips on a 393 pt phone leave no slack; scale rather than
                // truncate, so a narrower device loses size, not meaning.
                .minimumScaleFactor(0.7)
                // `sm`, matching P0's `ChartTabButton`: `xs` made the chip ~34 pt tall.
                .padding(.vertical, DOSSpacing.sm)
                .padding(.horizontal, DOSSpacing.xs)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(AmberTheme.amber)
                        .frame(height: 2)
                        .opacity(isSelected ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? label)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Render model

/// One plotted sample, already in the display unit.
private struct SweepPlotPoint: Identifiable {
    let id: Int
    let minute: Int
    let value: Double
}

/// One plotted sweep.
private struct SweepLine: Identifiable {
    let id: UUID
    let points: [SweepPlotPoint]
    let color: Color
    let dashed: Bool
}

/// One plotted band sample.
private struct SweepBandPoint: Identifiable {
    let id: Int
    let minute: Int
    let low: Double
    let high: Double
}

/// Everything the chart and the LAPS card draw, resolved once per input change.
private struct SweepRenderModel {
    var lines: [SweepLine] = []
    var band: [SweepBandPoint] = []
    var median: [SweepPlotPoint] = []
    var medianLabel: SweepPlotPoint?
    var medianCaption = ""
    var today: SweepLine?
    var todayEnd: SweepPlotPoint?
    var todayCaption = ""
    var totalCount = 0
    var cleanCount = 0
    var unfilteredCount = 0
    var subject: MealSweep?
    var twins: [MealSweep] = []
    var lapsTitle = ""
    var lapsLine = ""
    var yTicksMgdl: [Int] = []
    var yTicks: [Double] = []
    var xTicks: [Int] = [0, 60, 120, 180, 240]
    var yDomain: ClosedRange<Double> = -20...100

    static let empty = SweepRenderModel()

    static func build(
        evidence: LabSweepEvidence,
        bucket: CarbBucket?,
        cleanOnly: Bool,
        glucoseUnit: GlucoseUnit,
        now: Date
    ) -> SweepRenderModel {
        var model = SweepRenderModel()

        let filtered = SweepStatistics.filter(evidence.sweeps, bucket: bucket, cleanOnly: cleanOnly)
        model.unfilteredCount = evidence.sweeps.count
        model.totalCount = filtered.count
        // `bins` never counts an in-progress sweep (the live trace is what the band
        // is being compared against), so neither may the caption: with 2 completed
        // and 1 live clean sweep the wash drew from n=2 while the caption said
        // `3 CLEAN`.
        model.cleanCount = filtered.filter { $0.isClean && !$0.isInProgress }.count

        let drawn = SweepStatistics.capped(filtered)
        let inProgress = drawn.filter(\.isInProgress)
        let live = inProgress.first
        // A second meal logged inside the first one's 2 h window is in progress too.
        // It is confounded (both stack each other), so it belongs in the cloud with
        // the rest — drawn through the normal tiers rather than counted in `N=` and
        // then silently omitted.
        let completed = (drawn.filter { !$0.isInProgress } + inProgress.dropFirst())
            .sorted { $0.mealTime > $1.mealTime }

        let bins = SweepStatistics.bins(filtered, cleanOnly: true)
        let hasBand = model.cleanCount >= SweepStatistics.minSweepsForBand

        // ONE y computation, fed by every plotted series — the P0 errata's rule.
        var plotted: [Int] = completed.flatMap { $0.points.map(\.delta) }
        plotted += live?.points.map(\.delta) ?? []
        if hasBand {
            plotted += bins.flatMap { [$0.p25, $0.p75, $0.p50] }
        }
        let domainMgdl = SweepChartMath.yDomainMgdl(deltas: plotted)
        model.yTicksMgdl = SweepChartMath.yTicksMgdl(domain: domainMgdl)
        model.yTicks = model.yTicksMgdl.map { convert($0, glucoseUnit) }
        model.yDomain = convert(domainMgdl.lowerBound, glucoseUnit)...convert(domainMgdl.upperBound, glucoseUnit)

        // Oldest first: the recent, brighter sweeps then paint over the faint ones.
        model.lines = completed.reversed().map { sweep in
            SweepLine(
                id: sweep.id,
                points: plotPoints(sweep.points, glucoseUnit),
                color: tierColor(ageDays: sweep.ageDays, count: completed.count),
                dashed: !sweep.isClean
            )
        }

        if hasBand {
            model.band = bins.map { bin in
                SweepBandPoint(
                    id: bin.minute,
                    minute: bin.minute,
                    low: convert(bin.p25, glucoseUnit),
                    high: convert(bin.p75, glucoseUnit)
                )
            }
            model.median = bins.map { bin in
                SweepPlotPoint(id: bin.minute, minute: bin.minute, value: convert(bin.p50, glucoseUnit))
            }
            model.medianLabel = model.median.min {
                abs($0.minute - LabSweepConfig.medianLabelMinute) < abs($1.minute - LabSweepConfig.medianLabelMinute)
            }
            model.medianCaption = "MEDIAN · \(model.cleanCount) CLEAN"
        }

        if let live {
            let points = plotPoints(live.points, glucoseUnit)
            model.today = SweepLine(id: live.id, points: points, color: AmberTheme.amberLight, dashed: false)
            model.todayEnd = points.last
            if let delta = live.delta {
                model.todayCaption = "TODAY \(SweepLapsFormatter.signedDelta(delta, glucoseUnit: glucoseUnit))"
            } else {
                model.todayCaption = "TODAY"
            }
        }

        // The LAPS subject is chosen from the UNFILTERED set: a chip is a lens on
        // the cloud, not a reason to stop telling the user about their last meal.
        if let subject = SweepStatistics.lapsSubject(evidence.sweeps) {
            model.subject = subject
            model.twins = TwinFinder.twins(for: subject, in: evidence.sweeps)
            model.lapsTitle = SweepLapsFormatter.title(for: subject)
            model.lapsLine = SweepLapsFormatter.line(
                subject: subject,
                twins: TwinFinder.summary(of: model.twins),
                glucoseUnit: glucoseUnit,
                now: now
            )
        }

        return model
    }

    // MARK: Private

    private static func plotPoints(_ points: [SweepPoint], _ glucoseUnit: GlucoseUnit) -> [SweepPlotPoint] {
        points.map { SweepPlotPoint(id: $0.minute, minute: $0.minute, value: convert($0.delta, glucoseUnit)) }
    }

    /// Deltas are pure differences, so the mg/dL→mmol/L rate applies with no offset.
    private static func convert(_ mgdl: Int, _ glucoseUnit: GlucoseUnit) -> Double {
        glucoseUnit == .mmolL ? mgdl.toMmolL() : mgdl.toDouble()
    }

    /// The age fade the legend promises: `— OLDER · FAINTER`, thinned as a whole
    /// once the cloud is dense enough to swallow the median and the wash.
    private static func tierColor(ageDays: Int, count: Int) -> Color {
        if ageDays <= LabSweepConfig.recentAgeDays {
            return AmberTheme.amber.opacity(
                SweepChartMath.densityOpacity(count: count, base: LabSweepConfig.recentOpacity)
            )
        }
        let fade = SweepChartMath.densityOpacity(count: count, base: 1)
        if ageDays <= LabSweepConfig.middleAgeDays {
            return AmberTheme.amberDark.opacity(fade)
        }
        return AmberTheme.textFaint.opacity(fade)
    }
}

/// Shared between the view and its render model.
private enum LabSweepConfig {
    /// The chart's floor. It only bites when the LAPS card is expanded — and it has
    /// to be low enough to absorb that, or the page overflows and the persistent
    /// bottom bar sinks under the tab bar (the 44 pt tap targets cost ~40 pt of the
    /// slack that used to cover it).
    static let minHeight: CGFloat = 140
    static let maxHeight: CGFloat = 270
    /// The sweeps themselves — hairlines, so 120 of them still read as a cloud.
    static let sweepLineWidth: CGFloat = 1.2
    static let medianLineWidth: CGFloat = 2.5
    static let todayLineWidth: CGFloat = 3
    static let confoundedDash: [CGFloat] = [2, 3]
    static let zeroRuleStyle: StrokeStyle = .init(lineWidth: 1, dash: [3, 3])
    static let todaySymbolSize: CGFloat = 70
    /// Where the `MEDIAN · n CLEAN` label sits, in minutes since the meal.
    static let medianLabelMinute = 150
    /// Sweeps newer than this keep the bright tier; then amberDark, then textFaint.
    static let recentAgeDays = 10
    static let middleAgeDays = 20
    static let bandOpacity: Double = 0.14
    /// The expanded twin list's ceiling — three rows, the rest scroll. Sized in whole
    /// rows so the list never clips one in half (which reads as broken, not scrollable).
    static let twinListMaxHeight: CGFloat = 44
    /// The smallest thing a finger is asked to hit.
    static let minTapTarget: CGFloat = 44
    static let recentOpacity: Double = 0.55
}
