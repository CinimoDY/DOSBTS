//
//  SettingsView.swift
//  DOSBTS
//

import SwiftUI

/// Top-level settings hub: six category rows, each pushing a focused
/// sub-screen. Section views live in the category containers under
/// App/Views/Settings/.
struct SettingsView: View {
    var body: some View {
        // Strip above the page title + bar below — see GlucoseFramedTab.
        GlucoseFramedTab {
            NavigationStack {
            List {
                Group {
                    NavigationLink {
                        AlarmsCategoryView()
                    } label: {
                        SettingsHubRow(
                            icon: "alarm",
                            title: "Alarms & Alerts",
                            subtitle: "Limits, sounds, day/night profiles, Bellman"
                        )
                    }

                    NavigationLink {
                        GlucoseDisplayCategoryView()
                    } label: {
                        SettingsHubRow(
                            icon: "cross.case",
                            title: "Glucose & Display",
                            subtitle: "Unit, read aloud, chart and screen options, calibration"
                        )
                    }

                    NavigationLink {
                        InsulinCategoryView()
                    } label: {
                        SettingsHubRow(
                            icon: "syringe",
                            title: "Insulin",
                            subtitle: "Bolus preset, basal duration, IOB display"
                        )
                    }

                    NavigationLink {
                        SensorConnectionCategoryView()
                    } label: {
                        SettingsHubRow(
                            icon: "sensor.tag.radiowaves.forward.fill",
                            title: "Sensor & Connection",
                            subtitle: "Sensor details, transmitter, retrieval interval"
                        )
                    }

                    NavigationLink {
                        SettingsConnectionsView()
                    } label: {
                        SettingsHubRow(
                            icon: "antenna.radiowaves.left.and.right",
                            title: "Integrations",
                            subtitle: "Nightscout, Apple Health & Calendar, AI features"
                        )
                    }

                    NavigationLink {
                        SystemAboutCategoryView()
                    } label: {
                        SettingsHubRow(
                            icon: "info.circle",
                            title: "System & About",
                            subtitle: "Digest reminder, data export, version, debug"
                        )
                    }
                }
                .listRowBackground(AmberTheme.dosBlack)
                .listRowSeparatorTint(AmberTheme.amberDark.opacity(0.3))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AmberTheme.dosBlack)
            .dosNavigationTitle("Settings")
            .toolbarBackground(AmberTheme.dosBlack, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            }
        }
    }
}
