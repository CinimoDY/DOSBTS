//
//  CalendarExportSettings.swift
//  DOSBTS
//

import EventKit
import HealthKit
import SwiftUI

// MARK: - CalendarExportSettingsView

struct AppleExportSettingsView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore

    var body: some View {
        Section(
            content: {
                Toggle("Export to Apple Health", isOn: appleHealthExport).toggleStyle(SwitchToggleStyle(tint: AmberTheme.amber))
                Toggle("Export to Apple Calendar", isOn: appleCalendarExport).toggleStyle(SwitchToggleStyle(tint: AmberTheme.amber))

                Picker("Selected calendar", selection: selectedCalendar) {
                    if store.state.selectedCalendarTarget == nil {
                        Text("Please select")
                    }

                    ForEach(calendars, id: \.self) { cal in
                        Text(cal)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!store.state.appleCalendarExport)
                .opacity(store.state.appleCalendarExport ? 1 : 0.4)
            },
            header: {
                Label("Apple export settings", systemImage: "square.and.arrow.up")
            }
        )

        Section(
            content: {
                Toggle("Import from Apple Health", isOn: appleHealthImport).toggleStyle(SwitchToggleStyle(tint: AmberTheme.amber))

                Group {
                    NavigationLink("Source apps") {
                        HealthImportSourcesView()
                            .environmentObject(store)
                    }

                    Toggle(isOn: showHeartRateOverlay) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("HR overlay on chart")
                                .font(DOSTypography.body)
                            Text("Magenta dashed line + current bpm")
                                .font(DOSTypography.caption)
                                .foregroundStyle(AmberTheme.amberDark)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: AmberTheme.amber))
                }
                .disabled(!store.state.appleHealthImport)
                .opacity(store.state.appleHealthImport ? 1 : 0.4)
            },
            header: {
                Label("Apple import settings", systemImage: "square.and.arrow.down")
            },
            footer: {
                Text("Import nutrition, exercise, and heart rate data from other apps via Apple Health.")
            }
        )
    }

    // MARK: Private

    private var calendars: [String] {
        EKEventStore().calendars(for: .event).map { $0.title }
    }

    private var appleHealthExport: Binding<Bool> {
        Binding(
            get: { store.state.appleHealthExport },
            set: { store.dispatch(.requestAppleHealthAccess(enabled: $0)) }
        )
    }

    private var appleCalendarExport: Binding<Bool> {
        Binding(
            get: { store.state.appleCalendarExport },
            set: { store.dispatch(.requestAppleCalendarAccess(enabled: $0)) }
        )
    }

    private var appleHealthImport: Binding<Bool> {
        Binding(
            get: { store.state.appleHealthImport },
            set: { store.dispatch(.requestAppleHealthImportAccess(enabled: $0)) }
        )
    }

    private var showHeartRateOverlay: Binding<Bool> {
        Binding(
            get: { store.state.showHeartRateOverlay },
            set: { store.dispatch(.setShowHeartRateOverlay(enabled: $0)) }
        )
    }

    private var selectedCalendar: Binding<String> {
        Binding(
            get: { store.state.selectedCalendarTarget ?? LocalizedString("Please select") },
            set: { store.dispatch(.selectCalendarTarget(id: $0)) }
        )
    }
}
