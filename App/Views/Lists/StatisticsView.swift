//
//  Statistics.swift
//  DOSBTSApp
//
//  Created by Reimar Metzen on 07.01.23.
//

import SwiftUI

struct SelectedDatePager: View {
    @EnvironmentObject var store: DirectStore

    var body: some View {
        HStack {
            Button(action: {
                setSelectedDate(addDays: -1)
            }, label: {
                Image(systemName: "arrowshape.turn.up.backward")
            }).opacity((store.state.selectedDate ?? Date()).startOfDay > store.state.minSelectedDate.startOfDay ? 0.5 : 0)

            Group {
                if let selectedDate = store.state.selectedDate {
                    Text(verbatim: selectedDate.toLocalDate())
                } else {
                    Text("\(DirectConfig.lastChartHours.description) hours")
                }
            }
            .monospacedDigit()
            .padding(.horizontal)
            .onTapGesture {
                store.dispatch(.setSelectedDate(selectedDate: nil))
            }

            Button(action: {
                setSelectedDate(addDays: +1)
            }, label: {
                Image(systemName: "arrowshape.turn.up.forward")
            }).opacity(store.state.selectedDate == nil ? 0 : 0.5)
        }
    }

    private func setSelectedDate(addDays: Int) {
        store.dispatch(.setSelectedDate(selectedDate: Calendar.current.date(byAdding: .day, value: +addDays, to: store.state.selectedDate ?? Date())))

        DirectNotifications.shared.hapticFeedback()
    }
}

struct StatisticsView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore

    var body: some View {
        Group {
            if store.state.showCelebrations {
                tightControlSection
            }

            statisticsBody
        }
    }

    /// Lifetime tight-control streak count (DMNC-772). Always visible when Celebrations
    /// is on, independent of the statistics date window and the 3-day minimum that
    /// gates the rest of this view.
    @ViewBuilder
    private var tightControlSection: some View {
        Section {
            StatCard(
                label: "TIGHT CONTROL",
                value: "\(store.state.tightControlStreakCount)",
                valueColor: store.state.tightControlStreakCount > 0 ? AmberTheme.cgaGreen : AmberTheme.amberDark,
                help: "2h streaks at \(TightControlConfig.default.bandDescription(glucoseUnit: store.state.glucoseUnit))"
            )
        } header: {
            Label("Tight control", systemImage: "checkmark.seal").dosHeader()
        }
    }

    @ViewBuilder
    private var statisticsBody: some View {
        if let glucoseStatistics = store.state.glucoseStatistics, glucoseStatistics.maxDays >= 3 {
            Section {
                VStack(alignment: .leading, spacing: DOSSpacing.md) {
                    periodPicker(stats: glucoseStatistics)

                    // Hero AVG glucose, mirrors the Overview chart's Statistics tab.
                    if let avg = glucoseStatistics.avg.toInteger() {
                        HeroStatView(
                            value: "\(avg)",
                            unit: store.state.glucoseUnit.localizedDescription,
                            label: "AVERAGE"
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DOSSpacing.xs)
                    }

                    // 2x2 stat grid: GMI · TIR / SD · CV.
                    VStack(spacing: DOSSpacing.sm) {
                        HStack(spacing: DOSSpacing.sm) {
                            StatCard(
                                label: "GMI",
                                value: glucoseStatistics.gmi.asPercent(0.1),
                                help: "≈ A1C"
                            )
                            StatCard(
                                label: "TIR",
                                value: glucoseStatistics.tir.asPercent(),
                                valueColor: tirColor(glucoseStatistics.tir),
                                help: tirHelp(glucoseStatistics.tir)
                            )
                        }
                        HStack(spacing: DOSSpacing.sm) {
                            if let stdev = glucoseStatistics.stdev.toInteger() {
                                StatCard(
                                    label: "SD",
                                    value: stdev.asGlucose(glucoseUnit: store.state.glucoseUnit),
                                    help: store.state.glucoseUnit.localizedDescription
                                )
                            } else {
                                StatCard(label: "SD", value: "—")
                            }
                            StatCard(
                                label: "CV",
                                value: glucoseStatistics.cv.asPercent(),
                                valueColor: glucoseStatistics.cv <= 33 ? AmberTheme.cgaGreen : AmberTheme.amber,
                                help: glucoseStatistics.cv <= 33 ? "Stable" : "Variable"
                            )
                        }
                    }

                    // Distribution row: stacked TBR/TIR/TAR bar + numeric breakdown.
                    VStack(spacing: DOSSpacing.sm) {
                        StackedTIRBar(
                            tbr: glucoseStatistics.tbr,
                            tir: glucoseStatistics.tir,
                            tar: glucoseStatistics.tar
                        )
                        TIRBreakdownRow(
                            tbr: glucoseStatistics.tbr,
                            tir: glucoseStatistics.tir,
                            tar: glucoseStatistics.tar
                        )
                    }

                    // Target range + period footer.
                    VStack(spacing: 4) {
                        Text("TARGET \(store.state.alarmLow)–\(store.state.alarmHigh) \(store.state.glucoseUnit.localizedDescription.uppercased())")
                            .font(DOSTypography.mono(size: 10))
                            .foregroundStyle(AmberTheme.textFaint)
                        Text("\(glucoseStatistics.readings) readings · \(glucoseStatistics.days) of \(glucoseStatistics.maxDays) days")
                            .font(DOSTypography.caption)
                            .foregroundStyle(AmberTheme.amber)
                    }
                    .frame(maxWidth: .infinity)

                    if store.state.showAnnotations {
                        annotationLegend(stats: glucoseStatistics)
                    }
                }
                .padding(.vertical, DOSSpacing.xs)
                .onTapGesture(count: 2) {
                    store.dispatch(.setShowAnnotations(showAnnotations: !store.state.showAnnotations))
                }
            } header: {
                Label("Statistics (\(glucoseStatistics.days.description) days)", systemImage: "lightbulb").dosHeader()
            } footer: {
                Text("Double-tap to toggle annotations.")
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.borderStrong)
            }

            UsageSection(stats: glucoseStatistics)
        }
    }

    // MARK: Private

    /// Period chips (3d / 7d / 30d / 90d) — kept above the hero so users can change scope.
    @ViewBuilder
    private func periodPicker(stats: GlucoseStatistics) -> some View {
        HStack(spacing: DOSSpacing.sm) {
            Text("PERIOD")
                .font(DOSTypography.microLabel)
                .tracking(0.6)
                .foregroundStyle(AmberTheme.amberDark)

            Spacer()

            ForEach(Config.chartLevels, id: \.days) { level in
                Button(action: {
                    DirectNotifications.shared.hapticFeedback()
                    store.dispatch(.setStatisticsDays(days: level.days))
                }) {
                    Text(level.name)
                        .font(DOSTypography.mono(size: 11, weight: isSelectedChartLevel(days: level.days) ? .bold : .regular))
                        .foregroundStyle(isSelectedChartLevel(days: level.days) ? AmberTheme.inkOnAmber : AmberTheme.amber)
                        .padding(.horizontal, DOSSpacing.sm)
                        .padding(.vertical, DOSSpacing.xxs)
                        .background(
                            Rectangle()
                                .fill(isSelectedChartLevel(days: level.days) ? AmberTheme.amber : Color.clear)
                        )
                        .overlay(
                            Rectangle()
                                .stroke(AmberTheme.amberDark, lineWidth: 1)
                        )
                }
                .disabled(level.days > stats.maxDays)
                .opacity(level.days > stats.maxDays ? 0.4 : 1)
                .buttonStyle(.plain)
            }
        }
    }

    /// Annotation legend (visible only when `showAnnotations` is on). Plain
    /// caption text; no separate cards. Mirrors the long-form descriptions
    /// the previous version put inline against each row.
    @ViewBuilder
    private func annotationLegend(stats: GlucoseStatistics) -> some View {
        VStack(alignment: .leading, spacing: DOSSpacing.sm) {
            annotation(label: "GMI", text: "Glucose Management Indicator. Replaces \"estimated HbA1c\" for users on continuous glucose monitoring.")
            annotation(label: "TIR", text: "Time in Range — % of time spent in the target glucose range \(store.state.alarmLow.asGlucose(glucoseUnit: store.state.glucoseUnit))–\(store.state.alarmHigh.asGlucose(glucoseUnit: store.state.glucoseUnit, withUnit: true)).")
            annotation(label: "SD", text: "Standard Deviation — spread of readings around the average. Lower SD = steadier glucose.")
            annotation(label: "CV", text: "Coefficient of Variation = SD ÷ mean. Most experts target ≤33% as \"stable\".")
        }
        .padding(.top, DOSSpacing.xs)
    }

    private func annotation(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(DOSTypography.mono(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(AmberTheme.amber)
            Text(text)
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.amberMuted)
        }
    }

    private enum Config {
        static let chartLevels: [ChartLevel] = [
            ChartLevel(days: 3, name: "3d"),
            ChartLevel(days: 7, name: "7d"),
            ChartLevel(days: 30, name: "30d"),
            ChartLevel(days: 90, name: "90d")
        ]
    }

    private var chartLevel: ChartLevel? {
        return Config.chartLevels.first(where: { $0.days == store.state.statisticsDays }) ?? Config.chartLevels.first
    }

    private func isSelectedChartLevel(days: Int) -> Bool {
        if let chartLevel = chartLevel, chartLevel.days == days {
            return true
        }
        return false
    }
}

// MARK: - ChartLevel

private struct ChartLevel {
    let days: Int
    let name: String
}

// MARK: - UsageSection

struct UsageSection: View {
    @EnvironmentObject var store: DirectStore

    let stats: GlucoseStatistics

    var body: some View {
        Section {
            HStack(spacing: DOSSpacing.sm) {
                if let viewsPerDay {
                    StatCard(label: "VIEWS / DAY", value: "\(viewsPerDay)")
                }
                StatCard(label: "TOTAL VIEWS", value: "\(store.state.appOpenCount)")
                StatCard(
                    label: "SENSOR UPTIME",
                    value: sensorUptimeLabel,
                    valueColor: sensorUptimeColor
                )
            }
            .padding(.vertical, DOSSpacing.xs)
        } header: {
            Label("Usage", systemImage: "waveform.path.ecg.rectangle").dosHeader()
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit()
        }
    }

    /// Views-per-day averaged from `appOpenCount` over the days since first
    /// tracking began. Returns nil if tracking hasn't started yet.
    private var viewsPerDay: Int? {
        guard let firstRecordedAt = store.state.appOpenCountFirstRecordedAt else { return nil }
        let elapsed = Date().timeIntervalSince(firstRecordedAt)
        let days = max(elapsed / 86_400, 1)
        return Int((Double(store.state.appOpenCount) / days).rounded())
    }

    /// Sensor uptime over the current `statisticsDays` window — actual readings
    /// vs. expected at one-per-minute. Clamped to 0–100%.
    private var sensorUptimeLabel: String {
        let actual = Double(stats.readings)
        let windowDays = max(Double(store.state.statisticsDays), 1)
        let interval = max(Double(store.state.sensorInterval), 1)
        let expected = windowDays * 24.0 * 60.0 / interval
        guard expected > 0 else { return "—" }
        let pct = min(max(actual / expected * 100.0, 0), 100)
        return "\(Int(pct.rounded()))%"
    }

    private var sensorUptimeColor: Color {
        let raw = sensorUptimeLabel.replacingOccurrences(of: "%", with: "")
        guard let pct = Int(raw) else { return AmberTheme.amberLight }
        if pct >= 90 { return AmberTheme.cgaGreen }
        if pct >= 70 { return AmberTheme.amber }
        return AmberTheme.cgaRed
    }
}
