//
//  OverviewView.swift
//  DOSBTS
//

import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var store: DirectStore

    @State private var showingAddInsulinView = false
    @State private var showingAddMealView = false
    @State private var showingFoodPhotoView = false
    @State private var showingAddBloodGlucoseView = false

    var body: some View {
        List {
            GlucoseView()
                .listRowSeparator(.hidden)

            QuickActionsSection()

            if !store.state.sensorGlucoseValues.isEmpty || !store.state.bloodGlucoseValues.isEmpty {
                if #available(iOS 16.0, *) {
                    ChartView()
                } else {
                    ChartViewCompatibility()
                }
            }

            ConnectionView()
            SensorView()
        }.listStyle(.grouped)
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private func QuickActionsSection() -> some View {
        Section {
            HStack(spacing: DOSSpacing.sm) {
                // Meal group: MANUAL + PHOTO as one combined button
                HStack(spacing: 1) {
                    QuickActionButton(
                        title: "MANUAL",
                        icon: "fork.knife",
                        action: { showingAddMealView = true }
                    )
                    .sheet(isPresented: $showingAddMealView) {
                        AddMealView { time, description, carbs in
                            let mealEntry = MealEntry(timestamp: time, mealDescription: description, carbsGrams: carbs)
                            store.dispatch(.addMealEntry(mealEntryValues: [mealEntry]))
                        }
                    }

                    if store.state.claudeAPIKeyValid || store.state.aiConsentFoodPhoto {
                        QuickActionButton(
                            title: "PHOTO",
                            icon: "camera.viewfinder",
                            action: { showingFoodPhotoView = true }
                        )
                        .sheet(isPresented: $showingFoodPhotoView) {
                            FoodPhotoAnalysisView()
                                .environmentObject(store)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                if DirectConfig.showInsulinInput, store.state.showInsulinInput {
                    QuickActionButton(
                        title: "INSULIN",
                        icon: "syringe",
                        action: { showingAddInsulinView = true }
                    )
                    .sheet(isPresented: $showingAddInsulinView) {
                        AddInsulinView { start, end, units, insulinType in
                            let insulinDelivery = InsulinDelivery(id: UUID(), starts: start, ends: end, units: units, type: insulinType)
                            store.dispatch(.addInsulinDelivery(insulinDeliveryValues: [insulinDelivery]))
                        }
                    }
                }
            }
            .padding(.horizontal, DOSSpacing.xs)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: DOSSpacing.xs, leading: 0, bottom: DOSSpacing.xs, trailing: 0))

            if DirectConfig.bloodGlucoseInput {
                Button(action: { showingAddBloodGlucoseView = true }) {
                    HStack {
                        Image(systemName: "drop.fill")
                            .font(DOSTypography.caption)
                        Text("Add blood glucose")
                            .font(DOSTypography.bodySmall)
                    }
                    .foregroundColor(AmberTheme.amberDark)
                }
                .sheet(isPresented: $showingAddBloodGlucoseView) {
                    AddBloodGlucoseView(glucoseUnit: store.state.glucoseUnit) { time, value in
                        let glucose = BloodGlucose(id: UUID(), timestamp: time, glucoseValue: value)
                        store.dispatch(.addBloodGlucose(glucoseValues: [glucose]))
                    }
                }
            }
        }
    }
}

// MARK: - Quick Action Button

private struct QuickActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DOSSpacing.xs) {
                Image(systemName: icon)
                    .font(DOSTypography.bodyLarge)
                Text(title)
                    .font(DOSTypography.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DOSSpacing.sm)
        }
        .buttonStyle(DOSButtonStyle(variant: .ghost))
        .frame(maxWidth: .infinity)
    }
}
