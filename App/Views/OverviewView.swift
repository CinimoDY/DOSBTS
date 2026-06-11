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
        // The INSULIN/MEAL quick actions moved to the persistent bottom
        // accessory bar (GlucoseStatusBar) — one button row, same position
        // on every tab, no doubles. The chart expands into the reclaimed
        // space (R9 Phase 2, taken early by user decision).
    }

}
