//
//  LabCoverageStrip.swift
//  DOSBTS
//
//  Chart Lab P1 (DMNC-1506) — the POST strip.
//
//  The lab's honesty surface: for every stream the night could have drawn, it
//  says whether the data is there, absent, never asked for, or broken. A chart
//  that silently omits a stream teaches the wrong lesson about your own night;
//  this row is what stops that.
//
//  All of the decisions live in `LabCoverage` (pure). This file only paints.
//

import SwiftUI

struct LabCoverageStrip: View {
    @EnvironmentObject var store: DirectStore

    let snapshot: LabWindowSnapshot

    var body: some View {
        HStack(spacing: DOSSpacing.xs) {
            ForEach(LabCoverage.cells(snapshot: snapshot, sensorIntervalMinutes: store.state.sensorInterval)) { cell in
                cellView(cell)
            }
        }
        .font(DOSTypography.microLabel)
        .frame(maxWidth: .infinity)
        .padding(.top, DOSSpacing.xs)
        .padding(.horizontal, DOSSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stream coverage")
    }

    @ViewBuilder
    private func cellView(_ cell: LabCoverageCell) -> some View {
        switch cell.tone {
        case .unavailable:
            // The one actionable state: we have never been allowed to ask.
            Button {
                // Switch to Settings FIRST, then arm the category push — the
                // category is transient nav state, so dispatching it alone from
                // Overview does nothing now and fires a surprise push the next
                // time Settings happens to open (ChangelogDestination's order).
                store.dispatch(.selectView(viewTag: DirectConfig.settingsViewTag))
                store.dispatch(.setSettingsCategory(category: .integrations))
            } label: {
                Text(cell.text)
                    .foregroundStyle(AmberTheme.amberLight)
                    .underline()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(cell.label) unavailable, open Apple Health settings")

        case .loaded:
            Text(cell.text).foregroundStyle(AmberTheme.amber)

        case .empty:
            Text(cell.text).foregroundStyle(AmberTheme.amberDark)

        case .failed:
            Text(cell.text).foregroundStyle(AmberTheme.cgaRed)
        }
    }
}
