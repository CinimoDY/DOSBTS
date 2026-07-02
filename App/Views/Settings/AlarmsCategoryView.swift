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
            .listRowSeparatorTint(AmberTheme.borderFaint)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AmberTheme.dosBlack)
        .dosNavigationTitle("Alarms & Alerts")
        .toolbarBackground(AmberTheme.dosBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
