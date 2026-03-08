//
//  ListView.swift
//  DOSBTS
//

import SwiftUI

// MARK: - ListsView

struct ListsView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore

    var body: some View {
        List {
            if DirectConfig.showInsulinInput, store.state.showInsulinInput {
                Button("Add insulin", action: {
                    showingAddInsulinView = true
                }).sheet(isPresented: $showingAddInsulinView, onDismiss: {
                    showingAddInsulinView = false
                }) {
                    AddInsulinView { start, end, units, insulinType in
                        let insulinDelivery = InsulinDelivery(id: UUID(), starts: start, ends: end, units: units, type: insulinType)
                        store.dispatch(.addInsulinDelivery(insulinDeliveryValues: [insulinDelivery]))
                    }
                }
            }

            Button("Add meal", action: {
                showingAddMealView = true
            }).sheet(isPresented: $showingAddMealView, onDismiss: {
                showingAddMealView = false
            }) {
                AddMealView { time, description, carbs in
                    let mealEntry = MealEntry(timestamp: time, mealDescription: description, carbsGrams: carbs)
                    store.dispatch(.addMealEntry(mealEntryValues: [mealEntry]))
                }
            }

            if store.state.claudeAPIKeyValid || store.state.aiConsentFoodPhoto {
                Button(action: {
                    showingFoodPhotoView = true
                }) {
                    Label("Analyze meal with AI", systemImage: "camera.viewfinder")
                }.sheet(isPresented: $showingFoodPhotoView, onDismiss: {
                    showingFoodPhotoView = false
                }) {
                    FoodPhotoAnalysisView()
                        .environmentObject(store)
                }
            }

            Button("Add blood glucose", action: {
                showingAddBloodGlucoseView = true
            }).sheet(isPresented: $showingAddBloodGlucoseView, onDismiss: {
                showingAddBloodGlucoseView = false
            }) {
                AddBloodGlucoseView(glucoseUnit: store.state.glucoseUnit) { time, value in
                    let glucose = BloodGlucose(id: UUID(), timestamp: time, glucoseValue: value)
                    store.dispatch(.addBloodGlucose(glucoseValues: [glucose]))
                }
            }

            SensorGlucoseListView()

            if DirectConfig.bloodGlucoseInput {
                BloodGlucoseListView()
            }

            MealEntryListView()

            if DirectConfig.showInsulinInput, store.state.showInsulinInput {
                InsulinDeliveryListView()
            }

            if DirectConfig.glucoseErrors {
                SensorErrorListView()
            }

            if DirectConfig.glucoseStatistics {
                StatisticsView()
            }
        }.listStyle(.grouped)
    }

    // MARK: Private

    @State private var showingAddInsulinView = false
    @State private var showingAddMealView = false
    @State private var showingFoodPhotoView = false
    @State private var showingAddBloodGlucoseView = false
}
