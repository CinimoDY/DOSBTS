//
//  ChartReportViews.swift
//  DOSBTS
//
//  Non-chart report bodies for the overview report selector (TIME IN RANGE,
//  STATISTICS) plus the drag-selection tooltip overlay. Extracted from
//  ChartView.swift; data comes from store.state.glucoseStatistics.
//

import SwiftUI

// MARK: - TimeInRangeReportView

struct TimeInRangeReportView: View {
    @EnvironmentObject var store: DirectStore

    var body: some View {
        VStack(spacing: DOSSpacing.lg) {
            if let stats = store.state.glucoseStatistics {
                HeroStatView(
                    value: "\(Int(stats.tir))%",
                    label: "TIME IN RANGE",
                    valueColor: tirColor(stats.tir)
                )

                StackedTIRBar(tbr: stats.tbr, tir: stats.tir, tar: stats.tar)
                    .padding(.horizontal, DOSSpacing.md)

                TIRBreakdownRow(tbr: stats.tbr, tir: stats.tir, tar: stats.tar)
                    .padding(.horizontal, DOSSpacing.md)

                VStack(spacing: 4) {
                    Text("TARGET \(store.state.alarmLow)–\(store.state.alarmHigh) \(store.state.glucoseUnit.localizedDescription.uppercased())")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AmberTheme.amberDark.opacity(0.7))
                    Text("\(stats.days) of \(stats.maxDays) days")
                        .font(DOSTypography.caption)
                        .foregroundStyle(AmberTheme.amber)
                }
            } else {
                Text("No statistics available")
                    .font(DOSTypography.bodySmall)
                    .foregroundColor(AmberTheme.amber)
            }
        }
        .padding(.vertical, DOSSpacing.md)
    }
}

// MARK: - StatisticsReportView

struct StatisticsReportView: View {
    @EnvironmentObject var store: DirectStore

    var body: some View {
        VStack(spacing: DOSSpacing.md) {
            if let stats = store.state.glucoseStatistics {
                HeroStatView(
                    value: String(format: "%.0f", stats.avg),
                    unit: store.state.glucoseUnit.localizedDescription,
                    label: "AVERAGE"
                )
                .padding(.bottom, DOSSpacing.xs)

                VStack(spacing: DOSSpacing.sm) {
                    HStack(spacing: DOSSpacing.sm) {
                        StatCard(label: "GMI", value: String(format: "%.1f%%", stats.gmi), help: "≈ A1C")
                        StatCard(
                            label: "TIR",
                            value: String(format: "%.0f%%", stats.tir),
                            valueColor: tirColor(stats.tir),
                            help: tirHelp(stats.tir)
                        )
                    }
                    HStack(spacing: DOSSpacing.sm) {
                        StatCard(
                            label: "SD",
                            value: String(format: "%.1f", stats.stdev),
                            help: store.state.glucoseUnit.localizedDescription
                        )
                        StatCard(
                            label: "CV",
                            value: String(format: "%.1f%%", stats.cv),
                            valueColor: stats.cv <= 33 ? AmberTheme.cgaGreen : AmberTheme.amber,
                            help: stats.cv <= 33 ? "Stable" : "Variable"
                        )
                    }
                }
                .padding(.horizontal, DOSSpacing.md)

                HStack {
                    Text("\(stats.readings) readings")
                    Spacer()
                    Text("\(stats.days) of \(stats.maxDays) days")
                }
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.amber)
                .padding(.horizontal, DOSSpacing.md)
            } else {
                Text("No statistics available")
                    .font(DOSTypography.bodySmall)
                    .foregroundColor(AmberTheme.amber)
            }
        }
        .padding(.vertical, DOSSpacing.md)
    }
}

// MARK: - ChartSelectionTooltip

/// Floating value readout shown while dragging across the glucose chart.
/// Pure presentation — selection state stays in ChartView.
struct ChartSelectionTooltip: View {
    let selectedSmoothSensorPoint: GlucoseDatapoint?
    let selectedRawSensorPoint: GlucoseDatapoint?
    let selectedBloodPoint: GlucoseDatapoint?
    let selectedHeartRate: Int?
    let showRawPoint: Bool
    let showHeartRate: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                if let selectedSensorPoint = selectedSmoothSensorPoint {
                    VStack(alignment: .leading) {
                        Text(selectedSensorPoint.time.toLocalDateTime())
                        Text(selectedSensorPoint.info).bold()
                    }
                    .font(DOSTypography.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AmberTheme.amberLight)
                    .foregroundColor(AmberTheme.dosBlack)
                    .cornerRadius(0)
                }

                if let selectedRawPoint = selectedRawSensorPoint, showRawPoint {
                    VStack(alignment: .leading) {
                        Text(selectedRawPoint.time.toLocalDateTime())
                        Text(selectedRawPoint.info).bold()
                    }
                    .font(DOSTypography.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AmberTheme.amberDark)
                    .foregroundColor(AmberTheme.dosBlack)
                    .cornerRadius(0)
                }
            }

            if let selectedBloodPoint = selectedBloodPoint {
                HStack {
                    Image(systemName: "drop.fill")

                    VStack(alignment: .leading) {
                        Text(selectedBloodPoint.time.toLocalDateTime())
                        Text(selectedBloodPoint.info).bold()
                    }
                }
                .font(DOSTypography.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AmberTheme.cgaRed)
                .foregroundColor(AmberTheme.dosBlack)
                .cornerRadius(0)
            }

            if let hr = selectedHeartRate, showHeartRate {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                    Text("\(hr) bpm").bold()
                }
                .font(DOSTypography.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(AmberTheme.cgaMagenta)
                .foregroundColor(AmberTheme.dosBlack)
                .cornerRadius(0)
            }
        }.opacity(0.75)
    }
}
