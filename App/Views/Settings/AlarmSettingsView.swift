//
//  AlarmSettingsView.swift
//  DOSBTS
//

import SwiftUI

// MARK: - AlarmSettingsView

struct AlarmSettingsView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore

    var body: some View {
        Group {
            daySection
            nightSection
            sleepScheduleSection
            globalSection
        }
    }

    // MARK: Private

    @ViewBuilder
    private var daySection: some View {
        Section(
            content: {
                NumberSelectorView(
                    key: LocalizedString("Lower limit"),
                    value: store.state.dayAlarmLow,
                    step: 5,
                    max: store.state.dayAlarmHigh,
                    displayValue: store.state.dayAlarmLow.asGlucose(glucoseUnit: store.state.glucoseUnit, withUnit: true)
                ) { value in
                    store.dispatch(.setDayAlarmLow(value: value))
                }

                NumberSelectorView(
                    key: LocalizedString("Upper limit"),
                    value: store.state.dayAlarmHigh,
                    step: 5,
                    min: store.state.dayAlarmLow,
                    displayValue: store.state.dayAlarmHigh.asGlucose(glucoseUnit: store.state.glucoseUnit, withUnit: true)
                ) { value in
                    store.dispatch(.setDayAlarmHigh(value: value))
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Volume")
                        Spacer()
                        Text((store.state.dayAlarmVolume * 100).asPercent())
                    }
                    Slider(value: dayAlarmVolume, in: 0...1, step: 0.05)
                }
            },
            header: { Label("Day profile", systemImage: "sun.max") }
        )
    }

    @ViewBuilder
    private var nightSection: some View {
        Section(
            content: {
                NumberSelectorView(
                    key: LocalizedString("Lower limit"),
                    value: store.state.nightAlarmLow,
                    step: 5,
                    max: store.state.nightAlarmHigh,
                    displayValue: store.state.nightAlarmLow.asGlucose(glucoseUnit: store.state.glucoseUnit, withUnit: true)
                ) { value in
                    store.dispatch(.setNightAlarmLow(value: value))
                }

                if store.state.nightAlarmLow < store.state.dayAlarmLow {
                    let delta = store.state.dayAlarmLow - store.state.nightAlarmLow
                    Text("Lows will need to drop \(delta.asGlucose(glucoseUnit: store.state.glucoseUnit, withUnit: true)) further before alarming at night. Less margin to react if you're asleep.")
                        .font(.caption)
                        .foregroundStyle(AmberTheme.amber)
                }

                NumberSelectorView(
                    key: LocalizedString("Upper limit"),
                    value: store.state.nightAlarmHigh,
                    step: 5,
                    min: store.state.nightAlarmLow,
                    displayValue: store.state.nightAlarmHigh.asGlucose(glucoseUnit: store.state.glucoseUnit, withUnit: true)
                ) { value in
                    store.dispatch(.setNightAlarmHigh(value: value))
                }

                if store.state.nightAlarmHigh > store.state.dayAlarmHigh {
                    let delta = store.state.nightAlarmHigh - store.state.dayAlarmHigh
                    Text("Highs will need to rise \(delta.asGlucose(glucoseUnit: store.state.glucoseUnit, withUnit: true)) further before alarming at night.")
                        .font(.caption)
                        .foregroundStyle(AmberTheme.amber)
                }

                // Catch absurdly tight night ranges: night high so close to (or below) the
                // day low that nearly every reading would fire a high alarm at night.
                // Threshold of dayAlarmLow + 30 mg/dL captures the dangerous case while
                // tolerating reasonable conservative ranges (e.g., 100-130 over a 80-180 day).
                if store.state.nightAlarmHigh <= store.state.dayAlarmLow + 30 {
                    Text("Night high is unusually close to your low threshold — most readings will fire a high alarm at night.")
                        .font(.caption)
                        .foregroundStyle(AmberTheme.cgaRed)
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Volume")
                        Spacer()
                        Text((store.state.nightAlarmVolume * 100).asPercent())
                    }
                    Slider(value: nightAlarmVolume, in: 0...1, step: 0.05)
                }
            },
            header: { Label("Night profile", systemImage: "moon.fill") }
        )
    }

    @ViewBuilder
    private var sleepScheduleSection: some View {
        Section(
            content: {
                DatePicker("Start", selection: nightStart, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: nightEnd, displayedComponents: .hourAndMinute)

                if store.state.nightStartHour == store.state.nightEndHour
                    && store.state.nightStartMinute == store.state.nightEndMinute {
                    Text("Night profile inactive — start and end times are equal.")
                        .font(.caption)
                        .foregroundStyle(AmberTheme.amber)
                }
            },
            header: { Label("Sleep schedule", systemImage: "clock") }
        )
    }

    @ViewBuilder
    private var globalSection: some View {
        Section(
            content: {
                Picker("Low glucose alarm", selection: selectedLowGlucoseAlarmSound) {
                    ForEach(NotificationSound.allCases, id: \.rawValue) { info in
                        Text(info.localizedDescription)
                    }
                }.pickerStyle(.menu)

                Picker("High glucose alarm", selection: selectedHighGlucoseAlarmSound) {
                    ForEach(NotificationSound.allCases, id: \.rawValue) { info in
                        Text(info.localizedDescription)
                    }
                }.pickerStyle(.menu)

                Picker("Connection alarm", selection: selectedConnectionAlarmSound) {
                    ForEach(NotificationSound.allCases, id: \.rawValue) { info in
                        Text(info.localizedDescription)
                    }
                }.pickerStyle(.menu)

                Picker("Wearing time alarm", selection: selectedExpiringAlarmSound) {
                    ForEach(NotificationSound.allCases, id: \.rawValue) { info in
                        Text(info.localizedDescription)
                    }
                }.pickerStyle(.menu)

                Text("Previews play at day volume.")
                    .font(.caption)
                    .foregroundStyle(AmberTheme.amber)

                Toggle("Ignore mute", isOn: ignoreMute).toggleStyle(SwitchToggleStyle(tint: AmberTheme.amber))

                Picker("Treatment recheck", selection: selectedHypoTreatmentWaitMinutes) {
                    ForEach([10, 15, 20, 25, 30], id: \.self) { minutes in
                        Text("\(minutes) min")
                    }
                }.pickerStyle(.menu)

                Toggle("Predictive low alarm", isOn: showPredictiveLowAlarm)
                    .toggleStyle(SwitchToggleStyle(tint: AmberTheme.amber))

                Toggle("Celebrations", isOn: celebrationsEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: AmberTheme.amber))
            },
            header: { Label("Alarm settings", systemImage: "alarm") },
            footer: { Text("Predictive low alarm: warns before glucose is predicted to drop below your low threshold.\nCelebrations: a toast, sound, and lifetime count for tight-control streaks (2+ hours in range). Silent during night hours.") }
        )
    }

    // MARK: Bindings

    private var ignoreMute: Binding<Bool> {
        Binding(
            get: { store.state.ignoreMute },
            set: { store.dispatch(.setIgnoreMute(enabled: $0)) }
        )
    }

    private var dayAlarmVolume: Binding<Float> {
        Binding(
            get: { store.state.dayAlarmVolume },
            set: {
                store.dispatch(.setDayAlarmVolume(value: $0))

                if DirectNotifications.shared.isPlaying() {
                    DirectNotifications.shared.setVolume(volume: $0)
                } else {
                    DirectNotifications.shared.testSound(sound: .alarm, volume: $0)
                }
            }
        )
    }

    private var nightAlarmVolume: Binding<Float> {
        Binding(
            get: { store.state.nightAlarmVolume },
            set: {
                store.dispatch(.setNightAlarmVolume(value: $0))

                if DirectNotifications.shared.isPlaying() {
                    DirectNotifications.shared.setVolume(volume: $0)
                } else {
                    DirectNotifications.shared.testSound(sound: .alarm, volume: $0)
                }
            }
        )
    }

    private var nightStart: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = store.state.nightStartHour
                components.minute = store.state.nightStartMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: {
                let comps = Calendar.current.dateComponents([.hour, .minute], from: $0)
                store.dispatch(.setNightScheduleStart(hour: comps.hour ?? 22, minute: comps.minute ?? 0))
            }
        )
    }

    private var nightEnd: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = store.state.nightEndHour
                components.minute = store.state.nightEndMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: {
                let comps = Calendar.current.dateComponents([.hour, .minute], from: $0)
                store.dispatch(.setNightScheduleEnd(hour: comps.hour ?? 7, minute: comps.minute ?? 0))
            }
        )
    }

    private var showPredictiveLowAlarm: Binding<Bool> {
        Binding(
            get: { store.state.showPredictiveLowAlarm },
            set: { store.dispatch(.setShowPredictiveLowAlarm(enabled: $0)) }
        )
    }

    private var celebrationsEnabled: Binding<Bool> {
        Binding(
            get: { store.state.showCelebrations },
            set: { store.dispatch(.setShowCelebrations(enabled: $0)) }
        )
    }

    private var selectedHypoTreatmentWaitMinutes: Binding<Int> {
        Binding(
            get: { store.state.hypoTreatmentWaitMinutes },
            set: { store.dispatch(.setHypoTreatmentWaitMinutes(minutes: $0)) }
        )
    }

    private var selectedLowGlucoseAlarmSound: Binding<String> {
        Binding(
            get: { store.state.lowGlucoseAlarmSound.rawValue },
            set: {
                let sound = NotificationSound(rawValue: $0)!

                store.dispatch(.setLowGlucoseAlarmSound(sound: sound))
                DirectNotifications.shared.testSound(sound: sound, volume: store.state.dayAlarmVolume)
            }
        )
    }

    private var selectedHighGlucoseAlarmSound: Binding<String> {
        Binding(
            get: { store.state.highGlucoseAlarmSound.rawValue },
            set: {
                let sound = NotificationSound(rawValue: $0)!

                store.dispatch(.setHighGlucoseAlarmSound(sound: sound))
                DirectNotifications.shared.testSound(sound: sound, volume: store.state.dayAlarmVolume)
            }
        )
    }

    private var selectedConnectionAlarmSound: Binding<String> {
        Binding(
            get: { store.state.connectionAlarmSound.rawValue },
            set: {
                let sound = NotificationSound(rawValue: $0)!

                store.dispatch(.setConnectionAlarmSound(sound: sound))
                DirectNotifications.shared.testSound(sound: sound, volume: store.state.dayAlarmVolume)
            }
        )
    }

    private var selectedExpiringAlarmSound: Binding<String> {
        Binding(
            get: { store.state.expiringAlarmSound.rawValue },
            set: {
                let sound = NotificationSound(rawValue: $0)!

                store.dispatch(.setExpiringAlarmSound(sound: sound))
                DirectNotifications.shared.testSound(sound: sound, volume: store.state.dayAlarmVolume)
            }
        )
    }
}
