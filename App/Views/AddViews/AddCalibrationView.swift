//
//  AddCalibrationView.swift
//  DOSBTSApp
//
//  Created by Reimar Metzen on 07.01.23.
//

import SwiftUI

struct AddCalibrationView: View {
    @Environment(\.dismiss) var dismiss

    var glucoseSuggestion: Int
    var glucoseUnit: GlucoseUnit
    var addCallback: (_ value: Int) -> Void

    @State private var value: Int

    init(glucoseSuggestion: Int, glucoseUnit: GlucoseUnit, addCallback: @escaping (_ value: Int) -> Void) {
        self.glucoseSuggestion = glucoseSuggestion
        self.glucoseUnit = glucoseUnit
        self.addCallback = addCallback
        _value = State(initialValue: glucoseSuggestion)
    }
    
    var body: some View {
        NavigationStack {
            HStack {
                Form {
                    Section {
                        NumberSelectorView(key: LocalizedString("Glucose"), value: glucoseSuggestion, step: 1, displayValue: value.asGlucose(glucoseUnit: glucoseUnit, withUnit: true)) { value in
                            self.value = value
                        }
                    }
                    .listRowBackground(AmberTheme.dosBlack)
                    .listRowSeparatorTint(AmberTheme.borderFaint)
                }
                .scrollContentBackground(.hidden)
                .background(AmberTheme.dosBlack.ignoresSafeArea())
            }
            .dosNavigationTitle("Calibration")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addCallback(value)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AddCalibrationView2: View {
    @Environment(\.dismiss) var dismiss
    
    @FocusState private var glucoseFocus: Bool
    @State private var glucose: Double?

    var addCallback: (_ value: Double) -> Void
    
    var body: some View {
        NavigationStack {
            HStack {
                Form {
                    Section {
                        HStack {
                            Text("Glucose")

                            TextField("", value: $glucose, format: .number)
                                .textFieldStyle(.automatic)
                                .keyboardType(.numbersAndPunctuation)
                                .focused($glucoseFocus)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .listRowBackground(AmberTheme.dosBlack)
                    .listRowSeparatorTint(AmberTheme.borderFaint)
                }
                .scrollContentBackground(.hidden)
                .background(AmberTheme.dosBlack.ignoresSafeArea())
            }
            .dosNavigationTitle("Calibration")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        if let glucose = glucose {
                            addCallback(glucose)
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }.onAppear {
            // Set the units to be focused when the view opens.
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                self.glucoseFocus = true
            }
        }
    }
}
