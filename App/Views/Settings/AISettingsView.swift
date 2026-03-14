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

        if store.state.claudeAPIKeyValid || store.state.aiConsentFoodPhoto {
            Section(
                content: {
                    HStack {
                        Text("Thumb width")
                        Spacer()
                        TextField("--", value: $thumbWidthInput, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("mm")
                            .font(DOSTypography.caption)
                            .foregroundStyle(AmberTheme.amberDark)
                    }

                    if store.state.thumbCalibrationMM != nil {
                        Button("Clear calibration", role: .destructive) {
                            thumbWidthInput = nil
                            store.dispatch(.setThumbCalibration(widthMM: nil))
                        }
                    }
                },
                header: {
                    Label("Portion size calibration", systemImage: "hand.raised.fingers.spread")
                },
                footer: {
                    Text("Measure the widest part of your thumb at the joint just below the nail. When taking food photos, hold your thumb next to the food for more accurate portion estimates.")
                }
            )
            .onAppear {
                thumbWidthInput = store.state.thumbCalibrationMM
            }
            .onChange(of: thumbWidthInput) { newValue in
                if let mm = newValue, mm > 0, mm < 50 {
                    store.dispatch(.setThumbCalibration(widthMM: mm))
                }
            }
        }

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
    @State private var thumbWidthInput: Double?

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
