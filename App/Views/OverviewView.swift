//
//  OverviewView.swift
//  DOSBTS
//

import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var store: DirectStore
    @EnvironmentObject var sheets: SheetCoordinator

    @State private var selectedReportType: ReportType = .glucose

    var body: some View {
        VStack(spacing: 0) {
            GlucoseView()

            SensorLineView()

            // Treatment countdown banner (between sensor line and chart toolbar)
            if store.state.treatmentCycleActive {
                TreatmentBannerView()
            }

            ChartReportTypeRow(selectedReportType: $selectedReportType)

            if !store.state.sensorGlucoseValues.isEmpty || !store.state.bloodGlucoseValues.isEmpty {
                ChartView(
                    selectedReportType: selectedReportType,
                    onTapMarkerGroup: { group in
                        sheets.present(.entryGroupReadOverlay(group))
                    }
                )
                .frame(maxHeight: .infinity)

                ChartZoomRow(selectedReportType: selectedReportType)
            } else {
                Spacer()
            }
        }
        .background(AmberTheme.dosBlack)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StickyQuickActions()
        }
    }

    // MARK: - Sticky Quick Actions

    @ViewBuilder
    private func StickyQuickActions() -> some View {
        VStack(spacing: 0) {
            Divider()
                .background(AmberTheme.dosBorder)

            HStack(spacing: DOSSpacing.sm) {
                if DirectConfig.showInsulinInput, store.state.showInsulinInput {
                    QuickActionButton(title: "INSULIN", action: { sheets.present(.insulin) }) {
                        Image(systemName: "syringe")
                            .font(DOSTypography.body)
                    }
                }

                QuickActionButton(title: "MEAL", action: { sheets.present(.meal) }) {
                    AppleIcon().frame(width: 16, height: 16)
                }
            }
            .padding(.horizontal, DOSSpacing.md)
            .padding(.vertical, DOSSpacing.xs)
            .background(AmberTheme.dosBlack)
        }
    }
}

// MARK: - Quick Action Button

private struct QuickActionButton<Icon: View>: View {
    let title: String
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            HStack(spacing: DOSSpacing.xs) {
                icon()
                    .frame(height: 16)
                Text(title)
                    .font(DOSTypography.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(DOSButtonStyle(variant: .ghost))
        .frame(maxWidth: .infinity)
    }
}
