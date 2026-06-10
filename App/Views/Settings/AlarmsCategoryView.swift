//
//  AlarmsCategoryView.swift
//  DOSBTS
//

import SwiftUI

/// Settings hub category: alarm thresholds, sounds, day/night profiles, and
/// the Bellman assistive alarm transceiver.
struct AlarmsCategoryView: View {
    var body: some View {
        List {
            Group {
                AlarmSettingsView()
                BellmanSettingsView()
            }
            .listRowBackground(AmberTheme.dosBlack)
            .listRowSeparatorTint(AmberTheme.amberDark.opacity(0.3))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AmberTheme.dosBlack)
        .navigationTitle("Alarms & Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AmberTheme.dosBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
