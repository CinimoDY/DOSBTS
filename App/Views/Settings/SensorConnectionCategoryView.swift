//
//  SensorConnectionCategoryView.swift
//  DOSBTS
//

import SwiftUI

/// Settings hub category: sensor details, transmitter selection, and
/// per-connection configuration.
struct SensorConnectionCategoryView: View {
    var body: some View {
        List {
            Group {
                Section {
                    NavigationLink {
                        SensorDetailView()
                    } label: {
                        Label("Sensor details", systemImage: "sensor.tag.radiowaves.forward.fill")
                    }
                }

                SensorConnectorSettingsView()
                SensorConnectionConfigurationView()
            }
            .listRowBackground(AmberTheme.dosBlack)
            .listRowSeparatorTint(AmberTheme.amberDark.opacity(0.3))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AmberTheme.dosBlack)
        .dosNavigationTitle("Sensor & Connection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AmberTheme.dosBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
