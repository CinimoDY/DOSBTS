//
//  OverviewView.swift
//  DOSBTS
//

import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var store: DirectStore
    @EnvironmentObject var sheets: SheetCoordinator

    var body: some View {
        VStack(spacing: 0) {
            GlucoseView()

            SensorLineView()

            // Treatment countdown banner (between sensor line and chart toolbar)
            if store.state.treatmentCycleActive {
                TreatmentBannerView()
            }

            ChartReportTypeRow()

            if !store.state.sensorGlucoseValues.isEmpty || !store.state.bloodGlucoseValues.isEmpty {
                ChartView(
                    selectedReportType: store.state.selectedReportType,
                    onTapMarkerGroup: { group in
                        sheets.present(.entryGroupReadOverlay(group))
                    }
                )
                .frame(maxHeight: .infinity)

                ChartZoomRow()
            } else {
                Spacer()
            }
        }
        .background(AmberTheme.dosBlack)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GlucoseStatusBar()
        }
    }

}
