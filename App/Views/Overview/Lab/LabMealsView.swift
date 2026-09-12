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
    /// Owned here so the legend and the chart's `◂ N NEW` nub can never disagree
    /// about whether the view is pinned to the newest reading.
    @State private var followStatus: LabFollowStatus = .following

    var body: some View {
        VStack(spacing: 0) {
            LabChartView(
                overlays: ReportType.labMeals.labOverlays,
                followStatus: $followStatus
            )

            LabLegendRow(items: [
                LabLegendItem(glyph: "A→B", label: "MEASURES", color: AmberTheme.amberLight),
                LabLegendItem.follow(followStatus)
            ])

            LabFooter()
        }
    }
}
