//
//  SettingsConnectionsView.swift
//  DOSBTS
//

import SwiftUI

// MARK: - SettingsConnectionsView

/// Consolidated index of all external data-sharing and integration surfaces.
/// Each row navigates to the existing settings view wrapped in a focused List
/// so users see a single integration at a time when drilling in from here.
struct SettingsConnectionsView: View {
    @EnvironmentObject var store: DirectStore

    var body: some View {
        List {
            Section {
                ForEach(connections) { connection in
                    NavigationLink {
                        connection.destination
                    } label: {
                        ConnectionRow(connection: connection)
                    }
                }
            } footer: {
                Text("Manage where your glucose data is shared or exported.")
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.amber)
            }
        }
        .listStyle(.grouped)
        .dosNavigationTitle("Integrations")
    }

    // MARK: - Status

    private var connections: [Connection] {
        [
            Connection(
                id: "nightscout",
                name: "Nightscout",
                icon: "icloud.and.arrow.up",
                description: "Share glucose, insulin, and meals with your Nightscout server.",
                status: nightscoutStatus,
                destination: AnyView(
                    List { NightscoutSettingsView() }
                        .listStyle(.grouped)
                        .dosNavigationTitle("Nightscout")
                )
            ),
            Connection(
                id: "apple",
                name: "Apple Health & Calendar",
                icon: "heart.text.square",
                description: "Export glucose to Apple Health and, optionally, to a selected calendar.",
                status: appleStatus,
                destination: AnyView(
                    List { AppleExportSettingsView() }
                        .listStyle(.grouped)
                        .dosNavigationTitle("Apple Health & Calendar")
                )
            ),
            Connection(
                id: "ai",
                name: "AI Features",
                icon: "sparkles",
                description: "Food photo / text analysis and Daily Digest insight via Claude.",
                status: aiStatus,
                destination: AnyView(
                    List { AISettingsView() }
                        .listStyle(.grouped)
                        .dosNavigationTitle("AI Features")
                )
            ),
            Connection(
                id: "healthimport",
                name: "Health Import Sources",
                icon: "square.and.arrow.down",
                description: "Import exercise, heart rate, and nutrition from Apple Health.",
                status: healthImportStatus,
                destination: AnyView(
                    List { HealthImportSourcesView() }
                        .listStyle(.grouped)
                        .dosNavigationTitle("Health Import Sources")
                )
            ),
        ]
    }

    private var nightscoutStatus: ConnectionStatus {
        let urlSet = !store.state.nightscoutURL.isEmpty
        let secretSet = !store.state.nightscoutApiSecret.isEmpty
        if store.state.nightscoutUpload && urlSet && secretSet { return .active }
        if store.state.nightscoutUpload && (!urlSet || !secretSet) { return .error }
        return .inactive
    }

    private var appleStatus: ConnectionStatus {
        if store.state.appleHealthExport || store.state.appleCalendarExport { return .active }
        return .inactive
    }

    private var aiStatus: ConnectionStatus {
        let hasConsent = store.state.aiConsentFoodPhoto || store.state.aiConsentDailyDigest
        if hasConsent && store.state.claudeAPIKeyValid { return .active }
        if hasConsent && !store.state.claudeAPIKeyValid { return .error }
        return .inactive
    }

    private var healthImportStatus: ConnectionStatus {
        store.state.appleHealthImport ? .active : .inactive
    }
}

// MARK: - ConnectionRow

private struct ConnectionRow: View {
    let connection: Connection

    var body: some View {
        HStack(spacing: DOSSpacing.md) {
            Image(systemName: connection.icon)
                .foregroundStyle(AmberTheme.amberDark)
                .frame(width: 24, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DOSSpacing.xs) {
                    Circle()
                        .fill(connection.status.color)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(connection.name)
                        .font(DOSTypography.bodySmall)
                        .foregroundStyle(AmberTheme.amber)
                }
                Text(connection.description)
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.amber)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, DOSSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(connection.name), \(connection.status.accessibilityLabel)")
        .accessibilityHint(connection.description)
    }
}

// MARK: - Connection model

private struct Connection: Identifiable {
    let id: String
    let name: String
    let icon: String
    let description: String
    let status: ConnectionStatus
    let destination: AnyView
}

// MARK: - ConnectionStatus

enum ConnectionStatus {
    case active, inactive, error

    var color: Color {
        switch self {
        case .active: return AmberTheme.cgaGreen
        case .inactive: return AmberTheme.amberDark
        case .error: return AmberTheme.cgaRed
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .active: return "active"
        case .inactive: return "inactive"
        case .error: return "needs configuration"
        }
    }
}
