//
//  SensorErrorList.swift
//  DOSBTSApp
//

import SwiftUI

struct SensorErrorListView: View {
    /// UserDefaults persistence key for this section's expanded state —
    /// must stay stable across releases (display name may change freely).
    private let sectionKey = "Sensor errors"

    // MARK: Internal

    @EnvironmentObject var store: DirectStore

    var body: some View {
        Group {
            CollapsableSection(
                label: Label("Sensor error values", systemImage: "exclamationmark.triangle"),
                accessory: SelectedDatePager().padding(.trailing),
                sectionName: "Sensor errors",
                count: sensorErrorValues.count,
                collapsed: !store.state.listSectionExpanded[sectionKey, default: false],
                collapsible: !sensorErrorValues.isEmpty,
                onCollapsedChange: { isCollapsed in
                    store.dispatch(.setListSectionExpanded(sectionName: sectionKey, isExpanded: !isCollapsed))
                })
            {
                if !sensorErrorValues.isEmpty {
                    ForEach(sensorErrorValues) { sensorError in
                        HStack(alignment: .top) {
                            Text(verbatim: sensorError.timestamp.toLocalDateTime())
                                .monospacedDigit()

                            Spacer()

                            Text(verbatim: sensorError.error.description).multilineTextAlignment(.trailing)
                        }
                    }.onDelete { offsets in
                        DirectLog.info("onDelete: \(offsets)")

                        let deletables = offsets.map { i in
                            (index: i, error: sensorErrorValues[i])
                        }

                        deletables.forEach { delete in
                            sensorErrorValues.remove(at: delete.index)
                            store.dispatch(.deleteSensorError(error: delete.error))
                        }
                    }
                }
            }
        }
        .listStyle(.grouped)
        .onAppear {
            DirectLog.info("onAppear")
            self.sensorErrorValues = store.state.sensorErrorValues.reversed()
        }
        .onChange(of: store.state.sensorErrorValues) { _, errorValues in
            DirectLog.info("onChange")
            self.sensorErrorValues = errorValues.reversed()
        }
    }

    // MARK: Private

    @State private var sensorErrorValues: [SensorError] = []
}
