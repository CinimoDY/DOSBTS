//
//  LabMealsView.swift
//  DOSBTS
//
//  LAB: MEALS (DMNC-1500) — the lab chart plus its legend and safety footer.
//  P0 ships the platform: the chart, the instrument cursors, and no overlays.
//  P2 fills the meal overlays and appends its own legend items here.
//

import SwiftUI

struct LabMealsView: View {
    var body: some View {
        VStack(spacing: 0) {
            LabChartView(overlays: ReportType.labMeals.labOverlays)

            LabLegendRow(items: [
                LabLegendItem(glyph: "A→B", label: "MEASURES", color: AmberTheme.amberLight),
                LabLegendItem(glyph: "●", label: "FOLLOW", color: AmberTheme.amber)
            ])

            LabFooter()
        }
    }
}
