//
//  LabPlaceholderView.swift
//  DOSBTS
//
//  Stand-in for the Chart Lab tabs whose surfaces land later (DMNC-1500): P1
//  replaces NIGHT, P3 replaces SWEEP, P4 replaces PATTERNS. Each of those PRs
//  swaps its own arm in ChartView's switch and leaves the others alone.
//

import SwiftUI

struct LabPlaceholderView: View {
    let tab: ReportType

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: DOSSpacing.xs) {
                Text("\(tab.label) — COMING")
                    .font(DOSTypography.bodySmall)
                    .foregroundStyle(AmberTheme.cgaCyan)

                Text(caption)
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.amberDark)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dosCard(.info)
            .padding(DOSSpacing.sm)

            Spacer()

            LabFooter()
        }
    }

    private var caption: String {
        switch tab {
        case .labNight: return "the night made whole, 20:00 → 10:00"
        case .labSweep: return "every meal aligned at t=0"
        case .labPatterns: return "your own 30-day band under today"
        case .labMeals, .glucose, .timeInRange, .statistics: return "an experimental surface"
        }
    }
}
