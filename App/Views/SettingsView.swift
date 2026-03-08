//
//  SettingsView.swift
//  DOSBTS
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: DirectStore

    var body: some View {
        List {
            SensorConnectorSettingsView()
            SensorConnectionConfigurationView()
            GlucoseSettingsView()
            AlarmSettingsView()
            NightscoutSettingsView()
            AppleExportSettingsView()
            AISettingsView()
            BellmanSettingsView()
            AdditionalSettingsView()
            AboutView()
        }.listStyle(.grouped)
    }
}
