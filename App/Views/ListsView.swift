//
//  ListView.swift
//  DOSBTS
//

import SwiftUI

// MARK: - ListsView

struct ListsView: View {
    @EnvironmentObject var store: DirectStore
    @State private var showingAddBG: Bool = false
    @State private var showingMigrationHint: Bool = false

    var body: some View {
        NavigationStack {
            List {
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
            }
            .listStyle(.grouped)
            .dosNavigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if DirectConfig.bloodGlucoseInput {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingAddBG = true
                        } label: {
                            Image(systemName: "plus")
                                .accessibilityLabel("Add blood glucose")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddBG) {
                AddBloodGlucoseView(glucoseUnit: store.state.glucoseUnit) { time, value in
                    let glucose = BloodGlucose(id: UUID(), timestamp: time, glucoseValue: value)
                    store.dispatch(.addBloodGlucose(glucoseValues: [glucose]))
                }
            }
            .alert("Blood glucose moved", isPresented: $showingMigrationHint) {
                Button("Got it") {
                    store.dispatch(.setHasSeenBGRelocationHint(seen: true))
                }
            } message: {
                Text("BG entry is now in the Log tab. Tap the + button above to log a new reading.")
            }
            .onAppear {
                if !store.state.hasSeenBGRelocationHint && DirectConfig.bloodGlucoseInput {
                    showingMigrationHint = true
                }
            }
        }
    }
}
