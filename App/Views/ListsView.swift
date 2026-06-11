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
        // Strip sits ABOVE the page title (matching Daily digest), so it
        // wraps the NavigationStack instead of living inside it — nav bars
        // ignore outer safe-area insets, so a sibling VStack is the only
        // placement that puts it on top.
        VStack(spacing: 0) {
            GlucoseTopBar()

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
        .background(AmberTheme.dosBlack)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GlucoseStatusBar()
        }
    }
}
