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

    var body: some View {
        VStack(spacing: 0) {
            LabDayPager()

            unitRow

            GeometryReader { geo in
                plotArea(height: chartHeight(available: geo.size.height))
            }

            LabReadoutStrip(
                series: series,
                cursor: stickyCursor,
                range: stickyRange,
                glucoseUnit: store.state.glucoseUnit,
                height: Config.readoutHeight
            )
            .padding(.horizontal, DOSSpacing.sm)
            .padding(.top, DOSSpacing.xs)
        }
        .onAppear { rebuild() }
        .onChange(of: inputs) { rebuild() }
        .onChange(of: store.state.chartZoomLevel) { reanchorAfterZoom() }
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
        /// Mirrors ChartView.Config.zoomLevels (:614-619).
        static let labelEvery: [Int: Int] = [3: 1, 6: 2, 12: 3, 24: 4]
        static let visibleHoursFallback = 3
        /// A cursor within this of an event is "on" it, for the detent tick.
        static let detentWindow: TimeInterval = 2 * 60
        /// Two presses closer than this are a re-scrub, not an A→B range.
        static let minRangeSeconds: TimeInterval = 5 * 60
        /// Follow is "on" while the leading edge is within a minute of the end.
        static let followSlack: TimeInterval = 60
        /// Shorter than this, with no movement, is a tap (clear) — not a scrub.
        static let tapMaxDuration: TimeInterval = 0.35
        static let plotSideInset: CGFloat = 10
    }

    @State private var series: LabChartSeries = .empty
    /// `chartXSelection(value:)` — resets to nil on release.
    @State private var liveSelection: Date? = nil
    /// What actually renders: survives the release.
    @State private var stickyCursor: Date? = nil
    @State private var liveRange: ClosedRange<Date>? = nil
    @State private var stickyRange: ClosedRange<Date>? = nil
    /// True while one press-and-drag is in flight, so a continuing drag moves
    /// the current cursor instead of opening a new range.
    @State private var selectionSessionActive = false
    /// The A end while B is being dragged.
    @State private var rangeAnchor: Date? = nil

    @State private var scrollPosition: Date = Date()
    @State private var isFollowing = true
    @State private var unseenReadings = 0
    @State private var lastDetentKey: String? = nil
    /// When the current press began, so a tap can be told from a scrub.
    @State private var pressStartedAt: Date? = nil

    private let calculationQueue = DispatchQueue(label: "dosbts.lab-chart-calculation", qos: .utility)

    // MARK: Layout

    private var unitRow: some View {
        HStack {
            Spacer()
            Text(store.state.glucoseUnit.localizedDescription)
                .font(DOSTypography.mono(size: 9, weight: .medium))
                .foregroundStyle(AmberTheme.amberMuted)
        }
        .padding(.horizontal, DOSSpacing.xs)
        .padding(.bottom, DOSSpacing.xxs)
    }

    @ViewBuilder
    private func plotArea(height: CGFloat) -> some View {
        if series.isEmpty || series.domainStart >= series.domainEnd {
            VStack {
                Spacer()
                FiguresLoadingView.inline
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
        } else {
            chart
                .frame(height: height)
                .overlay(alignment: .topTrailing) {
                    if !isFollowing, unseenReadings > 0 {
                        followNub
                    }
                }
                .accessibilityLabel("Lab chart")
        }
    }

    /// Derives from the space actually available — never from `UIScreen`
    /// (swiftui-vstack-overflow-sinks-safeareainset).
    private func chartHeight(available: CGFloat) -> CGFloat {
        max(Config.minHeight, min(Config.maxHeight, available))
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
            if store.state.showHeartRateOverlay {
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
            if let range = stickyRange {
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
            } else if let cursor = stickyCursor {
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
        .chartXSelection(value: $liveSelection)
        .chartXSelection(range: $liveRange)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: labelEvery)) { _ in
                AxisGridLine(stroke: Config.axisStyle)
                AxisTick(length: 4, stroke: Config.tickStyle)
                    .foregroundStyle(AmberTheme.amberMuted)
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)), anchor: .top)
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
            plotArea.padding(.horizontal, Config.plotSideInset)
        }
        // Simultaneous, so it never starves the scroll or the selection gesture.
        // A quick tap on empty plot clears the cursors; a press-and-hold (which
        // IS the scrub gesture) deliberately does not.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if pressStartedAt == nil { pressStartedAt = Date() }
                }
                .onEnded { value in
                    let held = pressStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                    pressStartedAt = nil
                    let moved = abs(value.translation.width) > 10 || abs(value.translation.height) > 10
                    if !moved, held < Config.tapMaxDuration {
                        clearCursors()
                    }
                }
        )
        .onChange(of: liveSelection) { handleLiveSelection() }
        .onChange(of: liveRange) { handleLiveRange() }
        .onChange(of: scrollPosition) { updateFollowState() }
        .onChange(of: stickyCursor) { fireDetentIfNeeded() }
    }

    private var followNub: some View {
        Button(action: jumpToNow) {
            Text("◂ \(unseenReadings) NEW")
                .font(DOSTypography.micro)
                .foregroundStyle(AmberTheme.amber)
                .dosCard(.toast, padding: DOSSpacing.xxs)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .padding(.trailing, DOSSpacing.lg)
        .padding(.top, DOSSpacing.xxs)
        .accessibilityLabel("Scroll to now, \(unseenReadings) new readings")
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
        LabChartInputs(state: store.state, overlays: overlays)
    }

    private var sortedOverlays: [ChartLabOverlay] {
        overlays.sorted { $0.drawOrder < $1.drawOrder }
    }

    private var visibleHours: Int {
        Config.labelEvery[store.state.chartZoomLevel] == nil
            ? Config.visibleHoursFallback
            : store.state.chartZoomLevel
    }

    private var visibleDuration: TimeInterval {
        TimeInterval(visibleHours * 3600)
    }

    private var labelEvery: Int {
        Config.labelEvery[visibleHours] ?? 1
    }

    private var yAxisSteps: Double {
        store.state.glucoseUnit == .mmolL ? 3 : 50
    }

    /// Floor of the y domain's top, as the shipping chart forces it with an
    /// invisible rule mark (:701-707). The domain grows past it when a reading
    /// does, so an explicit scale can never clip a hyper.
    private var chartMinimum: Double {
        store.state.glucoseUnit == .mmolL ? 18 : 300
    }

    private var yMax: Double {
        let plotted = series.glucose.map(\.value) + series.bloodGlucose.map(\.value)
        return max(chartMinimum, (plotted.max() ?? 0).rounded(.up))
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
        max(series.domainStart, series.domainEnd.addingTimeInterval(-visibleDuration))
    }

    // MARK: Series rebuild

    private func rebuild() {
        // Same guard every DataStore middleware uses: nothing to draw while the
        // scene is inactive (ChartView.swift:737-739).
        guard store.state.appState == .active else { return }

        let snapshot = inputs
        let previousCount = series.readingCount
        let following = isFollowing
        let visible = visibleDuration

        calculationQueue.async {
            let built = LabChartSeriesBuilder.build(snapshot)

            DispatchQueue.main.async {
                self.series = built

                if following {
                    self.scrollPosition = max(
                        built.domainStart,
                        built.domainEnd.addingTimeInterval(-visible)
                    )
                } else {
                    self.unseenReadings += max(0, built.readingCount - previousCount)
                }
            }
        }
    }

    /// Changing `chartXVisibleDomain` re-anchors the scroll unless the position
    /// is co-set, so the leading edge is re-asserted after the new length lands.
    private func reanchorAfterZoom() {
        let edge = isFollowing ? followEdge : scrollPosition
        DispatchQueue.main.async {
            self.scrollPosition = edge
        }
    }

    private func updateFollowState() {
        isFollowing = scrollPosition >= series.domainEnd
            .addingTimeInterval(-visibleDuration - Config.followSlack)

        if isFollowing {
            unseenReadings = 0
        }
    }

    private func jumpToNow() {
        withAnimation(AnimationTokens.snappy) {
            scrollPosition = followEdge
        }
        isFollowing = true
        unseenReadings = 0
    }

    // MARK: Cursor arbitration

    /// Scroll is a plain drag (native). Scrub is press-and-drag: the built-in
    /// selection gesture on a scrollable chart. Its binding resets to nil on
    /// release, so the sticky copy is what renders — and the NEXT press promotes
    /// the standing cursor to A and the new position to B.
    private func handleLiveSelection() {
        guard let date = liveSelection else {
            selectionSessionActive = false
            return
        }

        if selectionSessionActive {
            if rangeAnchor != nil {
                extendRange(to: date)
            } else {
                stickyCursor = date
            }
            return
        }

        selectionSessionActive = true

        if let anchor = stickyCursor,
           stickyRange == nil,
           abs(date.timeIntervalSince(anchor)) >= Config.minRangeSeconds {
            rangeAnchor = anchor
            extendRange(to: date)
        } else {
            rangeAnchor = nil
            stickyRange = nil
            stickyCursor = date
        }
    }

    /// The built-in range gesture, when the platform hands it to us.
    private func handleLiveRange() {
        guard let range = liveRange else { return }
        stickyCursor = nil
        rangeAnchor = range.lowerBound
        stickyRange = range
    }

    private func extendRange(to date: Date) {
        guard let anchor = rangeAnchor else { return }
        stickyCursor = nil
        stickyRange = min(anchor, date)...max(anchor, date)
    }

    private func clearCursors() {
        stickyCursor = nil
        stickyRange = nil
        rangeAnchor = nil
        lastDetentKey = nil
    }

    // MARK: Detents

    /// A light tick as the cursor crosses an event, a medium one as it crosses an
    /// alarm bound. Silent through the night profile, mirroring the celebration
    /// toast's night gate.
    private func fireDetentIfNeeded() {
        guard let cursor = stickyCursor else {
            lastDetentKey = nil
            return
        }

        let key = detentKey(at: cursor)
        guard key != lastDetentKey else { return }
        lastDetentKey = key

        guard let key, store.state.activeAlarmProfile != .night else { return }

        let isBound = key == "low" || key == "high"
        DirectNotifications.shared.hapticFeedback(isBound ? .medium : .light)
    }

    private func detentKey(at date: Date) -> String? {
        if let meal = series.meals.first(where: { abs($0.time.timeIntervalSince(date)) <= Config.detentWindow }) {
            return "meal-\(meal.id)"
        }
        if let dose = series.insulin.first(where: { abs($0.starts.timeIntervalSince(date)) <= Config.detentWindow }) {
            return "insulin-\(dose.id)"
        }
        if let exercise = series.exercise.first(where: { abs($0.startTime.timeIntervalSince(date)) <= Config.detentWindow }) {
            return "exercise-\(exercise.id)"
        }
        if let reading = series.nearestGlucose(at: date) {
            if reading.value <= alarmLow { return "low" }
            if reading.value >= alarmHigh { return "high" }
        }
        return nil
    }
}

// MARK: - LabDayPager

/// DOS-style day pager, the lab's own copy of the shipping chart's
/// (ChartView.swift:35-77) so the shipping file stays untouched.
private struct LabDayPager: View {
    @EnvironmentObject var store: DirectStore

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
    let height: CGFloat

    var body: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .dosCard(.toast, padding: DOSSpacing.xs)
        .frame(height: height)
        .accessibilityElement(children: .combine)
    }

    // MARK: Cursor state

    @ViewBuilder
    private func cursorContent(_ cursor: Date) -> some View {
        let reading = series.nearestGlucose(at: cursor)
        let iob = series.iobValue(at: cursor)
        let meal = lastMeal(before: cursor)
        let heartRate = nearestHeartRate(at: cursor)

        HStack(spacing: DOSSpacing.sm) {
            Text(cursor.toLocalTime())
                .foregroundStyle(AmberTheme.amberLight)
            if let reading {
                Text("G \(formatted(reading.value))")
            }
            if let iob, iob >= 0.05 {
                Text("IOB \(formatUnits(iob))")
            }
        }
        .font(DOSTypography.label)
        .foregroundStyle(AmberTheme.amber)
        .monospacedDigit()

        HStack(spacing: DOSSpacing.sm) {
            if let meal, let carbs = meal.carbs {
                Text("MEAL \(Int(carbs))g (\(minutesAgoLabel(from: meal.time, to: cursor)))")
            }
            if let heartRate {
                Text("HR \(Int(heartRate))")
            }
        }
        .font(DOSTypography.label)
        .foregroundStyle(AmberTheme.amber)
        .monospacedDigit()
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

        HStack(spacing: DOSSpacing.sm) {
            if let first = summary.first, let last = summary.last {
                HStack(spacing: 4) {
                    Text("G \(formatted(first))→\(formatted(last))")
                        .foregroundStyle(AmberTheme.amber)
                    if let delta = summary.delta {
                        Text("(\(signed(delta)))")
                            .foregroundStyle(AmberTheme.amberLight)
                    }
                }
            }
            if let low = summary.min, let high = summary.max {
                Text("MIN \(formatted(low)) · MAX \(formatted(high))")
                    .foregroundStyle(AmberTheme.amber)
            }
            if summary.insulinUnits > 0 {
                Text("IN \(formatUnits(summary.insulinUnits))")
                    .foregroundStyle(AmberTheme.amber)
            }
            if summary.carbsGrams > 0 {
                Text("CARBS \(Int(summary.carbsGrams))g")
                    .foregroundStyle(AmberTheme.amber)
            }
            // Every derived number ships with its sample size.
            Text("n=\(summary.readings)")
                .foregroundStyle(AmberTheme.amberDark)
        }
        .font(DOSTypography.label)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    // MARK: Helpers

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

    private func signed(_ value: Double) -> String {
        (value > 0 ? "+" : "") + formatted(value)
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
