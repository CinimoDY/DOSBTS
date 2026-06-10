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
        NavigationView {
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
                }
            }
            .navigationTitle("Blood glucose")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        guard let mgdL = Self.mgdLValue(fromDisplay: displayValue, glucoseUnit: glucoseUnit) else { return }
                        addCallback(time, mgdL)
                        dismiss()
                    }
                    .disabled(Self.mgdLValue(fromDisplay: displayValue, glucoseUnit: glucoseUnit) == nil)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if displayValue == nil {
                    displayValue = glucoseUnit == .mmolL ? 100.toMmolL() : 100
                }
            }
        }
    }

    // MARK: - Conversion (unit-tested)

    /// Entry bounds in display units: 40–500 mg/dL, converted for mmol/L.
    static func displayRange(for glucoseUnit: GlucoseUnit) -> ClosedRange<Double> {
        glucoseUnit == .mmolL ? 40.toMmolL()...500.toMmolL() : 40...500
    }

    /// Display-unit value → stored Int mg/dL. Nil when the field is empty
    /// or out of the entry bounds.
    static func mgdLValue(fromDisplay displayValue: Double?, glucoseUnit: GlucoseUnit) -> Int? {
        guard let displayValue else { return nil }
        guard displayRange(for: glucoseUnit).contains(displayValue) else { return nil }

        if glucoseUnit == .mmolL {
            return displayValue.toMgdl()
        }
        return Int(displayValue.rounded())
    }
}
