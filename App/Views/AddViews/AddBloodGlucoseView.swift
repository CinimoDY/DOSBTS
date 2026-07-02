//
//  AddBloodGlucoseView.swift
//  DOSBTSApp
//
//  Created by Reimar Metzen on 07.01.23.
//

import SwiftUI

struct AddBloodGlucoseView: View {
    @Environment(\.dismiss) var dismiss

    @State var time: Date = .init()
    // Bound in display units (DMNC-796 KTD-9): mg/dL for mgdL users,
    // mmol/L for mmolL users; converted back to Int mg/dL on Add.
    @State private var displayValue: Double?

    var glucoseUnit: GlucoseUnit
    var addCallback: (_ time: Date, _ value: Int) -> Void

    var body: some View {
        NavigationStack {
            HStack {
                Form {
                    Section {
                        HStack {
                            DatePicker(
                                "Time",
                                selection: $time,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                        }

                        StepperField(
                            title: LocalizedString("Glucose"),
                            value: $displayValue,
                            step: glucoseUnit == .mmolL ? 0.1 : 1,
                            range: Self.displayRange(for: glucoseUnit),
                            unit: glucoseUnit.localizedDescription
                        )
                    }
                    .listRowBackground(AmberTheme.dosBlack)
                    .listRowSeparatorTint(AmberTheme.borderFaint)
                }
                .scrollContentBackground(.hidden)
                .background(AmberTheme.dosBlack.ignoresSafeArea())
            }
            .dosNavigationTitle("Blood glucose")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        guard let mgdL = enteredMgdL else { return }
                        addCallback(time, mgdL)
                        dismiss()
                    }
                    .disabled(enteredMgdL == nil)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if displayValue == nil {
                    // Seed at 1 decimal for mmol/L so the stored value matches
                    // the displayed value exactly (5.6, not 5.55).
                    displayValue = glucoseUnit == .mmolL ? (100.toMmolL() * 10).rounded() / 10 : 100
                }
            }
        }
    }

    // MARK: - Conversion (unit-tested)

    private var enteredMgdL: Int? {
        Self.mgdLValue(fromDisplay: displayValue, glucoseUnit: glucoseUnit)
    }

    /// Entry bounds in display units: 40–500 mg/dL, converted for mmol/L.
    /// Used to clamp the stepper buttons.
    static func displayRange(for glucoseUnit: GlucoseUnit) -> ClosedRange<Double> {
        glucoseUnit == .mmolL ? 40.toMmolL()...500.toMmolL() : 40...500
    }

    /// Display-unit value → stored Int mg/dL. Nil when the field is empty
    /// or out of the entry bounds. mmol/L validates AFTER conversion with a
    /// one-step tolerance clamp, so typing the app's own displayed bounds
    /// ("2.2" / "27.8" — the 1-decimal renderings of 40/500 mg/dL) is
    /// accepted rather than silently rejected by the exact converted range.
    static func mgdLValue(fromDisplay displayValue: Double?, glucoseUnit: GlucoseUnit) -> Int? {
        guard let displayValue else { return nil }

        if glucoseUnit == .mmolL {
            guard let mgdL = displayValue.toMgdl(), (39...501).contains(mgdL) else { return nil }
            return min(max(mgdL, 40), 500)
        }

        let mgdL = Int(displayValue.rounded())
        guard (40...500).contains(mgdL) else { return nil }
        return mgdL
    }
}
