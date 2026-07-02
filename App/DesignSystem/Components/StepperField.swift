//
//  StepperField.swift
//  DOSBTS
//

import SwiftUI

struct StepperField: View {
    let title: String
    @Binding var value: Double?
    let step: Double
    let range: ClosedRange<Double>
    var unit: String = ""
    var helpText: String? = nil

    @FocusState private var isFocused: Bool
    @State private var editorText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Button {
                    Self.decrement(&value, step: step, range: range)
                } label: {
                    Image(systemName: "minus")
                        .font(DOSTypography.mono(size: 18, weight: .medium))
                        .foregroundStyle(AmberTheme.amber)
                        .frame(width: 60, height: 56)
                        .background(AmberTheme.amber.opacity(0.08))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                ZStack {
                    if isFocused || value == nil {
                        // String-backed editor so every keystroke commits to
                        // the binding immediately. A value:format: TextField
                        // only commits on submit/focus-loss, and the decimal
                        // pad has no submit — a caller reading the binding
                        // from a toolbar button would get the stale value.
                        TextField("", text: $editorText)
                            .multilineTextAlignment(.center)
                            .keyboardType(.decimalPad)
                            .focused($isFocused)
                            .font(DOSTypography.numeral)
                            .foregroundStyle(AmberTheme.amber)
                            .onChange(of: editorText) { _, newText in
                                value = Self.parseEditorValue(newText)
                            }
                            .onChange(of: isFocused) { _, focused in
                                if focused {
                                    editorText = value.map(Self.editorText(for:)) ?? ""
                                }
                            }
                            .onChange(of: value) { _, newValue in
                                // Keep the editor in sync when +/- buttons
                                // change the value while the field is focused.
                                guard isFocused, Self.parseEditorValue(editorText) != newValue else { return }
                                editorText = newValue.map(Self.editorText(for:)) ?? ""
                            }
                    } else if let v = value {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            // Drop the trailing ".0" for whole numbers so the
                            // display matches what the user typed.
                            Text(v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v))
                                .font(DOSTypography.numeral)
                                .foregroundStyle(AmberTheme.amber)
                            if !unit.isEmpty {
                                Text(unit)
                                    .font(DOSTypography.mono(size: 14))
                                    .foregroundStyle(AmberTheme.amberDark)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .contentShape(Rectangle())
                .onTapGesture { isFocused = true }

                Button {
                    Self.increment(&value, step: step, range: range)
                } label: {
                    Image(systemName: "plus")
                        .font(DOSTypography.mono(size: 18, weight: .medium))
                        .foregroundStyle(AmberTheme.amber)
                        .frame(width: 60, height: 56)
                        .background(AmberTheme.amber.opacity(0.08))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(Color.black)
            .overlay(
                Rectangle()
                    .stroke(AmberTheme.amberDark, lineWidth: 1)
            )
            .clipShape(Rectangle())

            if let helpText {
                Text(helpText)
                    .font(DOSTypography.mono(size: 10))
                    .foregroundStyle(AmberTheme.amberDark.opacity(0.7))
            }
        }
    }

    static func increment(_ value: inout Double?, step: Double, range: ClosedRange<Double>) {
        let current = value ?? 0
        value = min(current + step, range.upperBound)
    }

    static func decrement(_ value: inout Double?, step: Double, range: ClosedRange<Double>) {
        let current = value ?? 0
        value = max(current - step, range.lowerBound)
    }

    /// Typed text → value. Accepts both "." and "," as decimal separator
    /// (decimal pad follows locale). Empty/unparseable text = nil.
    static func parseEditorValue(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    /// Value → editor seed text, matching the unfocused display: whole
    /// numbers without ".0", fractional values with up to 2 digits.
    static func editorText(for value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        let two = String(format: "%.2f", value)
        return two.hasSuffix("0") ? String(format: "%.1f", value) : two
    }
}
