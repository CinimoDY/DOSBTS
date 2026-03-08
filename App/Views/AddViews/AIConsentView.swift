//
//  AIConsentView.swift
//  DOSBTS
//

import SwiftUI

struct AIConsentView: View {
    @Environment(\.dismiss) var dismiss
    var onConsent: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Food Photo Analysis")
                .font(DOSTypography.displayMedium)
                .foregroundStyle(AmberTheme.amber)

            Text("Your food photo will be sent to **Anthropic (Claude AI)** to estimate nutritional content.")
                .font(DOSTypography.body)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                consentBullet("Only the photo and a text prompt are sent")
                consentBullet("No glucose or health data is included")
                consentBullet("Anthropic does not store your images or use them for model training (Zero Data Retention)")
                consentBullet("Data is transmitted securely via HTTPS/TLS")
                consentBullet("You can revoke access anytime in Settings")
            }
            .font(DOSTypography.caption)
            .padding(.vertical, 8)

            Link("Anthropic Privacy Policy",
                 destination: URL(string: "https://www.anthropic.com/privacy")!)
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.cgaCyan)

            Button(action: {
                onConsent()
                dismiss()
            }) {
                Text("Allow Food Photo Analysis")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AmberTheme.amber)

            Button("Not Now") {
                dismiss()
            }
            .foregroundStyle(AmberTheme.amberDark)
        }
        .padding()
    }

    private func consentBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}")
                .foregroundStyle(AmberTheme.amber)
            Text(text)
                .foregroundStyle(AmberTheme.amberLight)
        }
    }
}
