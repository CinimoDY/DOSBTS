//
//  GlucoseChartView.swift
//  DOSBTS
//

import Charts
import SwiftUI

// MARK: - ChartView

struct ChartView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore
    let selectedReportType: ReportType
    let onTapMarkerGroup: (ConsolidatedMarkerGroup) -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch selectedReportType {
            case .glucose:
                GlucoseChartContent
            case .timeInRange:
                TimeInRangeReportView()
            case .statistics:
                StatisticsReportView()
            }
        }
    }

    // MARK: - Glucose Chart Content

    private var GlucoseChartContent: some View {
        VStack {
                    HStack {
                        // DOS-style day pager: "<" / ">" prompt glyphs
                        // (matching the Digest date pager), kept off the
                        // screen edge.
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

                    HStack {
                        Spacer()
                        if store.state.showHeartRateOverlay && !store.state.heartRateSeries.isEmpty {
                            HStack(spacing: 3) {
                                Canvas { context, size in
                                    var path = Path()
                                    path.move(to: CGPoint(x: 0, y: size.height / 2))
                                    path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                                    context.stroke(path, with: .color(AmberTheme.cgaMagenta.opacity(0.4)),
                                                   style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                }
                                .frame(width: 16, height: 8)
                                Text("HR")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(AmberTheme.cgaMagenta.opacity(0.5))
                            }
                            .padding(.trailing, 4)
                        }
                        Text(store.state.glucoseUnit.localizedDescription)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(AmberTheme.amberMuted)
                    }

                    GeometryReader { chartAreaGeo in
                    ZStack(alignment: .topLeading) {
                        ScrollViewReader { scrollViewProxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                VStack(spacing: 0) {
                                    if store.state.markerLanePosition == .top {
                                        EventMarkerLaneView(
                                            markerGroups: markerGroups,
                                            totalWidth: max(0, screenWidth, seriesWidth),
                                            timeRange: (startMarker ?? Date())...(endMarker ?? Date()),
                                            scoredMealEntryIds: store.state.scoredMealEntryIds,
                                            onTapGroup: onTapMarkerGroup
                                        )
                                        .frame(width: max(0, screenWidth, seriesWidth), height: Config.markerLaneHeight)
                                        .id("lane-\(store.state.markerLanePosition.rawValue)")
                                    }

                                    glucoseChart
                                        .frame(width: max(0, screenWidth, seriesWidth), height: chartHeight(available: chartAreaGeo.size.height))
                                    .onChange(of: store.state.sensorGlucoseValues) {
                                        scrollToEnd(scrollViewProxy: scrollViewProxy)

                                    }.onChange(of: store.state.bloodGlucoseValues) {
                                        scrollToEnd(scrollViewProxy: scrollViewProxy)

                                    }.onChange(of: store.state.insulinDeliveryValues) {
                                        scrollToEnd(scrollViewProxy: scrollViewProxy)

                                    }.onChange(of: store.state.chartZoomLevel) {
                                        scrollToEnd(scrollViewProxy: scrollViewProxy, force: true)

                                    }.onAppear {
                                        scrollToEnd(scrollViewProxy: scrollViewProxy)

                                    }.onTapGesture(count: 2) {
                                        showUnsmoothedValues = !showUnsmoothedValues
                                    }

                                    if store.state.markerLanePosition == .bottom {
                                        EventMarkerLaneView(
                                            markerGroups: markerGroups,
                                            totalWidth: max(0, screenWidth, seriesWidth),
                                            timeRange: (startMarker ?? Date())...(endMarker ?? Date()),
                                            scoredMealEntryIds: store.state.scoredMealEntryIds,
                                            onTapGroup: onTapMarkerGroup
                                        )
                                        .frame(width: max(0, screenWidth, seriesWidth), height: Config.markerLaneHeight)
                                        .id("lane-\(store.state.markerLanePosition.rawValue)")
                                    }
                                } // VStack
                            }
                        }

                        if selectedSmoothSensorPoint != nil || selectedRawSensorPoint != nil || selectedBloodPoint != nil || selectedHeartRate != nil {
                            ChartSelectionTooltip(
                                selectedSmoothSensorPoint: selectedSmoothSensorPoint,
                                selectedRawSensorPoint: selectedRawSensorPoint,
                                selectedBloodPoint: selectedBloodPoint,
                                selectedHeartRate: selectedHeartRate,
                                showRawPoint: showUnsmoothedValues && store.state.showSmoothedGlucose,
                                showHeartRate: store.state.showHeartRateOverlay
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
        }
    }

    var glucoseChart: some View {
        Chart {
            RuleMark(y: .value("Minimum High", chartMinimum))
                .foregroundStyle(.clear)

            RectangleMark(
                yStart: .value("Low", alarmLow),
                yEnd: .value("High", alarmHigh)
            )
            .foregroundStyle(AmberTheme.cgaGreen.opacity(0.08))

            RuleMark(y: .value("Lower limit", alarmLow))
                .foregroundStyle(AmberTheme.cgaRed)
                .lineStyle(Config.ruleStyle)

            RuleMark(y: .value("Upper limit", alarmHigh))
                .foregroundStyle(AmberTheme.cgaRed)
                .lineStyle(Config.ruleStyle)

            ForEach(glucoseSegments) { segment in
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

            // MARK: - Prediction projection line
            if let latest = store.state.latestSensorGlucose,
               let minuteChange = smoothedMinuteChange,
               Date().timeIntervalSince(latest.timestamp) < 5 * 60,
               store.state.selectedDate == nil
            {
                let currentGlucose = convertToRequired(mgdLValue: latest.glucoseValue)
                let predictedGlucose = currentGlucose + minuteChange * 20.0 * (store.state.glucoseUnit == .mmolL ? (1.0 / 18.0182) : 1.0)
                let endTime = latest.timestamp.addingTimeInterval(20 * 60)
                let predColor = AmberTheme.glucoseColor(forValue: Int(store.state.glucoseUnit == .mmolL ? predictedGlucose * 18.0182 : predictedGlucose), low: store.state.alarmLow, high: store.state.alarmHigh)

                LineMark(
                    x: .value("Time", latest.timestamp),
                    y: .value("Glucose", currentGlucose),
                    series: .value("Series", "prediction")
                )
                .foregroundStyle(predColor)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))

                LineMark(
                    x: .value("Time", endTime),
                    y: .value("Glucose", predictedGlucose),
                    series: .value("Series", "prediction")
                )
                .foregroundStyle(predColor)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))

                // Threshold crossing marker when prediction crosses alarmLow
                if minuteChange < 0 {
                    let currentMgdL = Double(latest.glucoseValue)
                    let alarmLowMgdL = Double(store.state.alarmLow)
                    if currentMgdL > alarmLowMgdL {
                        let minutesToCross = (alarmLowMgdL - currentMgdL) / minuteChange
                        if minutesToCross > 0, minutesToCross <= 20 {
                            let crossingTime = latest.timestamp.addingTimeInterval(minutesToCross * 60)
                            PointMark(
                                x: .value("Time", crossingTime),
                                y: .value("Glucose", alarmLow)
                            )
                            .symbol(.cross)
                            .symbolSize(80)
                            .foregroundStyle(AmberTheme.cgaRed)
                        }
                    }
                }
            }

            ForEach(bloodGlucoseSeries) { value in
                PointMark(
                    x: .value("Time", value.time),
                    y: .value("Glucose", value.value)
                )
                .symbolSize(Config.symbolSize)
                .foregroundStyle(AmberTheme.cgaRed)
            }

            ForEach(insulinSeries.filter { $0.type == .basal }) { value in
                RectangleMark(
                    xStart: .value("Starts", value.starts),
                    xEnd: .value("Ends", value.ends),
                    yStart: .value("Units", 0),
                    yEnd: .value("Units", value.value.map(from: 0...20, to: 0...Double(alarmLow)))
                )
                .opacity(0.25)
                .annotation(position: .overlay, alignment: .bottom) {
                    Text(value.value.asInsulin())
                        .foregroundStyle(AmberTheme.amberDark)
                        .padding(.horizontal, 2.5)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(2)
                        .bold()
                        .font(DOSTypography.caption)
                }
                .foregroundStyle(AmberTheme.amberDark)
            }

            // MARK: - IOB decay curve
            if !iobSeries.isEmpty {
                let maxIOB = iobSeries.map(\.total).max() ?? 1.0
                let iobCeiling = max(maxIOB, 1.0)

                if store.state.showSplitIOB {
                    // Bottom layer: basal + correction IOB — sky blue. Basal
                    // is the constant background baseline, so it sits at the
                    // floor of the chart. `series:` is required so Charts
                    // treats this and the bolus layer above as two independent
                    // series; without it the two ForEach loops auto-group into
                    // one stack and only one renders.
                    ForEach(Array(iobSeries.enumerated()), id: \.offset) { _, point in
                        AreaMark(
                            x: .value("Time", point.date),
                            yStart: .value("Bottom", 0),
                            yEnd: .value("IOB", point.corrBasal.map(from: 0...iobCeiling, to: 0...Double(alarmLow))),
                            series: .value("IOB Layer", "Basal")
                        )
                        .foregroundStyle(AmberTheme.iobBasal.opacity(0.85))
                        .interpolationMethod(.monotone)
                    }

                    // Top layer: meal/snack bolus IOB stacked above basal — warm green.
                    ForEach(Array(iobSeries.enumerated()), id: \.offset) { _, point in
                        AreaMark(
                            x: .value("Time", point.date),
                            yStart: .value("Bottom", point.corrBasal.map(from: 0...iobCeiling, to: 0...Double(alarmLow))),
                            yEnd: .value("IOB", point.total.map(from: 0...iobCeiling, to: 0...Double(alarmLow))),
                            series: .value("IOB Layer", "Bolus")
                        )
                        .foregroundStyle(AmberTheme.iobBolus.opacity(0.7))
                        .interpolationMethod(.monotone)
                    }
                } else {
                    ForEach(Array(iobSeries.enumerated()), id: \.offset) { _, point in
                        AreaMark(
                            x: .value("Time", point.date),
                            y: .value("IOB", point.total.map(from: 0...iobCeiling, to: 0...Double(alarmLow)))
                        )
                        .foregroundStyle(AmberTheme.iobBolus.opacity(0.4))
                        .interpolationMethod(.monotone)
                    }
                }
            }

            ForEach(exerciseSeries) { exercise in
                RectangleMark(
                    xStart: .value("Start", exercise.startTime),
                    xEnd: .value("End", exercise.endTime),
                    yStart: .value("Bottom", chartMinimum),
                    yEnd: .value("Top", chartMinimum * 0.95)
                )
                .foregroundStyle(AmberTheme.cgaCyan.opacity(0.3))
            }

            if store.state.showHeartRateOverlay {
                ForEach(store.state.heartRateSeries.indices, id: \.self) { index in
                    let point = store.state.heartRateSeries[index]
                    LineMark(
                        x: .value("Time", point.0),
                        y: .value("HR", scaledHR(point.1)),
                        series: .value("Series", "HeartRate")
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(AmberTheme.cgaMagenta.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }

                if let last = store.state.heartRateSeries.last,
                   Date().timeIntervalSince(last.0) < 10 * 60 {
                    PointMark(
                        x: .value("Time", last.0),
                        y: .value("HR", scaledHR(last.1))
                    )
                    .foregroundStyle(AmberTheme.cgaMagenta.opacity(0.7))
                    .symbolSize(30)
                    .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                        Text("\(Int(last.1))")
                            .font(DOSTypography.caption)
                            .foregroundStyle(AmberTheme.cgaMagenta.opacity(0.7))
                    }
                }
            }

            if showUnsmoothedValues, store.state.showSmoothedGlucose {
                if !rawSensorGlucoseSeries.isEmpty {
                    ForEach(rawSensorGlucoseSeries) { value in
                        LineMark(
                            x: .value("Time", value.time),
                            y: .value("Glucose", value.value),
                            series: .value("Series", "Raw")
                        )
                        .interpolationMethod(.monotone)
                        .opacity(0.5)
                        .foregroundStyle(AmberTheme.amberDark)
                        .lineStyle(Config.rawLineStyle)
                    }
                }

                if let selectedPointInfo = selectedRawSensorPoint {
                    PointMark(
                        x: .value("Time", selectedPointInfo.time),
                        y: .value("Glucose", selectedPointInfo.value)
                    )
                    //.symbol(.square)
                    .opacity(0.75)
                    .symbolSize(Config.selectionSize)
                    .foregroundStyle(AmberTheme.amberDark)
                }
            }

            if let selectedPointInfo = selectedSmoothSensorPoint {
                PointMark(
                    x: .value("Time", selectedPointInfo.time),
                    y: .value("Glucose", selectedPointInfo.value)
                )
                .opacity(0.75)
                .symbolSize(Config.selectionSize)
                .foregroundStyle(AmberTheme.amberLight)
            }

            if let selectedPointInfo = selectedBloodPoint {
                PointMark(
                    x: .value("Time", selectedPointInfo.time),
                    y: .value("Glucose", selectedPointInfo.value)
                )
                //.symbol(.square)
                .opacity(0.75)
                .symbolSize(Config.selectionSize)
                .foregroundStyle(AmberTheme.cgaRed)
            }

            if let endMarker = endMarker {
                RuleMark(
                    x: .value("", endMarker)
                ).foregroundStyle(.clear)
            }
        }
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
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                }
            }
        }
        .chartLegend(.hidden)
        .id(Config.chartID)
        .onChange(of: store.state.showSmoothedGlucose) {
            if shouldRefresh {
                DirectLog.info("onChange: sensorGlucoseValues")

                debounceSeriesMetadata()
                updateSensorSeries()
            }

        }.onChange(of: store.state.sensorGlucoseValues) {
            if shouldRefresh {
                DirectLog.info("onChange: sensorGlucoseValues")

                debounceSeriesMetadata()
                updateSensorSeries()
                updateSmoothedMinuteChange()
            }

        }.onChange(of: store.state.bloodGlucoseValues) {
            if shouldRefresh {
                DirectLog.info("onChange: bloodGlucoseValues")

                debounceSeriesMetadata()
                updateBloodSeries()
            }

        }.onChange(of: store.state.insulinDeliveryValues) {
            if shouldRefresh {
                DirectLog.info("onChange: insulinDeliveryValues")

                debounceSeriesMetadata()
                updateInsulinSeries()
                updateMarkerGroups()
            }

        }.onChange(of: store.state.iobDeliveries.count) {
            if shouldRefresh {
                DirectLog.info("onChange: iobDeliveries")
                updateInsulinSeries()
            }

        }.onChange(of: store.state.bolusInsulinPreset) {
            if shouldRefresh {
                DirectLog.info("onChange: bolusInsulinPreset")
                updateInsulinSeries()
            }

        }.onChange(of: store.state.basalDIAMinutes) {
            if shouldRefresh {
                DirectLog.info("onChange: basalDIAMinutes")
                updateInsulinSeries()
            }

        }.onChange(of: store.state.mealEntryValues) {
            if shouldRefresh {
                DirectLog.info("onChange: mealEntryValues")

                debounceSeriesMetadata()
                updateMealSeries()
                updateMarkerGroups()
            }

        }.onChange(of: store.state.exerciseEntryValues) {
            if shouldRefresh {
                DirectLog.info("onChange: exerciseEntryValues")

                debounceSeriesMetadata()
                updateExerciseSeries()
                updateMarkerGroups()
            }

        }.onChange(of: store.state.chartZoomLevel) {
            if shouldRefresh {
                DirectLog.info("onChange: chartZoomLevel")

                debounceSeriesMetadata()
                updateMarkerGroups()
            }

        }.onChange(of: store.state.showSmoothedGlucose) {
            showUnsmoothedValues = false

        }.onChange(of: store.state.selectedDate) {
            selectedSmoothSensorPoint = nil
            selectedRawSensorPoint = nil
            selectedBloodPoint = nil
            selectedHeartRate = nil

        }.onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            if shouldRefresh {
                DirectLog.info("onChange: orientation")

                debounceSeriesMetadata()
            }

        }.onAppear {
            DirectLog.info("onAppear")

            updateSeriesMetadata()
            updateSensorSeries()
            updateBloodSeries()
            updateInsulinSeries()
            updateMealSeries()
            updateExerciseSeries()
            updateHeartRateLookup()
            updateSmoothedMinuteChange()
            updateMarkerGroups()

        }.chartOverlay { overlayProxy in
            GeometryReader { geometryProxy in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard let plotFrame = overlayProxy.plotFrame else { return }
                            let currentX = value.location.x - geometryProxy[plotFrame].origin.x

                            if let currentDate: Date = overlayProxy.value(atX: currentX) {
                                let rounded = currentDate.toRounded(on: 1, .minute)
                                let selectedSmoothSensorPoint = smoothSensorPointInfos[rounded]
                                let selectedRawSensorPoint = rawSensorPointInfos[rounded]
                                let selectedBloodPoint = bloodPointInfos[rounded]

                                if let selectedSmoothSensorPoint {
                                    self.selectedSmoothSensorPoint = selectedSmoothSensorPoint
                                }

                                self.selectedRawSensorPoint = selectedRawSensorPoint
                                self.selectedBloodPoint = selectedBloodPoint

                                // Search nearby minutes for heart rate (HR samples may not align exactly).
                                // Skip when the overlay is disabled — keeps the HR chip in the tooltip
                                // hidden and avoids the lookup work on every drag tick.
                                if store.state.showHeartRateOverlay {
                                    self.selectedHeartRate = nearestHeartRate(at: rounded)
                                }
                            }
                        }
                        .onEnded { dragValue in
                            let wasTap = abs(dragValue.translation.width) < 10 && abs(dragValue.translation.height) < 10

                            selectedSmoothSensorPoint = nil
                            selectedRawSensorPoint = nil
                            selectedBloodPoint = nil
                            selectedHeartRate = nil

                            guard wasTap else { return }
                        }
                    )
            }
        }
    }

    // MARK: Private

    private enum Config {
        static let chartID = "chart"
        static let cornerRadius: CGFloat = 20
        static let rangeCornerRadius: CGFloat = 2
        static let insulinSize: MarkDimension = 10
        static let symbolSize: CGFloat = 20
        static let selectionSize: CGFloat = 100
        static let mealSymbolSize: CGFloat = 120
        static let insulinSymbolSizeRange: ClosedRange<Double> = 30...160
        static let spacerWidth: CGFloat = 50
        static let chartHeight: CGFloat = 250
        static let minChartHeight: CGFloat = 140
        static let lineStyle: StrokeStyle = .init(lineWidth: 3, lineCap: .round)
        static let smoothLineStyle: StrokeStyle = .init(lineWidth: 3.5, lineCap: .round)
        static let rawLineStyle: StrokeStyle = .init(lineWidth: 3, lineCap: .round)
        static let ruleStyle: StrokeStyle = .init(lineWidth: 1, dash: [2])
        static let gridStyle: StrokeStyle = .init(lineWidth: 1)
        static let dayStyle: StrokeStyle = .init(lineWidth: 1)
        static let axisStyle: StrokeStyle = .init(lineWidth: 0.3, dash: [2, 3])
        static let tickStyle: StrokeStyle = .init(lineWidth: 4)
        static let zoomLevels: [ZoomLevel] = [
            ZoomLevel(level: 3, name: LocalizedString("3h"), visibleHours: 3, labelEvery: 1),
            ZoomLevel(level: 6, name: LocalizedString("6h"), visibleHours: 6, labelEvery: 2),
            ZoomLevel(level: 12, name: LocalizedString("12h"), visibleHours: 12, labelEvery: 3),
            ZoomLevel(level: 24, name: LocalizedString("24h"), visibleHours: 24, labelEvery: 4)
        ]
        static let markerLaneHeight: CGFloat = 60
        static let consolidationWindows: [Int: TimeInterval] = [
            3: 0,
            6: 10 * 60,
            12: 20 * 60,
            24: 30 * 60
        ]
    }

    @State private var showUnsmoothedValues: Bool = false

    @State private var seriesWidth: CGFloat = 0
    @State private var smoothSensorGlucoseSeries: [GlucoseDatapoint] = []
    @State private var glucoseSegments: [GlucoseSegment] = []
    @State private var rawSensorGlucoseSeries: [GlucoseDatapoint] = []
    @State private var bloodGlucoseSeries: [GlucoseDatapoint] = []
    @State private var insulinSeries: [InsulinDatapoint] = []
    @State private var mealSeries: [MealDatapoint] = []
    @State private var exerciseSeries: [ExerciseDatapoint] = []
    @State private var iobSeries: [(date: Date, total: Double, mealSnack: Double, corrBasal: Double)] = []

    @State private var smoothSensorPointInfos: [Date: GlucoseDatapoint] = [:]
    @State private var rawSensorPointInfos: [Date: GlucoseDatapoint] = [:]
    @State private var bloodPointInfos: [Date: GlucoseDatapoint] = [:]

    @State private var selectedSmoothSensorPoint: GlucoseDatapoint? = nil
    @State private var selectedRawSensorPoint: GlucoseDatapoint? = nil
    @State private var selectedBloodPoint: GlucoseDatapoint? = nil
    @State private var selectedHeartRate: Int? = nil
    @State private var heartRatePointInfos: [Date: Int] = [:]

    @State private var markerGroups: [ConsolidatedMarkerGroup] = []

    @State private var smoothedMinuteChange: Double? = nil

    private let calculationQueue = DispatchQueue(label: "libre-direct.chart-calculation", qos: .utility)

    @State private var metadataDebounceTask: DispatchWorkItem? = nil

    private func debounceSeriesMetadata() {
        metadataDebounceTask?.cancel()
        let task = DispatchWorkItem { updateSeriesMetadata() }
        metadataDebounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: task)
    }

    /// Chart height adapts to the space actually available so the Overview
    /// VStack never overflows the screen (e.g. when the treatment banner
    /// is inserted above the chart, the chart compresses instead of pushing
    /// the quick-action buttons under the tab bar).
    private func chartHeight(available: CGFloat) -> CGFloat {
        let forChart = available - Config.markerLaneHeight
        return max(Config.minChartHeight, min(Config.chartHeight, forChart))
    }

    private var screenWidth: CGFloat {
        // Clamp to 0: pre-scene cold launch returns 0 for UIScreen.screenWidth,
        // and 0 - 40 = -40 would cache into seriesWidth @State and stick there.
        max(0, UIScreen.screenWidth - 40)
    }

    private var yAxisSteps: Double {
        if store.state.glucoseUnit == .mmolL {
            return 3
        }

        return 50
    }

    private var zoomLevel: ZoomLevel? {
        if let zoomLevel = Config.zoomLevels.first(where: { $0.level == store.state.chartZoomLevel }) {
            return zoomLevel
        }

        return Config.zoomLevels.first
    }

    private var labelEvery: Int {
        if let zoomLevel = zoomLevel {
            return zoomLevel.labelEvery
        }

        return 1
    }

    private var chartMinimum: Double {
        if store.state.glucoseUnit == .mmolL {
            return 18
        }

        return 300
    }

    private var alarmLow: Double {
        convertToRequired(mgdLValue: store.state.alarmLow)
    }

    private var alarmHigh: Double {
        convertToRequired(mgdLValue: store.state.alarmHigh)
    }

    private func scaledHR(_ bpm: Double) -> Double {
        // Plot the actual BPM on the same Y axis the glucose line uses, so
        // an HR of 80 lands at the same height as a glucose of 80 mg/dL.
        // For mmol/L users, convert through the same path the glucose values
        // take (80 mg/dL → 4.4 mmol/L) so the line stays on the visible axis.
        convertToRequired(mgdLValue: Int(bpm.rounded()))
    }

private var startMarker: Date? {
        return firstTimestamp
    }

    private var endMarker: Date? {
        if let lastTimestamp = lastTimestamp, store.state.selectedDate == nil {
            return Calendar.current.date(byAdding: .minute, value: 15, to: lastTimestamp)
        }

        return lastTimestamp
    }

    private var shouldRefresh: Bool {
        store.state.appState == .active
    }

    private var firstTimestamp: Date? {
        let dates = [store.state.sensorGlucoseValues.first?.timestamp, store.state.bloodGlucoseValues.first?.timestamp]
            .compactMap { $0 }
            .sorted(by: { $0 < $1 })

        return dates.first
    }

    private var lastTimestamp: Date? {
        let dates = [store.state.sensorGlucoseValues.last?.timestamp, store.state.bloodGlucoseValues.last?.timestamp]
            .compactMap { $0 }
            .sorted(by: { $0 > $1 })

        return dates.first
    }

    private func convertToRequired(mgdLValue: Int) -> Double {
        if store.state.glucoseUnit == .mmolL {
            return mgdLValue.toMmolL()
        }

        return mgdLValue.toDouble()
    }

    private func setSelectedDate(addDays: Int) {
        // store.dispatch(.setChartZoomLevel(level: 24))
        store.dispatch(.setSelectedDate(selectedDate: Calendar.current.date(byAdding: .day, value: +addDays, to: store.state.selectedDate ?? Date())))

        DirectNotifications.shared.hapticFeedback()
    }

    private func scrollToStart(scrollViewProxy: ScrollViewProxy, force: Bool = false) {
        scrollTo(scrollViewProxy: scrollViewProxy, force: force, anchor: .leading)
    }

    private func scrollToEnd(scrollViewProxy: ScrollViewProxy, force: Bool = false) {
        scrollTo(scrollViewProxy: scrollViewProxy, force: force, anchor: .trailing)
    }

    private func scrollTo(scrollViewProxy: ScrollViewProxy, force: Bool = false, anchor: UnitPoint) {
        if selectedSmoothSensorPoint == nil || force {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
                scrollViewProxy.scrollTo(Config.chartID, anchor: anchor)
            }

            if force {
                selectedSmoothSensorPoint = nil
                selectedRawSensorPoint = nil
                selectedBloodPoint = nil
            }
        }
    }

    private func updateSeriesMetadata() {
        DirectLog.info("updateSeriesMetadata()")

        if let firstTimestamp = firstTimestamp,
           let lastTimestamp = lastTimestamp,
           let zoomLevel = zoomLevel
        {
            let minuteWidth = (screenWidth / CGFloat(zoomLevel.visibleHours * 60))
            let chartMinutes = CGFloat((lastTimestamp.timeIntervalSince1970 - firstTimestamp.timeIntervalSince1970) / 60)
            let seriesWidth = CGFloat(minuteWidth * chartMinutes)

            if self.seriesWidth != seriesWidth {
                self.seriesWidth = seriesWidth
            }
        }
    }

    private func updateSensorSeries() {
        DirectLog.info("updateSensorSeries()")

        // Snapshot store.state on the main actor before crossing the queue
        // boundary. Reading @Published state from a background queue is not
        // strict-concurrency-clean and would surface as a Sendable warning
        // under Swift 6 strict mode.
        let showSmoothedGlucose = store.state.showSmoothedGlucose
        let sensorGlucoseValues = store.state.sensorGlucoseValues
        let smoothThreshold = store.state.smoothThreshold

        calculationQueue.async {
            var smoothSensorPointInfos: [Date: GlucoseDatapoint] = [:]
            var rawSensorPointInfos: [Date: GlucoseDatapoint] = [:]

            let smoothSensorGlucoseSeries = DirectConfig.showSmoothedGlucose && showSmoothedGlucose
                ? populateSmoothValues(glucoseValues: sensorGlucoseValues)
                : populateValues(glucoseValues: sensorGlucoseValues)
            smoothSensorGlucoseSeries.forEach { value in
                if smoothSensorPointInfos[value.time] == nil {
                    smoothSensorPointInfos[value.time] = value
                }
            }

            let rawSensorGlucoseSeries = showSmoothedGlucose
                ? populateValues(glucoseValues: sensorGlucoseValues.filter {
                    $0.timestamp < smoothThreshold
                })
                : []
            rawSensorGlucoseSeries.forEach { value in
                if rawSensorPointInfos[value.time] == nil {
                    rawSensorPointInfos[value.time] = value
                }
            }

            let segments = segmentGlucoseSeries(smoothSensorGlucoseSeries)

            DispatchQueue.main.async {
                self.smoothSensorGlucoseSeries = smoothSensorGlucoseSeries
                self.glucoseSegments = segments
                self.smoothSensorPointInfos = smoothSensorPointInfos

                self.rawSensorGlucoseSeries = rawSensorGlucoseSeries
                self.rawSensorPointInfos = rawSensorPointInfos
            }
        }
    }

    private func updateBloodSeries() {
        DirectLog.info("updateBloodSeries()")

        let bloodGlucoseValues = store.state.bloodGlucoseValues

        calculationQueue.async {
            var bloodPointInfos: [Date: GlucoseDatapoint] = [:]
            let bloodGlucoseSeries = populateValues(glucoseValues: bloodGlucoseValues)
            bloodGlucoseSeries.forEach { value in
                if bloodPointInfos[value.time] == nil {
                    bloodPointInfos[value.time] = value
                }
            }

            DispatchQueue.main.async {
                self.bloodGlucoseSeries = bloodGlucoseSeries
                self.bloodPointInfos = bloodPointInfos
            }
        }
    }

    private func updateInsulinSeries() {
        DirectLog.info("updateInsulinSeries()")

        // Snapshot all needed state up front. Building the bolus/basal
        // models on the main actor keeps the factory (which reads enum +
        // Int values) off the background queue too.
        let insulinDeliveryValues = store.state.insulinDeliveryValues
        let bolusModel = ExponentialInsulinModel.bolus(preset: store.state.bolusInsulinPreset)
        let basalModel = ExponentialInsulinModel.basal(diaMinutes: store.state.basalDIAMinutes)
        let iobDeliveries = store.state.iobDeliveries
        let firstTS = firstTimestamp
        let lastTS = lastTimestamp
        let startDate = startMarker ?? Date()
        let endDate = endMarker ?? Date()

        calculationQueue.async {
            let insulinSeries = insulinDeliveryValues.map { $0.toDatapoint(minDate: startDate, maxDate: endDate) }.compactMap { $0 }

            var iobPoints: [(date: Date, total: Double, mealSnack: Double, corrBasal: Double)] = []

            if !iobDeliveries.isEmpty, let first = firstTS, let last = lastTS {
                // 1-minute sampling smooths visible step transitions when a
                // new bolus is delivered between two adjacent samples
                // (5-min sampling produced visible "cuts" in the area chart).
                let step: TimeInterval = 60
                var current = first
                while current <= last {
                    let result = computeIOB(
                        deliveries: iobDeliveries,
                        bolusModel: bolusModel,
                        basalModel: basalModel,
                        at: current
                    )
                    iobPoints.append((date: current, total: result.total, mealSnack: result.mealSnackIOB, corrBasal: result.correctionBasalIOB))
                    current = current.addingTimeInterval(step)
                }
            }

            DispatchQueue.main.async {
                self.insulinSeries = insulinSeries
                self.iobSeries = iobPoints
            }
        }
    }

    private func updateMealSeries() {
        DirectLog.info("updateMealSeries()")
        self.mealSeries = store.state.mealEntryValues.map { $0.toDatapoint() }
    }

    private func updateExerciseSeries() {
        DirectLog.info("updateExerciseSeries()")
        self.exerciseSeries = store.state.exerciseEntryValues.map { $0.toDatapoint() }
    }

    private func updateMarkerGroups() {
        let window = Config.consolidationWindows[store.state.chartZoomLevel] ?? 0
        var allMarkers: [EventMarker] = []

        for meal in store.state.mealEntryValues {
            let label: String
            if let carbs = meal.carbsGrams {
                label = "\(Int(carbs))g"
            } else {
                label = String(meal.mealDescription.prefix(6))
            }
            allMarkers.append(EventMarker(
                id: "meal-\(meal.id.uuidString)",
                time: meal.timestamp,
                type: .meal,
                label: label,
                rawValue: meal.carbsGrams ?? 0,
                sourceID: meal.id
            ))
        }

        for insulin in store.state.insulinDeliveryValues {
            allMarkers.append(EventMarker(
                id: "insulin-\(insulin.id.uuidString)",
                time: insulin.starts,
                type: insulin.type == .basal ? .basal : .bolus,
                label: insulin.units.asInsulin(),
                rawValue: insulin.units,
                sourceID: insulin.id
            ))
        }

        for exercise in store.state.exerciseEntryValues {
            let mins = Int(exercise.durationMinutes)
            allMarkers.append(EventMarker(
                id: "exercise-\(exercise.id.uuidString)",
                time: exercise.startTime,
                type: .exercise,
                label: "\(mins)m",
                rawValue: Double(mins),
                sourceID: exercise.id
            ))
        }

        allMarkers.sort { $0.time < $1.time }

        // Consolidate into groups based on zoom-level window
        var groups: [ConsolidatedMarkerGroup] = []
        var currentMarkers: [EventMarker] = []

        for marker in allMarkers {
            if let last = currentMarkers.last, window > 0, marker.time.timeIntervalSince(last.time) > window {
                // New group
                if !currentMarkers.isEmpty {
                    let midTime = currentMarkers[currentMarkers.count / 2].time
                    groups.append(ConsolidatedMarkerGroup(
                        id: "group-\(currentMarkers[0].id)",
                        time: midTime,
                        markers: currentMarkers
                    ))
                }
                currentMarkers = [marker]
            } else {
                currentMarkers.append(marker)
            }
        }
        if !currentMarkers.isEmpty {
            let midTime = currentMarkers[currentMarkers.count / 2].time
            groups.append(ConsolidatedMarkerGroup(
                id: "group-\(currentMarkers[0].id)",
                time: midTime,
                markers: currentMarkers
            ))
        }

        markerGroups = groups
    }

    private func updateSmoothedMinuteChange() {
        let recentWithChange = store.state.sensorGlucoseValues.suffix(10).filter { $0.minuteChange != nil }
        let last3 = recentWithChange.suffix(3)
        guard !last3.isEmpty else {
            smoothedMinuteChange = nil
            return
        }
        let sum = last3.compactMap(\.minuteChange).reduce(0, +)
        smoothedMinuteChange = sum / Double(last3.count)
    }

    private func updateHeartRateLookup() {
        var lookup: [Date: Int] = [:]
        for point in store.state.heartRateSeries {
            let rounded = point.0.toRounded(on: 1, .minute)
            lookup[rounded] = Int(point.1)
        }
        self.heartRatePointInfos = lookup
    }

    /// Search within +/- 2 minutes for nearest heart rate sample
    private func nearestHeartRate(at date: Date) -> Int? {
        for offset in 0...2 {
            if let forward = Calendar.current.date(byAdding: .minute, value: offset, to: date)?.toRounded(on: 1, .minute),
               let hr = heartRatePointInfos[forward] {
                return hr
            }
            if offset > 0,
               let backward = Calendar.current.date(byAdding: .minute, value: -offset, to: date)?.toRounded(on: 1, .minute),
               let hr = heartRatePointInfos[backward] {
                return hr
            }
        }
        return nil
    }

    private func populateValues(glucoseValues: [InsulinDelivery]) -> [InsulinDatapoint] {
        glucoseValues.map { value in
            value.toDatapoint(minDate: startMarker ?? Date(), maxDate: endMarker ?? Date())
        }
        .compactMap { $0 }
    }

    private func populateValues(glucoseValues: [BloodGlucose]) -> [GlucoseDatapoint] {
        glucoseValues.map { value in
            value.toDatapoint(glucoseUnit: store.state.glucoseUnit, alarmLow: store.state.alarmLow, alarmHigh: store.state.alarmHigh)
        }
        .compactMap { $0 }
    }

    private func populateValues(glucoseValues: [SensorGlucose]) -> [GlucoseDatapoint] {
        return glucoseValues.map { value in
            value.toDatapoint(glucoseUnit: store.state.glucoseUnit, alarmLow: store.state.alarmLow, alarmHigh: store.state.alarmHigh)
        }.compactMap { $0 }
    }

    private func populateSmoothValues(glucoseValues: [SensorGlucose]) -> [GlucoseDatapoint] {
        return glucoseValues.map { value in
            if value.timestamp < store.state.smoothThreshold {
                return value.toSmoothDatapoint(glucoseUnit: store.state.glucoseUnit, alarmLow: store.state.alarmLow, alarmHigh: store.state.alarmHigh)
            }

            return value.toDatapoint(glucoseUnit: store.state.glucoseUnit, alarmLow: store.state.alarmLow, alarmHigh: store.state.alarmHigh)
        }.compactMap { $0 }
    }
}
