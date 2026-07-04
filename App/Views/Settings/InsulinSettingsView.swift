//
//  InsulinSettingsView.swift
//  DOSBTS
//

import SwiftUI

// MARK: - InsulinSettingsView

struct InsulinSettingsView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore

    var body: some View {
        Section(
            content: {
                Picker("Insulin type", selection: selectedBolusInsulinPreset) {
                    ForEach(InsulinPreset.allCases, id: \.rawValue) { preset in
                        Text(preset.description)
                    }
                }.pickerStyle(.menu)
            },
            header: {
                Label("Bolus insulin", systemImage: "syringe")
            },
            footer: {
                Text("Duration of Insulin Action — how long insulin remains active after injection. Changes apply to all active insulin.")
                    .font(DOSTypography.caption)
            }
        )

        Section(
            content: {
                Stepper(value: selectedBasalDIAMinutes, in: 120...1440, step: 30) {
                    Text(formatDuration(store.state.basalDIAMinutes))
                        .font(DOSTypography.bodySmall)
                }
            },
            header: {
                Label("Basal duration", systemImage: "clock")
            },
            footer: {
                Text("For long-acting basal (Lantus/Tresiba), set to the manufacturer-specified duration.")
                    .font(DOSTypography.caption)
            }
        )

        Section(
            content: {
                Toggle("Show split IOB (meal vs correction)", isOn: selectedShowSplitIOB)
                    .toggleStyle(SwitchToggleStyle(tint: AmberTheme.amber))
            },
            header: {
                Label("Display", systemImage: "eye")
            }
        )

        Section(
            content: {
                NavigationLink {
                    RatioLabView()
                } label: {
                    Text("Ratio Lab")
                        .font(DOSTypography.body)
                }
                if let icr = store.state.confirmedICR {
                    Text("REF \(RatioEstimator.icrLabel(icr))")
                        .font(DOSTypography.caption)
                        .foregroundStyle(AmberTheme.amberDark)
                }
            },
            header: {
                Label("Ratios", systemImage: "function")
            },
            footer: {
                Text("Estimate your insulin-to-carb ratio and correction factor from your own logged data. Reference only.")
                    .font(DOSTypography.caption)
            }
        )
    }

    // MARK: Private

    private var selectedBolusInsulinPreset: Binding<String> {
        Binding(
            get: { store.state.bolusInsulinPreset.rawValue },
            set: {
                if let preset = InsulinPreset(rawValue: $0) {
                    store.dispatch(.setBolusInsulinPreset(preset: preset))
                }
            }
        )
    }

    private var selectedBasalDIAMinutes: Binding<Int> {
        Binding(
            get: { store.state.basalDIAMinutes },
            set: { store.dispatch(.setBasalDIAMinutes(minutes: $0)) }
        )
    }

    private var selectedShowSplitIOB: Binding<Bool> {
        Binding(
            get: { store.state.showSplitIOB },
            set: { store.dispatch(.setShowSplitIOB(enabled: $0)) }
        )
    }

    private func formatDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(String(format: "%02d", mins))m"
    }
}
