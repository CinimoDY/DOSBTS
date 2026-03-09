//
//  AISettingsView.swift
//  DOSBTS
//

import SwiftUI

struct AISettingsView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore

    var body: some View {
        Section(
            content: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Anthropic API Key")
                    SecureField("sk-ant-...", text: $apiKeyInput)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            validateAndSave()
                        }
                }

                if store.state.claudeAPIKeyValid {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AmberTheme.cgaGreen)
                        Text("API key configured")
                            .foregroundStyle(AmberTheme.cgaGreen)
                    }
                }

                if let error = validationError {
                    Text(error)
                        .foregroundStyle(AmberTheme.cgaRed)
                        .font(DOSTypography.caption)
                }

                if store.state.claudeAPIKeyValid {
                    Button("Remove API Key", role: .destructive) {
                        store.dispatch(.deleteClaudeAPIKey)
                        store.dispatch(.setClaudeAPIKeyValid(isValid: false))
                        apiKeyInput = ""
                    }
                }
            },
            header: {
                Label("AI settings", systemImage: "brain")
            },
            footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enter your Anthropic API key to enable AI-powered food photo analysis.")
                    Text("Estimated cost: less than $0.01 per analysis (~$0.30/month at 3 meals/day)")
                        .foregroundStyle(AmberTheme.amberDark)
                }
            }
        )

        if store.state.aiConsentFoodPhoto {
            Section(
                content: {
                    HStack {
                        Text("Food photo analysis")
                        Spacer()
                        Text("Allowed")
                            .foregroundStyle(AmberTheme.cgaGreen)
                    }

                    Button("Revoke AI Access", role: .destructive) {
                        store.dispatch(.setAIConsentFoodPhoto(enabled: false))
                    }
                },
                header: {
                    Label("AI consent", systemImage: "hand.raised")
                }
            )
        }
    }

    // MARK: Private

    @State private var apiKeyInput: String = ""
    @State private var validationError: String?

    private func validateAndSave() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        guard key.hasPrefix("sk-ant-"), key.count > 20 else {
            validationError = "Invalid key format. Keys start with sk-ant-"
            return
        }

        validationError = nil

        // Save to Keychain first, then dispatch validation (no key in action)
        try? KeychainService.save(key: ClaudeService.keychainKey, value: key)
        store.dispatch(.validateClaudeAPIKey)
    }
}
