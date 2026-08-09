//
//  ListView.swift
//  DOSBTS
//

import SwiftUI

// MARK: - ListsView

struct ListsView: View {
    @EnvironmentObject var store: DirectStore
    @EnvironmentObject var sheets: SheetCoordinator
    @State private var showingMigrationHint: Bool = false

    var body: some View {
        // GlucoseFramedTab owns the NavigationStack; passing the root List
        // directly lets the bottom-bar safeAreaInset propagate to pushed
        // detail screens as well as this root.
        GlucoseFramedTab {
            List {
                SensorGlucoseListView()

                if DirectConfig.bloodGlucoseInput {
                    BloodGlucoseListView()
                }

                MealEntryListView()

                // Ungated, unlike the BloodGlucose section above
                // (DirectConfig.bloodGlucoseInput is false).
                JournalNoteListView()

                Section {
                    NavigationLink {
                        FoodImpactView()
                    } label: {
                        Label("Food Impact", systemImage: "chart.bar.doc.horizontal")
                            .font(DOSTypography.body)
                    }
                }

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
            .toolbar {
                if DirectConfig.bloodGlucoseInput {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            // Routes through the app's single presentation
                            // root — a local .sheet here was a second root
                            // (sibling-sheet collision class, R8a).
                            sheets.present(.bloodGlucose)
                        } label: {
                            Image(systemName: "plus")
                                .accessibilityLabel("Add blood glucose")
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        sheets.present(.journalNote)
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .accessibilityLabel("Add note")
                    }
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
