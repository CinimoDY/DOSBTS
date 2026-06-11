//
//  InsulinCategoryView.swift
//  DOSBTS
//

import SwiftUI

// MARK: - InsulinCategoryView

/// Settings hub category: bolus preset, basal duration, IOB display, and
/// insulin entry visibility.
struct InsulinCategoryView: View {
    var body: some View {
        List {
            Group {
                InsulinSettingsView()
                InsulinEntrySection()
            }
            .listRowBackground(AmberTheme.dosBlack)
            .listRowSeparatorTint(AmberTheme.amberDark.opacity(0.3))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AmberTheme.dosBlack)
        .dosNavigationTitle("Insulin")
        .toolbarBackground(AmberTheme.dosBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - InsulinEntrySection

/// Insulin entry toggle migrated from the dissolved AdditionalSettingsView.
private struct InsulinEntrySection: View {
    @EnvironmentObject var store: DirectStore

    var body: some View {
        if DirectConfig.showInsulinInput {
            Section(
                content: {
                    Toggle("Show insulin input", isOn: showInsulinInput).toggleStyle(SwitchToggleStyle(tint: AmberTheme.amber))
                },
                header: {
                    Label("Logging", systemImage: "square.and.pencil")
                }
            )
        }
    }

    private var showInsulinInput: Binding<Bool> {
        Binding(
            get: { store.state.showInsulinInput },
            set: { store.dispatch(.setShowInsulinInput(enabled: $0)) }
        )
    }
}
