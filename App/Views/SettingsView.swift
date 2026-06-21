//
//  SettingsView.swift
//  DOSBTS
//

import SwiftUI

/// Top-level settings hub: six category rows, each pushing a focused
/// sub-screen. Section views live in the category containers under
/// App/Views/Settings/.
struct SettingsView: View {
    @EnvironmentObject var store: DirectStore

    var body: some View {
        // Strip above the page title + bar below — see GlucoseFramedTab.
        GlucoseFramedTab {
            NavigationStack {
            List {
                // Destinations route through categoryView(for:) — the single
                // source of truth shared with the deep-link navigationDestination
                // below, so the two paths can never drift (DMNC-1147 review).
                Group {
                    NavigationLink {
                        categoryView(for: .alarms)
                    } label: {
                        SettingsHubRow(
                            icon: "alarm",
                            title: "Alarms & Alerts",
                            subtitle: "Limits, sounds, day/night profiles, Bellman"
                        )
                    }

                    NavigationLink {
                        categoryView(for: .glucose)
                    } label: {
                        SettingsHubRow(
                            icon: "cross.case",
                            title: "Glucose & Display",
                            subtitle: "Unit, read aloud, chart and screen options, calibration"
                        )
                    }

                    NavigationLink {
                        categoryView(for: .insulin)
                    } label: {
                        SettingsHubRow(
                            icon: "syringe",
                            title: "Insulin",
                            subtitle: "Bolus preset, basal duration, IOB display"
                        )
                    }

                    NavigationLink {
                        categoryView(for: .sensor)
                    } label: {
                        SettingsHubRow(
                            icon: "sensor.tag.radiowaves.forward.fill",
                            title: "Sensor & Connection",
                            subtitle: "Sensor details, transmitter, retrieval interval"
                        )
                    }

                    NavigationLink {
                        categoryView(for: .integrations)
                    } label: {
                        SettingsHubRow(
                            icon: "antenna.radiowaves.left.and.right",
                            title: "Integrations",
                            subtitle: "Nightscout, Apple Health & Calendar, AI features"
                        )
                    }

                    NavigationLink {
                        categoryView(for: .about)
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
            // Programmatic push for changelog deep links (DMNC-1147, KTD6).
            // Coexists with the closure NavigationLinks above (which handle
            // ordinary user taps); this only fires when a deep link sets the
            // category. SwiftUI nils the binding on back-nav, clearing the
            // transient state so a relaunch never re-pushes (KTD6).
            .navigationDestination(item: settingsCategoryBinding) { category in
                categoryView(for: category)
            }
            }
        }
    }

    private var settingsCategoryBinding: Binding<SettingsCategory?> {
        Binding(
            get: { store.state.selectedSettingsCategory },
            set: { store.dispatch(.setSettingsCategory(category: $0)) }
        )
    }

    @ViewBuilder
    private func categoryView(for category: SettingsCategory) -> some View {
        switch category {
        case .alarms: AlarmsCategoryView()
        case .glucose: GlucoseDisplayCategoryView()
        case .insulin: InsulinCategoryView()
        case .sensor: SensorConnectionCategoryView()
        case .integrations: SettingsConnectionsView()
        case .about: SystemAboutCategoryView()
        }
    }
}
