//
//  SettingsHubRow.swift
//  DOSBTS
//

import SwiftUI

/// Row for the top-level settings hub: icon + title + dim one-line summary.
/// Visual vocabulary mirrors ConnectionRow in SettingsConnectionsView.
struct SettingsHubRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: DOSSpacing.md) {
            Image(systemName: icon)
                .foregroundStyle(AmberTheme.amberDark)
                .frame(width: 24, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DOSTypography.bodySmall)
                    .foregroundStyle(AmberTheme.amber)
                Text(subtitle)
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.amber)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, DOSSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}
