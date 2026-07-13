//
//  GlucoseDisplayCategoryView.swift
//  DOSBTS
//

import SwiftUI

// MARK: - GlucoseDisplayCategoryView

/// Settings hub category: glucose unit and output options, chart/screen
/// display preferences, and sensor calibration.
struct GlucoseDisplayCategoryView: View {
    var body: some View {
        List {
            Group {
                GlucoseSettingsView()
                DisplaySettingsSection()
                ClinicReportSection()
                CalibrationSettingsView()
            }
            .listRowBackground(AmberTheme.dosBlack)
            .listRowSeparatorTint(AmberTheme.borderFaint)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AmberTheme.dosBlack)
        .dosNavigationTitle("Glucose & Display")
        .toolbarBackground(AmberTheme.dosBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - ClinicReportSection

/// Entry point to the clinic-visit report export (DMNC-1304).
private struct ClinicReportSection: View {
    var body: some View {
        Section(
            content: {
                NavigationLink {
                    ClinicReportView()
                } label: {
                    Text("Clinic Report")
                        .font(DOSTypography.body)
                }
            },
            header: {
                Label("Reports", systemImage: "doc.text").dosHeader()
            },
            footer: {
                Text("Generate a clinician-ready PDF or CSV summary over 14 / 30 / 90 days. Reference only.")
                    .font(DOSTypography.caption)
            }
        )
    }
}

// MARK: - DisplaySettingsSection

/// Display preferences migrated from the dissolved AdditionalSettingsView.
private struct DisplaySettingsSection: View {
    @EnvironmentObject var store: DirectStore

    var body: some View {
        Section(
            content: {
                if DirectConfig.showSmoothedGlucose {
                    Toggle("Show smoothed glucose", isOn: showSmoothedGlucose).toggleStyle(SwitchToggleStyle(tint: AmberTheme.amber))
                }

                Toggle("CRT scanline overlay", isOn: showScanlines).toggleStyle(SwitchToggleStyle(tint: AmberTheme.amber))

                VStack(alignment: .leading, spacing: DOSSpacing.xxs) {
                    Toggle("Keep screen awake", isOn: preventScreenLock).toggleStyle(SwitchToggleStyle(tint: AmberTheme.amber))
                    Text("Prevents the device from auto-locking while monitoring. Resets automatically when the app is backgrounded.")
                        .font(DOSTypography.caption)
                        .foregroundStyle(AmberTheme.amber)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: DOSSpacing.xxs) {
                    Text("Chart event markers")
                    Picker("Chart event markers", selection: markerLanePosition) {
                        ForEach(MarkerLanePosition.allCases) { position in
                            Text(position.displayLabel).tag(position)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Where the meal/insulin/exercise icons sit relative to the glucose chart.")
                        .font(DOSTypography.caption)
                        .foregroundStyle(AmberTheme.amber)
                }
                .padding(.vertical, 4)
            },
            header: {
                Label("Display", systemImage: "display").dosHeader()
            }
        )
    }

    private var showSmoothedGlucose: Binding<Bool> {
        Binding(
            get: { store.state.showSmoothedGlucose },
            set: { store.dispatch(.setShowSmoothedGlucose(enabled: $0)) }
        )
    }

    private var showScanlines: Binding<Bool> {
        Binding(
            get: { store.state.showScanlines },
            set: { store.dispatch(.setShowScanlines(enabled: $0)) }
        )
    }

    private var preventScreenLock: Binding<Bool> {
        Binding(
            get: { store.state.preventScreenLock },
            set: { store.dispatch(.setPreventScreenLock(enabled: $0)) }
        )
    }

    private var markerLanePosition: Binding<MarkerLanePosition> {
        Binding(
            get: { store.state.markerLanePosition },
            set: { store.dispatch(.setMarkerLanePosition(position: $0)) }
        )
    }
}
