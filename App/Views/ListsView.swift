//
//  ListView.swift
//  DOSBTS
//

import SwiftUI

// MARK: - ListsView

struct ListsView: View {
    @EnvironmentObject var store: DirectStore

    var body: some View {
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
        }.listStyle(.grouped)
    }
}
