//
//  SystemAboutCategoryView.swift
//  DOSBTS
//

import SwiftUI

// MARK: - SystemAboutCategoryView

/// Settings hub category: notification housekeeping, data export, version
/// info, and debug tools.
struct SystemAboutCategoryView: View {
    var body: some View {
        List {
            Group {
                DigestReminderSection()
                AboutView()
            }
            .listRowBackground(AmberTheme.dosBlack)
            .listRowSeparatorTint(AmberTheme.borderFaint)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AmberTheme.dosBlack)
        .dosNavigationTitle("System & About")
        .toolbarBackground(AmberTheme.dosBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - DigestReminderSection

/// Daily digest reminder migrated from the dissolved AdditionalSettingsView.
private struct DigestReminderSection: View {
    @EnvironmentObject var store: DirectStore

    var body: some View {
        Section(
            content: {
                VStack(alignment: .leading, spacing: DOSSpacing.xxs) {
                    Toggle("Daily digest reminder", isOn: dailyDigestReminderEnabled).toggleStyle(SwitchToggleStyle(tint: AmberTheme.amber))

                    DatePicker(
                        "Time",
                        selection: dailyDigestReminderTime,
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(!isDigestReminderEnabled)
                    .opacity(isDigestReminderEnabled ? 1 : 0.4)

                    Text("Daily local notification that opens the Daily Digest tab.")
                        .font(DOSTypography.caption)
                        .foregroundStyle(AmberTheme.amber)
                }
                .padding(.vertical, 4)
            },
            header: {
                Label("Notifications", systemImage: "bell.badge").dosHeader()
            }
        )
    }

    private var isDigestReminderEnabled: Bool {
        store.state.dailyDigestReminderHour != nil && store.state.dailyDigestReminderMinute != nil
    }

    private var dailyDigestReminderEnabled: Binding<Bool> {
        Binding(
            get: { store.state.dailyDigestReminderHour != nil && store.state.dailyDigestReminderMinute != nil },
            set: { enabled in
                if enabled {
                    // Default to 8 PM if no prior time stored.
                    let hour = store.state.dailyDigestReminderHour ?? 20
                    let minute = store.state.dailyDigestReminderMinute ?? 0
                    store.dispatch(.setDailyDigestReminderTime(hour: hour, minute: minute))
                } else {
                    store.dispatch(.setDailyDigestReminderTime(hour: nil, minute: nil))
                }
            }
        )
    }

    private var dailyDigestReminderTime: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = store.state.dailyDigestReminderHour ?? 20
                components.minute = store.state.dailyDigestReminderMinute ?? 0
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                store.dispatch(.setDailyDigestReminderTime(hour: components.hour, minute: components.minute))
            }
        )
    }
}
