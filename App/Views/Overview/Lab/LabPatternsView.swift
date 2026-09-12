//
//  LabPatternsView.swift
//  DOSBTS
//
//  LAB: PATTERNS (DMNC-1503) — today's chart with the user's OWN hourly band
//  ghosted behind it, the hours where today left that band flagged with their
//  sample size, and a same-hour drill across the last 14 days.
//
//  The question it answers is "is today unusual FOR ME, and where" — never
//  "what should I do about it". Every line carries its `n`; the drill's `> 180`
//  is the consensus threshold and says so.
//
//  Gesture note: the drill is driven by P0's existing press-and-hold scrub
//  (`LabChartView.onCursorChange`), NOT by a long-press of its own. A second
//  long-press on the same plot would compete with the scrub and lose.
//

import Charts
import SwiftUI

struct LabPatternsView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore

    var body: some View {
        VStack(spacing: 0) {
            LabChartView(
                overlays: ReportType.labPatterns.labOverlays,
                followStatus: $followStatus,
                unitRowLabel: PatternCopy.bandChip(days: lookbackDays),
                onCursorChange: { cursorDate = $0 }
            )

            drillCard
                .padding(.horizontal, DOSSpacing.sm)
                .padding(.top, DOSSpacing.xs)

            LabLegendRow(items: [
                LabLegendItem(glyph: "▒", label: "P25–P75", color: AmberTheme.amber),
                LabLegendItem(glyph: "░", label: "P5–P95", color: AmberTheme.amberDark),
                LabLegendItem(glyph: "▎", label: "OUT OF BAND", color: AmberTheme.amberLight),
                LabLegendItem.follow(followStatus),
            ])

            LabFooter()
        }
        .onAppear {
            store.dispatch(.loadLabPatterns(days: store.state.statisticsDays))
            refreshDrill()
        }
        // ONE cheap string, so the 90-day reading array is never compared on a
        // render. The day chips are handled by the middleware's own
        // `.setStatisticsDays` arm, not by a second dispatch from here.
        .onChange(of: drillIdentity) { refreshDrill() }
    }

    // MARK: Private

    private enum Config {
        static let traceChartHeight: CGFloat = 120
        static let todayLineWidth: CGFloat = 2
        static let pastLineWidth: CGFloat = 1
        static let thresholdStyle: StrokeStyle = .init(lineWidth: 1, dash: [2])
        static let axisStyle: StrokeStyle = .init(lineWidth: 0.3, dash: [2, 3])
    }

    @State private var followStatus: LabFollowStatus = .following
    /// The scrub cursor, mirrored out of `LabChartView`.
    @State private var cursorDate: Date?
    /// The cursor position whose drill the user dismissed with `×`. Moving the
    /// cursor re-arms the drill; the chart's own cursor is left alone, because
    /// clearing someone's measurement to close a card would be rude.
    @State private var dismissedDrill: Date?
    @State private var drill: SameHourDrill?
    @State private var drillKey: String = ""

    private var lookbackDays: Int {
        store.state.labPatterns?.days ?? LabPatternEvidence.cappedDays(store.state.statisticsDays)
    }

    private var glucoseUnit: GlucoseUnit { store.state.glucoseUnit }

    /// The drill reaches 14 days back, or as far as the loaded band if that is
    /// shorter (the 7d chip loads seven days, and nothing may promise more).
    private var drillWindowDays: Int {
        PatternCopy.drillWindowDays(lookbackDays: lookbackDays)
    }

    /// The hour the user is holding, if any — nil once they dismiss its card.
    private var heldHour: Int? {
        guard let cursorDate, cursorDate != dismissedDrill else { return nil }
        return Calendar.current.component(.hour, from: cursorDate)
    }

    /// What the drill describes: the held hour, else the pattern hour (the
    /// widest-spread one), else nothing.
    private var activeHour: Int? {
        heldHour ?? store.state.labPatterns.flatMap { PatternAnalysis.patternHour($0.hourly)?.hour }
    }

    /// Cheap identity for the drill inputs — comparing `LabPatternEvidence`
    /// itself would compare up to 90 days of readings on every render.
    private var drillIdentity: String {
        let evidence = store.state.labPatterns
        return [
            String(activeHour ?? -1),
            String(evidence?.readings.count ?? 0),
            String(Int(evidence?.period.end.timeIntervalSince1970 ?? 0)),
        ].joined(separator: "|")
    }

    // MARK: Drill card

    @ViewBuilder
    private var drillCard: some View {
        VStack(alignment: .leading, spacing: DOSSpacing.xxs) {
            if store.state.labPatterns == nil {
                // The day chart still renders while this loads — only the card
                // waits, because only the card needs the multi-day read.
                HStack {
                    FiguresLoadingView.inline
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(heldHour.map { PatternCopy.heldHint(hour: $0, days: drillWindowDays) }
                    ?? PatternCopy.holdHint(days: drillWindowDays))
                    .font(DOSTypography.label)
                    .foregroundStyle(AmberTheme.amberLight)

                HStack(alignment: .firstTextBaseline) {
                    Text(resultLine)
                        .font(DOSTypography.label)
                        .foregroundStyle(AmberTheme.amber)
                        .monospacedDigit()

                    Spacer()

                    if heldHour != nil {
                        Button(action: { dismissedDrill = cursorDate }) {
                            Text(verbatim: "×")
                                .font(DOSTypography.mono(size: 17, weight: .bold))
                                .foregroundStyle(AmberTheme.amberDark)
                                .frame(width: 44, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close the hour drill")
                    }
                }

                if heldHour != nil, let drill, !drill.traces.isEmpty {
                    traceChart(drill)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dosCard(.stat, padding: DOSSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    /// The card's second line. With no hour in hand it describes the pattern
    /// hour; with too little evidence it refuses to describe anything.
    private var resultLine: String {
        guard let drill else {
            let readings = store.state.labPatterns?.readings.count ?? 0
            return "\(lookbackDays)-DAY BAND · n=\(readings) READINGS"
        }

        let line = PatternCopy.drillLine(
            daysAbove: drill.daysAbove180,
            days: drill.days,
            readings: drill.n,
            glucoseUnit: glucoseUnit
        )
        // Unheld, the line is about the pattern hour — say which, or it reads as
        // a statement about the whole day.
        return heldHour == nil ? "\(PatternCopy.hourLabel(drill.hour)) · \(line)" : line
    }

    // MARK: Trace chart

    private func traceChart(_ drill: SameHourDrill) -> some View {
        Chart {
            RuleMark(y: .value("Threshold", display(PatternAnalysis.highThresholdMgDL)))
                .foregroundStyle(AmberTheme.cgaRed)
                .lineStyle(Config.thresholdStyle)

            ForEach(drill.traces) { trace in
                ForEach(trace.points.indices, id: \.self) { index in
                    LineMark(
                        x: .value("Offset", trace.points[index].offsetMinutes),
                        y: .value("Glucose", display(trace.points[index].value)),
                        series: .value("Day", trace.day)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(trace.isToday ? AmberTheme.amber : AmberTheme.amberDark)
                    .lineStyle(StrokeStyle(
                        lineWidth: trace.isToday ? Config.todayLineWidth : Config.pastLineWidth,
                        lineCap: .round
                    ))
                }
            }
        }
        .chartXScale(domain: -Double(PatternAnalysis.drillHalfWidthMinutes) ... Double(PatternAnalysis.drillHalfWidthMinutes))
        .chartYScale(domain: 0 ... traceCeiling(drill))
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: [-120.0, -60.0, 0.0, 60.0, 120.0]) { value in
                AxisGridLine(stroke: Config.axisStyle)
                AxisValueLabel {
                    Text(offsetLabel(value.as(Double.self) ?? 0))
                        .font(DOSTypography.mono(size: 9))
                        .foregroundStyle(AmberTheme.amberDark)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .stride(by: glucoseUnit == .mmolL ? 6 : 100)) { value in
                AxisGridLine(stroke: Config.axisStyle)
                if let glucose = value.as(Double.self), glucose > 0 {
                    AxisValueLabel()
                        .font(DOSTypography.mono(size: 9))
                }
            }
        }
        .frame(height: Config.traceChartHeight)
        .padding(.top, DOSSpacing.xxs)
        .accessibilityLabel("\(drill.days) days of the same hour, \(drill.n) readings")
    }

    private func traceCeiling(_ drill: SameHourDrill) -> Double {
        LabChartMath.yMax(
            floor: glucoseUnit == .mmolL ? 18 : 300,
            plotted: drill.traces.flatMap { $0.points.map { display($0.value) } }
        )
    }

    private func offsetLabel(_ minutes: Double) -> String {
        let hours = Int(minutes / 60)
        if hours == 0 { return PatternCopy.hourLabel(drill?.hour ?? 0) }
        return hours > 0 ? "+\(hours)H" : "−\(abs(hours))H"
    }

    /// mg/dL → the display unit. These are RAW storage values, so converting
    /// here is correct (the chart's own datapoints are already converted — see
    /// the P0 errata on double conversion).
    private func display(_ mgdl: Int) -> Double {
        glucoseUnit == .mmolL ? mgdl.toMmolL() : mgdl.toDouble()
    }

    private func refreshDrill() {
        guard let evidence = store.state.labPatterns, let hour = activeHour else {
            drill = nil
            drillKey = ""
            return
        }

        let key = drillIdentity
        guard key != drillKey else { return }
        drillKey = key
        drill = PatternAnalysis.drill(hour: hour, readings: evidence.readings, days: drillWindowDays)
    }
}
