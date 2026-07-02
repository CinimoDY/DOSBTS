//
//  DOSStateViews.swift
//  DOSBTS
//
//  Shared empty and error state components for the DOS amber vocabulary.
//

import SwiftUI

/// Full-width empty state — use when a data set is genuinely empty.
/// title renders bodyLarge amber; optional detail renders caption amberDark;
/// optional action renders as a ghost DOS button.
struct DOSEmptyState: View {
    let title: String
    var detail: String? = nil
    var action: (label: String, handler: () -> Void)? = nil

    var body: some View {
        VStack(spacing: DOSSpacing.md) {
            Text(title)
                .font(DOSTypography.bodyLarge)
                .foregroundStyle(AmberTheme.amber)
                .multilineTextAlignment(.center)

            if let detail {
                Text(detail)
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.amberDark)
                    .multilineTextAlignment(.center)
            }

            if let action {
                Button(action.label, action: action.handler)
                    .buttonStyle(.dosGhost)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DOSSpacing.md)
    }
}

/// Full-width error state — use when an operation has failed.
/// message renders caption cgaRed; optional retry renders as a ghost DOS button.
struct DOSErrorState: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: DOSSpacing.md) {
            Text(message)
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.cgaRed)
                .multilineTextAlignment(.center)

            if let retry {
                Button("RETRY", action: retry)
                    .buttonStyle(.dosGhost)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DOSSpacing.md)
    }
}
