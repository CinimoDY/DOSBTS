//
//  GlucoseSettingsView.swift
//  DOSBTS
//

import SwiftUI

// MARK: - GlucoseSettingsView

struct GlucoseSettingsView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore

    var body: some View {
        Section(
            content: {
                Picker("Glucose unit", selection: selectedGlucoseUnit) {
                    Text(GlucoseUnit.mgdL.localizedDescription).tag(GlucoseUnit.mgdL.rawValue)
                    Text(GlucoseUnit.mmolL.localizedDescription).tag(GlucoseUnit.mmolL.rawValue)
                }.pickerStyle(.menu)

                Toggle("Normal glucose notification", isOn: normalGlucoseNotification).toggleStyle(SwitchToggleStyle(tint: AmberTheme.amber))
                Toggle("Alarm glucose notification", isOn: alarmGlucoseNotification).toggleStyle(SwitchToggleStyle(tint: AmberTheme.amber))

                Toggle("Glucose Live Activity", isOn: glucoseLiveActivity).toggleStyle(SwitchToggleStyle(tint: AmberTheme.amber))

                Toggle("Glucose read aloud", isOn: readGlucose).toggleStyle(SwitchToggleStyle(tint: AmberTheme.amber))
            },
            header: {
                Label("Glucose settings", systemImage: "cross.case").dosHeader()
            }
        )
    }

    // MARK: Private

    private var normalGlucoseNotification: Binding<Bool> {
        Binding(
            get: { store.state.normalGlucoseNotification },
            set: { store.dispatch(.setNormalGlucoseNotification(enabled: $0)) }
        )
    }

    private var alarmGlucoseNotification: Binding<Bool> {
        Binding(
            get: { store.state.alarmGlucoseNotification },
            set: { store.dispatch(.setAlarmGlucoseNotification(enabled: $0)) }
        )
    }

    private var glucoseLiveActivity: Binding<Bool> {
        Binding(
            get: { store.state.glucoseLiveActivity },
            set: { store.dispatch(.setGlucoseLiveActivity(enabled: $0)) }
        )
    }

    private var readGlucose: Binding<Bool> {
        Binding(
            get: { store.state.readGlucose },
            set: { store.dispatch(.setReadGlucose(enabled: $0)) }
        )
    }

    private var selectedGlucoseUnit: Binding<String> {
        Binding(
            get: { store.state.glucoseUnit.rawValue },
            set: { store.dispatch(.setGlucoseUnit(unit: GlucoseUnit(rawValue: $0)!)) }
        )
    }
}
