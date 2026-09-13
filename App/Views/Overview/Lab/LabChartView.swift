//
//  LabChartView.swift
//  DOSBTS
//
//  Chart Lab (DMNC-1500) native chart platform. Mirrors the shipping GLUCOSE
//  chart's marks, but scrolls the Health way — a native scrollable Chart with an
//  explicit domain and hour snapping — and adds the instrument cursors: a scrub
//  cursor that persists after release, an A→B range with a fixed readout strip,
//  a detached-FOLLOW state with a `◂ N NEW` nub, and detent haptics.
//
//  Deliberately NOT a copy of ChartView: no marker lane, no content-width zoom,
//  no prediction line, no raw-trace toggle. The shipping chart body is untouched.
//
//  The interaction logic lives in `LabCursorState` / `LabChartMath` / `LabDetent`
//  so it is pinned by tests rather than only by eye; this file forwards events in
//  and renders what comes back.
//
//  Nothing in the lab is dosing advice.
//

import Charts
import SwiftUI

// MARK: - LabChartView

struct LabChartView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore

    /// Mark-sets this lab tab layers on. P0 ships every arm empty.
    let overlays: Set<ChartLabOverlay>

    /// Hoisted so the tab's legend can say what the nub says.
    @Binding var followStatus: LabFollowStatus

    /// Where the computed facts go. Optional and defaulted: a tab that draws no
    /// pins (and every sibling lab tab) constructs this view unchanged.
    var factsBinding: Binding<LabFactsSnapshot>?

    /// Set by a tapped fact card: scroll to the anchor and drop a cursor on it.
    var focusRequest: LabFocusRequest?
    /// Optional extra chip on the unit row (P4's `▒ YOUR 30-DAY BAND`).
    /// Defaults to nil, so every existing call site is unchanged.
    var unitRowLabel: String? = nil

    /// Fires when the sticky scrub cursor moves or clears.
    ///
    /// P4's "hold an hour" drill reads THIS rather than adding a long-press of
    /// its own: press-and-hold is already the scrub gesture (P0's arbitration),
    /// and a second long-press on the same plot would fight it. Defaults to nil.
    var onCursorChange: ((Date?) -> Void)? = nil
    /// The whole-system window path (DMNC-1506). When set, the chart draws THIS
    /// snapshot over its own interval instead of the store's day window, and the
    /// visible domain is the whole window — a night is a thing you look at, not
    /// a thing you scroll through.
    var windowInputs: LabChartInputs? = nil

    var body: some View {
        VStack(spacing: 0) {
            LabDayPager(windowDate: isWindowed ? (store.state.selectedDate ?? Date()) : nil)

            unitRow

            GeometryReader { geo in
                plotArea(height: LabChartMath.chartHeight(
                    available: geo.size.height,
                    minimum: Config.minHeight,
                    maximum: Config.maxHeight
                ))
                .onAppear { plotWidth = geo.size.width }
                .onChange(of: geo.size.width) { plotWidth = geo.size.width }
            }
            // The chart can compress, but never past its floor — otherwise a
            // short available height (treatment banner mounted) eats into the
            // readout strip instead (swiftui-vstack-overflow-sinks-safeareainset).
            .frame(minHeight: Config.minHeight)

            LabReadoutStrip(
                series: series,
                cursor: cursors.cursor,
                range: cursors.range,
                glucoseUnit: store.state.glucoseUnit,
                pinnedHeight: Config.readoutHeight,
                onClear: { cursors.clear() }
            )
            .padding(.horizontal, DOSSpacing.sm)
            .padding(.top, DOSSpacing.xs)
        }
        .onAppear { rebuild() }
        .onChange(of: inputs) { rebuild() }
        .onChange(of: store.state.chartZoomLevel) { reanchorAfterZoom() }
        .onChange(of: focusRequest) { applyFocus() }
        .onChange(of: store.state.selectedDate) {
            // Another day's numbers under a cursor the user placed on this one
            // would read as `n=0 · G —` with nothing visible to explain it.
            cursors.clear()
            lastDetentKey = nil
            followStatus = .following
        }
    }

    // MARK: Private

    private enum Config {
        /// Shipping chart height (250) plus the 60 pt marker-lane budget this
        /// chart does not spend.
        static let maxHeight: CGFloat = 310
        static let minHeight: CGFloat = 140
        /// PINNED — the readout must never change height between its states
        /// (branch-height learning: swiftui-viewbuilder-branch-height-mismatch).
        static let readoutHeight: CGFloat = 64
        static let selectionSymbolSize: CGFloat = 100
        static let bloodSymbolSize: CGFloat = 20
        static let heartRateSymbolSize: CGFloat = 30
        static let smoothLineStyle: StrokeStyle = .init(lineWidth: 3.5, lineCap: .round)
        static let ruleStyle: StrokeStyle = .init(lineWidth: 1, dash: [2])
        static let cursorStyle: StrokeStyle = .init(lineWidth: 1, dash: [3, 3])
        static let axisStyle: StrokeStyle = .init(lineWidth: 0.3, dash: [2, 3])
        static let tickStyle: StrokeStyle = .init(lineWidth: 4)
        static let visibleHoursFallback = 3
        /// A cursor within this of an event is "on" it, for the detent tick.
        static let detentWindow: TimeInterval = 2 * 60
        /// Two presses closer together than this ON SCREEN are a re-scrub, not
        /// an A→B measurement.
        static let minRangePoints: CGFloat = 12
        /// Follow is "on" while the leading edge is within a minute of the end.
        static let followSlack: TimeInterval = 60
        /// Shorter than this, with no movement, is a tap (clear) — not a scrub.
        static let tapMaxDuration: TimeInterval = 0.35
        static let tapMaxDistance: CGFloat = 10
        static let plotSideInset: CGFloat = 10
        static let windowedPlotSideInset: CGFloat = 22
    }

    @State private var series: LabChartSeries = .empty
    /// `chartXSelection(value:)` — non-nil while the finger is down, nil on release.
    @State private var liveSelection: Date? = nil
    /// What actually renders: survives the release.
    @State private var cursors = LabCursorState()

    @State private var scrollPosition: Date = Date()
    /// The newest reading time at the moment the chart was last caught up.
    @State private var lastSeenReadingTime: Date? = nil
    @State private var lastDetentKey: String? = nil
    /// When the current press began, so a tap can be told from a scrub.
    @State private var pressStartedAt: Date? = nil
    @State private var plotWidth: CGFloat = 0

    /// `static` so rebuilds serialise on ONE queue: a `let` on a `View` struct
    /// allocates a fresh queue for every instance SwiftUI makes.
    private static let calculationQueue = DispatchQueue(label: "dosbts.lab-chart-calculation", qos: .utility)

    // MARK: Layout

    private var unitRow: some View {
        HStack(spacing: DOSSpacing.xs) {
            Spacer()
            if let unitRowLabel {
                Text(unitRowLabel)
                    .font(DOSTypography.mono(size: 9, weight: .medium))
                    .foregroundStyle(AmberTheme.amberDark)
            }
            Text(store.state.glucoseUnit.localizedDescription)
                .font(DOSTypography.mono(size: 9, weight: .medium))
                .foregroundStyle(AmberTheme.amberMuted)
        }
        .padding(.horizontal, DOSSpacing.xs)
        .padding(.bottom, DOSSpacing.xxs)
    }

    @ViewBuilder
    private func plotArea(height: CGFloat) -> some View {
        if series.domainStart >= series.domainEnd {
            // A day with one reading (or none at all) has no domain to plot. A
            // loading pulse here would spin forever.
            emptyState
                .frame(maxWidth: .infinity)
                .frame(height: height)
        } else if series.isEmpty {
            // A WINDOWED chart knows its domain up front, so "no rows" is a
            // fact about that window, not a load still in flight — a pulse here
            // would spin forever, and (worse) the day pager above it would be
            // the thing that vanished, stranding the user on the empty night
            // with no way back.
            if isWindowed {
                emptyState
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            } else {
                VStack {
                    Spacer()
                    FiguresLoadingView.inline
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: height)
            }
        } else {
            chart
                .frame(height: height)
                .overlay(alignment: .topTrailing) {
                    if followStatus.unseen > 0 {
                        followNub
                    }
                }
                .accessibilityLabel("Lab chart")
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: DOSSpacing.xxs) {
                Text("NO READINGS TO PLOT")
                    .font(DOSTypography.bodySmall)
                    .foregroundStyle(AmberTheme.cgaCyan)
                Text(emptyCaption)
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.amberDark)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dosCard(.info)
            .padding(.horizontal, DOSSpacing.sm)
            Spacer()
        }
    }

    /// A windowed chart names the window it found nothing in — that is the
    /// informative part. A day chart says what a day needs.
    private var emptyCaption: String {
        if let window = windowInputs?.domainOverride {
            return "n=\(series.readingCount) · \(window.start.toLocalTime()) → \(window.end.toLocalTime())"
        }
        return "n=\(series.readingCount) · a day needs two readings before it has a shape"
    }

    // MARK: Chart

    private var chart: some View {
        Chart {
            // MARK: In-range band
            RectangleMark(
                yStart: .value("Low", alarmLow),
                yEnd: .value("High", alarmHigh)
            )
            .foregroundStyle(AmberTheme.cgaGreen.opacity(0.08))

            // MARK: Lab overlays (under-layer; P1/P2/P4/P5 fill their own arm)
            ForEach(sortedOverlays, id: \.self) { overlay in
                LabOverlayMarks.marks(for: overlay, series: series, yMax: yMax)
            }

            // MARK: Limit rules
            RuleMark(y: .value("Lower limit", alarmLow))
                .foregroundStyle(AmberTheme.cgaRed)
                .lineStyle(Config.ruleStyle)

            RuleMark(y: .value("Upper limit", alarmHigh))
                .foregroundStyle(AmberTheme.cgaRed)
                .lineStyle(Config.ruleStyle)

            // MARK: Glucose trace
            ForEach(series.glucoseSegments) { segment in
                ForEach(segment.points) { point in
                    LineMark(
                        x: .value("Time", point.time),
                        y: .value("Glucose", point.value),
                        series: .value("Series", segment.id)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(segment.color)
                    .lineStyle(Config.smoothLineStyle)
                }
            }

            // MARK: Manual blood glucose
            ForEach(series.bloodGlucose) { value in
                PointMark(
                    x: .value("Time", value.time),
                    y: .value("Glucose", value.value)
                )
                .symbolSize(Config.bloodSymbolSize)
                .foregroundStyle(AmberTheme.cgaRed)
            }

            // MARK: Basal bars
            ForEach(series.insulin.filter { $0.type == .basal }) { value in
                RectangleMark(
                    xStart: .value("Starts", value.starts),
                    xEnd: .value("Ends", value.ends),
                    yStart: .value("Units", 0),
                    yEnd: .value("Units", value.value.map(from: 0...20, to: 0...alarmLow))
                )
                .opacity(0.25)
                .annotation(position: .overlay, alignment: .bottom) {
                    Text(value.value.asInsulin())
                        .foregroundStyle(AmberTheme.amberDark)
                        .padding(.horizontal, 2.5)
                        .background(AmberTheme.dosBlack.opacity(0.5))
                        .bold()
                        .font(DOSTypography.caption)
                }
                .foregroundStyle(AmberTheme.amberDark)
            }

            // MARK: IOB decay curve
            if !series.iob.isEmpty {
                let iobCeiling = max(series.iob.map(\.total).max() ?? 1.0, 1.0)

                if store.state.showSplitIOB {
                    // `series:` is load-bearing — without it the two ForEach
                    // loops auto-group into one stack and only one renders
                    // (ChartView.swift:286-289).
                    ForEach(Array(series.iob.enumerated()), id: \.offset) { _, point in
                        AreaMark(
                            x: .value("Time", point.date),
                            yStart: .value("Bottom", 0),
                            yEnd: .value("IOB", point.corrBasal.map(from: 0...iobCeiling, to: 0...alarmLow)),
                            series: .value("IOB Layer", "Basal")
                        )
                        .foregroundStyle(AmberTheme.iobBasal.opacity(0.85))
                        .interpolationMethod(.monotone)
                    }

                    ForEach(Array(series.iob.enumerated()), id: \.offset) { _, point in
                        AreaMark(
                            x: .value("Time", point.date),
                            yStart: .value("Bottom", point.corrBasal.map(from: 0...iobCeiling, to: 0...alarmLow)),
                            yEnd: .value("IOB", point.total.map(from: 0...iobCeiling, to: 0...alarmLow)),
                            series: .value("IOB Layer", "Bolus")
                        )
                        .foregroundStyle(AmberTheme.iobBolus.opacity(0.7))
                        .interpolationMethod(.monotone)
                    }
                } else {
                    ForEach(Array(series.iob.enumerated()), id: \.offset) { _, point in
                        AreaMark(
                            x: .value("Time", point.date),
                            y: .value("IOB", point.total.map(from: 0...iobCeiling, to: 0...alarmLow))
                        )
                        .foregroundStyle(AmberTheme.iobBolus.opacity(0.4))
                        .interpolationMethod(.monotone)
                    }
                }
            }

            // MARK: Exercise strip
            ForEach(series.exercise) { exercise in
                RectangleMark(
                    xStart: .value("Start", exercise.startTime),
                    xEnd: .value("End", exercise.endTime),
                    yStart: .value("Bottom", yMax),
                    yEnd: .value("Top", yMax * 0.95)
                )
                .foregroundStyle(AmberTheme.cgaCyan.opacity(0.3))
            }

            // MARK: Heart rate
            // Gated by the SERIES, not the setting, so the night window can
            // force it on without drawing a second line from the overlay arm.
            if series.showsHeartRate {
                ForEach(series.heartRate.indices, id: \.self) { index in
                    let point = series.heartRate[index]
                    LineMark(
                        x: .value("Time", point.time),
                        y: .value("HR", scaledHR(point.bpm)),
                        series: .value("Series", "HeartRate")
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(AmberTheme.cgaMagenta.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }

                if let last = series.heartRate.last,
                   Date().timeIntervalSince(last.time) < 10 * 60 {
                    PointMark(
                        x: .value("Time", last.time),
                        y: .value("HR", scaledHR(last.bpm))
                    )
                    .foregroundStyle(AmberTheme.cgaMagenta.opacity(0.7))
                    .symbolSize(Config.heartRateSymbolSize)
                    .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                        Text("\(Int(last.bpm))")
                            .font(DOSTypography.caption)
                            .foregroundStyle(AmberTheme.cgaMagenta.opacity(0.7))
                    }
                }
            }

            // MARK: Instrument cursors
            if let range = cursors.range {
                RectangleMark(
                    xStart: .value("A", range.lowerBound),
                    xEnd: .value("B", range.upperBound),
                    yStart: .value("Bottom", 0),
                    yEnd: .value("Top", yMax)
                )
                .foregroundStyle(AmberTheme.surfaceTint)

                cursorRule(at: range.lowerBound, label: "A \(range.lowerBound.toLocalTime())")
                cursorRule(at: range.upperBound, label: "B \(range.upperBound.toLocalTime())")
                cursorPoint(at: range.lowerBound)
                cursorPoint(at: range.upperBound)
            } else if let cursor = cursors.cursor {
                cursorRule(at: cursor, label: cursor.toLocalTime())
                cursorPoint(at: cursor)
            }
        }
        .chartXScale(domain: series.domainStart...series.domainEnd)
        .chartYScale(domain: 0...yMax)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleDuration)
        .chartScrollPosition(x: $scrollPosition)
        .chartScrollTargetBehavior(.valueAligned(matching: DateComponents(minute: 0)))
        // ONLY the value selection. A range binding here would be dead wiring
        // that fights the two-press promotion below — A→B is built from two
        // sticky presses, which is also the interaction the spec describes.
        .chartXSelection(value: $liveSelection)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: labelEvery)) { _ in
                AxisGridLine(stroke: Config.axisStyle)
                AxisTick(length: 4, stroke: Config.tickStyle)
                    .foregroundStyle(AmberTheme.amberMuted)
                // A windowed chart's labels are hours apart and cannot collide
                // with each other — the only thing they "collide" with is the
                // plot frame, and Charts resolves that by dropping the two that
                // NAME the window. A scrolling chart keeps the default: its edge
                // labels move constantly and overlapping them would be worse.
                if isWindowed {
                    AxisValueLabel(
                        format: .dateTime.hour(.defaultDigits(amPM: .narrow)),
                        anchor: .top,
                        collisionResolution: .disabled
                    )
                } else {
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)), anchor: .top)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .stride(by: yAxisSteps)) { value in
                AxisGridLine(stroke: Config.axisStyle)

                if let glucoseValue = value.as(Double.self), glucoseValue > 0 {
                    AxisTick(length: 4, stroke: Config.tickStyle)
                        .foregroundStyle(AmberTheme.amberMuted)
                    AxisValueLabel()
                        .font(DOSTypography.mono(size: 10))
                }
            }
        }
        .chartLegend(.hidden)
        // A little horizontal room so the edge hour labels are not clipped by
        // the chart frame. No TOP inset: the chart's height budget is fixed, so
        // insetting the plot downwards pushes the x-axis labels out of frame —
        // the cursor labels get their headroom from `overflowResolution` instead.
        .chartPlotStyle { plotArea in
            plotArea.padding(.horizontal, plotSideInset)
        }
        // Simultaneous, so it never starves the scroll or the selection gesture.
        // A quick tap on empty plot clears the cursors; a press-and-hold (which
        // IS the scrub gesture) deliberately does not.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // The first event of a gesture carries no translation. Keying
                    // off it means a gesture the scroll view CANCELS (no .onEnded,
                    // so no reset) cannot strand a stale timestamp and kill
                    // tap-to-clear until the next completed gesture.
                    if value.translation == .zero || pressStartedAt == nil {
                        pressStartedAt = value.time
                    }
                }
                .onEnded { value in
                    let held = value.time.timeIntervalSince(pressStartedAt ?? value.time)
                    pressStartedAt = nil

                    if LabChartMath.isClearTap(
                        held: held,
                        translation: value.translation,
                        maxDuration: Config.tapMaxDuration,
                        maxDistance: Config.tapMaxDistance
                    ) {
                        cursors.clear()
                    }
                }
        )
        // The app's first AXChartDescriptor: the feature sheet IS the summary, and
        // every cited fact is a labelled point in the audio-graph rotor.
        .accessibilityChartDescriptor(LabChartDescriptor(
            series: series,
            facts: series.facts,
            sheet: series.sheet,
            glucoseUnit: store.state.glucoseUnit
        ))
        .onChange(of: liveSelection) {
            cursors.apply(selection: liveSelection, minRange: minRangeSeconds)
        }
        .onChange(of: scrollPosition) { updateFollowState() }
        .onChange(of: cursors.cursor) { fireDetentIfNeeded() }
    }

    private var followNub: some View {
        Button(action: jumpToNow) {
            Text("◂ \(followStatus.unseen) NEW")
                .font(DOSTypography.micro)
                .foregroundStyle(AmberTheme.amber)
                .dosCard(.toast, padding: DOSSpacing.xxs)
                // INSIDE the label: outside the Button it is a transparent hole
                // that swallows the tap and hands it to the clear gesture.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, DOSSpacing.lg)
        .padding(.top, DOSSpacing.xxs)
        .accessibilityLabel("Scroll to now, \(followStatus.unseen) new readings")
    }

    @ChartContentBuilder
    private func cursorRule(at date: Date, label: String) -> some ChartContent {
        RuleMark(x: .value("Cursor", date))
            .foregroundStyle(AmberTheme.amberLight)
            .lineStyle(Config.cursorStyle)
            .annotation(
                position: .top,
                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
            ) {
                Text(label)
                    .font(DOSTypography.microLabel)
                    .foregroundStyle(AmberTheme.amberLight)
                    .monospacedDigit()
            }
    }

    @ChartContentBuilder
    private func cursorPoint(at date: Date) -> some ChartContent {
        if let point = series.nearestGlucose(at: date) {
            PointMark(
                x: .value("Time", point.time),
                y: .value("Glucose", point.value)
            )
            .opacity(0.75)
            .symbolSize(Config.selectionSymbolSize)
            .foregroundStyle(AmberTheme.amberLight)
        }
    }

    // MARK: Derived values

    private var inputs: LabChartInputs {
        windowInputs ?? LabChartInputs(state: store.state, overlays: overlays)
    }

    /// A fixed window shows all of itself; the day chart shows a zoom chip's worth.
    private var isWindowed: Bool {
        windowInputs?.domainOverride != nil
    }

    private var sortedOverlays: [ChartLabOverlay] {
        overlays.sorted { $0.drawOrder < $1.drawOrder }
    }

    private var visibleHours: Int {
        LabChartMath.visibleHours(zoomLevel: store.state.chartZoomLevel, fallback: Config.visibleHoursFallback)
    }

    private var visibleDuration: TimeInterval {
        if isWindowed {
            return max(3600, series.domainEnd.timeIntervalSince(series.domainStart))
        }
        return TimeInterval(visibleHours * 3600)
    }

    private var labelEvery: Int {
        LabChartMath.labelEvery(visibleHours: Int((visibleDuration / 3600).rounded()))
    }

    /// 12 pt of plot, whatever that is worth in time at this zoom.
    private var minRangeSeconds: TimeInterval {
        LabChartMath.minRangeSeconds(
            visibleDuration: visibleDuration,
            plotWidth: plotWidth - 2 * plotSideInset,
            points: Config.minRangePoints
        )
    }

    /// A windowed chart's FIRST and LAST hour labels are the two numbers that
    /// name the window (20:00 → 10:00), so they get the room to render whole.
    /// A scrolling chart's edge labels move constantly and are not worth the
    /// plot width — P0's known nit, left as it is there.
    private var plotSideInset: CGFloat {
        isWindowed ? Config.windowedPlotSideInset : Config.plotSideInset
    }

    private var yAxisSteps: Double {
        store.state.glucoseUnit == .mmolL ? 3 : 50
    }

    /// Floor of the y domain's top, as the shipping chart forces it with an
    /// invisible rule mark (:701-707).
    private var chartMinimum: Double {
        store.state.glucoseUnit == .mmolL ? 18 : 300
    }

    private var yMax: Double {
        LabChartMath.yMax(
            floor: chartMinimum,
            // The band is drawn on the SAME scale as the trace, so a p95 above
            // today's maximum widens the floor instead of being clipped at it.
            plotted: plottedValues + (series.patternBand?.maxValue.map { [$0] } ?? [])
        )
    }

    /// Only what is actually ON the plot. The window path fetches a 4-hour lead
    /// so a meal keeps its pre-meal baseline — but a 19:00 spike must not lift
    /// the night's axis for a reading the user cannot see.
    private var plottedValues: [Double] {
        let points = series.glucose + series.bloodGlucose
        guard isWindowed else { return points.map(\.value) }
        return points
            .filter { $0.time >= series.domainStart && $0.time <= series.domainEnd }
            .map(\.value)
    }

    private var alarmLow: Double {
        convertToRequired(mgdLValue: store.state.alarmLow)
    }

    private var alarmHigh: Double {
        convertToRequired(mgdLValue: store.state.alarmHigh)
    }

    private func convertToRequired(mgdLValue: Int) -> Double {
        store.state.glucoseUnit == .mmolL ? mgdLValue.toMmolL() : mgdLValue.toDouble()
    }

    /// Plot BPM on the glucose axis, so 80 bpm sits where 80 mg/dL does
    /// (ChartView.swift:717-723).
    private func scaledHR(_ bpm: Double) -> Double {
        convertToRequired(mgdLValue: Int(bpm.rounded()))
    }

    private var followEdge: Date {
        LabChartMath.followEdge(
            domainStart: series.domainStart,
            domainEnd: series.domainEnd,
            visibleDuration: visibleDuration
        )
    }

    // MARK: Series rebuild

    private func rebuild() {
        // Same guard every DataStore middleware uses: nothing to draw while the
        // scene is inactive (ChartView.swift:737-739).
        guard store.state.appState == .active else { return }

        let snapshot = inputs
        let wasFollowing = followStatus.isFollowing
        let seen = lastSeenReadingTime
        let visible = visibleDuration

        Self.calculationQueue.async {
            let built = LabChartSeriesBuilder.build(snapshot)

            DispatchQueue.main.async {
                self.series = built
                self.factsBinding?.wrappedValue = LabFactsSnapshot(facts: built.facts, sheet: built.sheet)

                if wasFollowing {
                    self.scrollPosition = LabChartMath.followEdge(
                        domainStart: built.domainStart,
                        domainEnd: built.domainEnd,
                        visibleDuration: visible
                    )
                    self.markCaughtUp()
                } else {
                    // By timestamp, never by array length — the store's window rolls.
                    self.followStatus = .detached(unseen: LabChartMath.unseenCount(
                        readingTimes: built.glucose.map(\.time),
                        newerThan: seen
                    ))
                }
            }
        }
    }

    /// Changing `chartXVisibleDomain` re-anchors the scroll unless the position
    /// is co-set, so the leading edge is re-asserted after the new length lands —
    /// and the follow state is recomputed, because re-asserting an equal value
    /// fires no `.onChange`.
    private func reanchorAfterZoom() {
        let edge = followStatus.isFollowing ? followEdge : scrollPosition
        DispatchQueue.main.async {
            self.scrollPosition = edge
            self.updateFollowState()
        }
    }

    /// A tapped card moves the instrument: centre the anchor in the visible
    /// window and leave a standing cursor on it, so the readout strip says the
    /// same numbers the card does.
    private func applyFocus() {
        guard let focusRequest else { return }

        let centred = focusRequest.date.addingTimeInterval(-visibleDuration / 2)
        let clamped = min(max(series.domainStart, centred), followEdge)

        withAnimation(AnimationTokens.snappy) {
            scrollPosition = clamped
        }
        cursors.place(at: focusRequest.date)
    }

    private func updateFollowState() {
        let following = LabChartMath.isFollowing(
            scrollPosition: scrollPosition,
            domainEnd: series.domainEnd,
            visibleDuration: visibleDuration,
            slack: Config.followSlack
        )

        if following {
            markCaughtUp()
        } else if followStatus.isFollowing {
            followStatus = .detached(unseen: 0)
            lastSeenReadingTime = series.glucose.last?.time
        }
    }

    /// The newest reading is in view: nothing is unseen, and this is the mark
    /// everything later counts against.
    private func markCaughtUp() {
        followStatus = .following
        lastSeenReadingTime = series.glucose.last?.time
    }

    private func jumpToNow() {
        withAnimation(AnimationTokens.snappy) {
            scrollPosition = followEdge
        }
        markCaughtUp()
    }

    // MARK: Detents

    /// A light tick as the cursor crosses an event, a medium one as it crosses an
    /// alarm bound. Silent through the night profile, mirroring the celebration
    /// toast's night gate.
    private func fireDetentIfNeeded() {
        guard let cursor = cursors.cursor else {
            lastDetentKey = nil
            onCursorChange?(nil)
            return
        }

        let key = series.detentKey(
            at: cursor,
            alarmLow: alarmLow,
            alarmHigh: alarmHigh,
            window: Config.detentWindow
        )
        let feedback = LabDetent.feedback(
            newKey: key,
            previousKey: lastDetentKey,
            isNight: store.state.activeAlarmProfile == .night
        )
        lastDetentKey = key
        onCursorChange?(cursor)

        switch feedback {
        case .light: DirectNotifications.shared.hapticFeedback(.light)
        case .medium: DirectNotifications.shared.hapticFeedback(.medium)
        case nil: break
        }
    }
}

// MARK: - LabDayPager

/// DOS-style day pager, the lab's own copy of the shipping chart's
/// (ChartView.swift:35-77) so the shipping file stays untouched.
private struct LabDayPager: View {
    @EnvironmentObject var store: DirectStore

    /// Non-nil when the chart is drawing a fixed window (the night). "24 hours"
    /// would be a lie there — the window is 14, and it belongs to a DAY.
    let windowDate: Date?

    var body: some View {
        HStack {
            let canGoBack = (store.state.selectedDate ?? Date()).startOfDay > store.state.minSelectedDate.startOfDay

            Button(action: {
                setSelectedDate(addDays: -1)
            }, label: {
                Text(verbatim: "<")
                    .font(DOSTypography.mono(size: 17, weight: .bold))
                    .frame(minWidth: 32, minHeight: 32)
            })
            .opacity(canGoBack ? 0.7 : 0)
            .disabled(!canGoBack)

            Spacer()

            Group {
                if let selectedDate = store.state.selectedDate {
                    Text(verbatim: selectedDate.toLocalDate())
                } else if let windowDate {
                    Text(verbatim: windowDate.toLocalDate())
                } else {
                    Text("\(DirectConfig.lastChartHours.description) hours")
                }
            }
            .monospacedDigit()
            .onTapGesture {
                store.dispatch(.setSelectedDate(selectedDate: nil))
            }

            Spacer()

            Button(action: {
                setSelectedDate(addDays: +1)
            }, label: {
                Text(verbatim: ">")
                    .font(DOSTypography.mono(size: 17, weight: .bold))
                    .frame(minWidth: 32, minHeight: 32)
            })
            .opacity(store.state.selectedDate == nil ? 0 : 0.7)
            .disabled(store.state.selectedDate == nil)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DOSSpacing.sm)
    }

    private func setSelectedDate(addDays: Int) {
        store.dispatch(.setSelectedDate(
            selectedDate: Calendar.current.date(byAdding: .day, value: +addDays, to: store.state.selectedDate ?? Date())
        ))

        DirectNotifications.shared.hapticFeedback()
    }
}

// MARK: - LabReadoutStrip

/// Fixed-height instrument readout under the plot. Three states, ONE height —
/// the strip must never jump as the cursor changes.
private struct LabReadoutStrip: View {
    let series: LabChartSeries
    let cursor: Date?
    let range: ClosedRange<Date>?
    let glucoseUnit: GlucoseUnit
    /// ONE height for all three states — never per branch.
    let pinnedHeight: CGFloat
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: DOSSpacing.xs) {
            VStack(alignment: .leading, spacing: 3) {
                if let range {
                    rangeContent(range)
                } else if let cursor {
                    cursorContent(cursor)
                } else {
                    Text("TOUCH & HOLD TO MEASURE · DRAG TO SCROLL")
                        .font(DOSTypography.label)
                        .foregroundStyle(AmberTheme.textFaint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if cursor != nil || range != nil {
                // The escape hatch: always reachable, even if a gesture is
                // mid-flight and the tap-to-clear is momentarily unavailable.
                Button(action: onClear) {
                    Text(verbatim: "×")
                        .font(DOSTypography.mono(size: 17, weight: .bold))
                        .foregroundStyle(AmberTheme.amberDark)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear measurement")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .dosCard(.toast, padding: DOSSpacing.xs)
        .frame(height: pinnedHeight)
        .accessibilityElement(children: .combine)
    }

    // MARK: Cursor state

    @ViewBuilder
    private func cursorContent(_ cursor: Date) -> some View {
        let reading = series.nearestGlucose(at: cursor)
        let iob = series.iobValue(at: cursor)
        let meal = lastMeal(before: cursor)
        let heartRate = nearestHeartRate(at: cursor)

        let cursorLine: AttributedString = {
            var line = run(cursor.toLocalTime(), AmberTheme.amberLight)
            if let reading {
                line += separatorRun + run("G \(formatted(reading.value))", AmberTheme.amber)
            }
            if let iob, iob >= 0.05 {
                line += separatorRun + run("IOB \(formatUnits(iob))", AmberTheme.amber)
            }
            return line
        }()

        Text(cursorLine)
            .font(DOSTypography.label)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)

        let contextParts: [String] = {
            var parts: [String] = []
            if let meal, let carbs = meal.carbs {
                parts.append("MEAL \(Int(carbs))g (\(minutesAgoLabel(from: meal.time, to: cursor)))")
            }
            if let heartRate {
                parts.append("HR \(Int(heartRate))")
            }
            return parts
        }()

        if !contextParts.isEmpty {
            Text(contextParts.map { run($0, AmberTheme.amber) }.joinedWithSeparator(separatorRun))
                .font(DOSTypography.label)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: Range state

    @ViewBuilder
    private func rangeContent(_ range: ClosedRange<Date>) -> some View {
        let summary = series.summary(over: range)

        HStack {
            Text("A \(range.lowerBound.toLocalTime()) → B \(range.upperBound.toLocalTime())")
                .foregroundStyle(AmberTheme.amberLight)
            Spacer()
            Text("Δt \(durationLabel(range))")
                .foregroundStyle(AmberTheme.amber)
        }
        .font(DOSTypography.label)
        .monospacedDigit()
        // 12-hour locales render `A 11:11 AM → B 12:29 PM`.
        .lineLimit(1)
        .minimumScaleFactor(0.8)

        Text(joined(summary.readoutSegments(format: formatted, units: formatUnits)))
            .font(DOSTypography.label)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    // MARK: Helpers

    private func run(_ text: String, _ color: Color) -> AttributedString {
        var run = AttributedString(text)
        run.foregroundColor = color
        return run
    }

    /// Whitespace, as the prototype separates its groups — a ` · ` between every
    /// group cost 15 characters of a line that has to end with `n=`, and `n=`
    /// is the one thing that must never be the part that truncates.
    private var separatorRun: AttributedString {
        run("  ", AmberTheme.borderStrong)
    }

    /// ONE attributed string, so the whole line scales together instead of each
    /// run truncating on its own while a neighbour still has slack.
    private func joined(_ segments: [LabReadoutSegment]) -> AttributedString {
        segments
            .map { run($0.text, color(for: $0.emphasis)) }
            .joinedWithSeparator(separatorRun)
    }

    private func color(for emphasis: LabReadoutSegment.Emphasis) -> Color {
        switch emphasis {
        case .value: return AmberTheme.amber
        case .delta: return AmberTheme.amberLight
        case .sampleSize: return AmberTheme.amberDark
        }
    }

    /// Values arrive already in the display unit (the datapoint builders convert),
    /// so they are formatted — never converted — here.
    private func formatted(_ value: Double) -> String {
        let formatter = glucoseUnit == .mmolL
            ? GlucoseFormatters.mmolLFormatter
            : GlucoseFormatters.mgdLFormatter
        return formatter.string(from: value as NSNumber) ?? "—"
    }

    /// Same shape as the hero's IOB label (GlucoseView.swift:240-242), so the
    /// lab and the hero never disagree on how many units they are showing.
    private func formatUnits(_ value: Double) -> String {
        String(format: "%.1fU", value)
    }

    private func durationLabel(_ range: ClosedRange<Date>) -> String {
        let minutes = Int(range.upperBound.timeIntervalSince(range.lowerBound) / 60)
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h\(String(format: "%02d", remainder))" : "\(remainder)m"
    }

    private func minutesAgoLabel(from: Date, to: Date) -> String {
        let minutes = Int(to.timeIntervalSince(from) / 60)
        return "−\(minutes) MIN"
    }

    private func lastMeal(before date: Date) -> MealDatapoint? {
        series.meals
            .filter { $0.time <= date && date.timeIntervalSince($0.time) <= 4 * 60 * 60 }
            .max { $0.time < $1.time }
    }

    private func nearestHeartRate(at date: Date) -> Double? {
        series.heartRate
            .filter { abs($0.time.timeIntervalSince(date)) <= 5 * 60 }
            .min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }?
            .bpm
    }
}

// MARK: - AttributedString joining

private extension Array where Element == AttributedString {
    func joinedWithSeparator(_ separator: AttributedString) -> AttributedString {
        guard var result = first else { return AttributedString() }
        for element in dropFirst() {
            result += separator
            result += element
        }
        return result
    }
}
