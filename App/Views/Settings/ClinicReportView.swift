//
//  ClinicReportView.swift
//  DOSBTSApp
//
//  Clinic-report export screen (DMNC-1304): pick a period, export a clinician-ready
//  PDF or CSV summary via the system share sheet. V1 is deliberately simple — period
//  picker + two export buttons + explainer/disclaimer, no live preview state.
//

import SwiftUI

struct ClinicReportView: View {
    @EnvironmentObject var store: DirectStore
    @State private var period: ReportPeriod = .oneMonth

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DOSSpacing.md) {
                explainerCard
                periodPicker
                exportButtons
                disclaimer
            }
            .padding(.horizontal, DOSSpacing.md)
            .padding(.vertical, DOSSpacing.md)
        }
        .background(AmberTheme.dosBlack)
        .dosNavigationTitle("Clinic Report")
        .toolbarBackground(AmberTheme.dosBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var explainerCard: some View {
        VStack(alignment: .leading, spacing: DOSSpacing.sm) {
            Text("CLINIC REPORT").dosHeader(AmberTheme.cgaCyan)

            Text("Generate a clinician-ready summary of your glucose data over a chosen period, then share it via the system share sheet.")
            Text("Uses the international consensus range (70–180 mg/dL) — not your personal alarm settings — so it stays comparable across reports.")
            Text("Pseudonymous by design: no name or date of birth. Reference only.")
        }
        .font(DOSTypography.bodySmall)
        .foregroundStyle(AmberTheme.amberLight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dosCard(.info)
    }

    private var periodPicker: some View {
        VStack(alignment: .leading, spacing: DOSSpacing.xs) {
            Text("PERIOD").dosHeader()
            HStack(spacing: DOSSpacing.xs) {
                ForEach(ReportPeriod.allCases) { candidate in
                    AmberChip(
                        label: candidate.label,
                        variant: .type,
                        tint: AmberTheme.amber,
                        isSelected: period == candidate,
                        action: { period = candidate }
                    )
                }
            }
        }
    }

    private var exportButtons: some View {
        VStack(spacing: DOSSpacing.sm) {
            Button("EXPORT PDF") {
                store.dispatch(.generateClinicReport(days: period.days, format: .pdf))
            }
            .buttonStyle(.dosPrimary)
            .frame(maxWidth: .infinity)

            Button("EXPORT CSV") {
                store.dispatch(.generateClinicReport(days: period.days, format: .csv))
            }
            .buttonStyle(.dosGhost)
            .frame(maxWidth: .infinity)
        }
    }

    private var disclaimer: some View {
        Text("EDUCATIONAL SUMMARY ONLY — NOT A MEDICAL DEVICE. DISCUSS ALL VALUES WITH YOUR CARE TEAM.")
            .font(DOSTypography.caption)
            .foregroundStyle(AmberTheme.amberDark)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DOSSpacing.xs)
    }
}
