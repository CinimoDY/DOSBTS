//
//  ChartToolbar.swift
//  DOSBTS
//

import SwiftUI

// MARK: - Shared visual primitives

/// A tab-like text row with bottom underline, used by both the report-type
/// selector (above the chart) and the time-range / day-window zoom row
/// (below the chart). Both rows share the same font, padding, and accent
/// treatment so the chart sits in a visually balanced sandwich.
private struct ChartTabButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(isSelected ? DOSTypography.bodySmall.weight(.bold) : DOSTypography.bodySmall)
                .foregroundStyle(isSelected ? AmberTheme.amber : AmberTheme.amberDark)
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
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - ChartReportTypeRow

/// Top selector: GLUCOSE · TIME IN RANGE · STATISTICS. Sits above the chart.
struct ChartReportTypeRow: View {
    @EnvironmentObject var store: DirectStore

    var body: some View {
        HStack(spacing: DOSSpacing.md) {
            ForEach(ReportType.allCases, id: \.self) { type in
                ChartTabButton(
                    label: type.label,
                    isSelected: store.state.selectedReportType == type,
                    action: { store.dispatch(.setSelectedReportType(reportType: type)) }
                )
            }
        }
        .padding(.vertical, DOSSpacing.xs)
        .background(AmberTheme.dosBlack)
        .onAppear(perform: normaliseDaysIfNeeded)
        .onChange(of: store.state.selectedReportType) { normaliseDaysIfNeeded() }
    }

    /// When the user switches to TIR or STATISTICS and the persisted `statisticsDays`
    /// is not one of the day chips exposed by `ChartZoomRow`, bump it to `30d` so a
    /// chip always reflects the active aggregation window.
    private func normaliseDaysIfNeeded() {
        guard store.state.selectedReportType != .glucose else { return }
        let validDays: Set<Int> = Set(DaysZoom.allCases.map(\.days))
        guard !validDays.contains(store.state.statisticsDays) else { return }
        store.dispatch(.setStatisticsDays(days: 30))
    }
}

// MARK: - ChartZoomRow

/// Bottom selector: hours zoom (3h · 6h · 12h · 24h) for the GLUCOSE tab,
/// or day window (7d · 30d · 90d · ALL) for TIME IN RANGE / STATISTICS.
/// Sits below the chart for natural reading order: pick a view, see the
/// chart, then pick a window.
struct ChartZoomRow: View {
    @EnvironmentObject var store: DirectStore

    var body: some View {
        Group {
            switch store.state.selectedReportType {
            case .glucose:
                hoursRow
            case .timeInRange, .statistics:
                daysRow
            }
        }
        .padding(.vertical, DOSSpacing.xs)
        .background(AmberTheme.dosBlack)
    }

    private var hoursRow: some View {
        HStack(spacing: DOSSpacing.md) {
            ForEach(HoursZoom.allCases, id: \.self) { zoom in
                ChartTabButton(
                    label: zoom.label,
                    isSelected: store.state.chartZoomLevel == zoom.level,
                    action: { store.dispatch(.setChartZoomLevel(level: zoom.level)) }
                )
            }
        }
    }

    private var daysRow: some View {
        HStack(spacing: DOSSpacing.md) {
            ForEach(DaysZoom.allCases, id: \.self) { zoom in
                ChartTabButton(
                    label: zoom.label,
                    isSelected: store.state.statisticsDays == zoom.days,
                    action: { store.dispatch(.setStatisticsDays(days: zoom.days)) }
                )
            }
        }
    }
}

// MARK: - HoursZoom

private enum HoursZoom: CaseIterable {
    case three, six, twelve, twentyFour

    var level: Int {
        switch self {
        case .three: return 3
        case .six: return 6
        case .twelve: return 12
        case .twentyFour: return 24
        }
    }

    var label: String { "\(level)h" }
}

// MARK: - DaysZoom

private enum DaysZoom: CaseIterable {
    case seven, thirty, ninety, all

    /// Sentinel for "All" — large enough that the stats SQL window covers every available reading.
    static let allDays = 9999

    var days: Int {
        switch self {
        case .seven: return 7
        case .thirty: return 30
        case .ninety: return 90
        case .all: return DaysZoom.allDays
        }
    }

    var label: String {
        switch self {
        case .seven: return "7d"
        case .thirty: return "30d"
        case .ninety: return "90d"
        case .all: return "ALL"
        }
    }
}

// MARK: - Preview

struct ChartToolbar_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ChartReportTypeRow()
            Spacer()
            ChartZoomRow()
        }
        .background(AmberTheme.dosBlack)
        .preferredColorScheme(.dark)
        .environmentObject(DirectStore(initialState: AppState(), reducer: directReducer, middlewares: []))
    }
}
