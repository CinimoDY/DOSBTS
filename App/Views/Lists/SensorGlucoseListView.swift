//
//  SensorGlucoseList.swift
//  DOSBTSApp
//

import SwiftUI

struct SensorGlucoseListView: View {
    /// UserDefaults persistence key for this section's expanded state —
    /// must stay stable across releases (display name may change freely).
    private let sectionKey = "CGM"

    // MARK: Internal

    @EnvironmentObject var store: DirectStore
    @EnvironmentObject var loggedEntryToast: LoggedEntryToastController

    var body: some View {
        Group {
            CollapsableSection(
                label: Label("Sensor glucose values", systemImage: "sensor.tag.radiowaves.forward"),
                accessory: SelectedDatePager().padding(.trailing),
                sectionName: "CGM",
                count: sensorGlucoseValues.count,
                collapsed: !store.state.listSectionExpanded[sectionKey, default: false],
                collapsible: !sensorGlucoseValues.isEmpty,
                onCollapsedChange: { isCollapsed in
                    store.dispatch(.setListSectionExpanded(sectionName: sectionKey, isExpanded: !isCollapsed))
                })
            {
                if !sensorGlucoseValues.isEmpty {
                    ForEach(sensorGlucoseValues) { sensorGlucose in
                        HStack {
                            Text(verbatim: sensorGlucose.timestamp.toLocalDateTime())
                                .monospacedDigit()

                            Spacer()

                            if let glucoseValue = sensorGlucose.smoothGlucoseValue?.toInteger(), sensorGlucose.timestamp < store.state.smoothThreshold, DirectConfig.showSmoothedGlucose {
                                Text(verbatim: glucoseValue.asGlucose(glucoseUnit: store.state.glucoseUnit, withUnit: true))
                                    .monospacedDigit()
                                    .if(store.state.isAlarm(glucoseValue: glucoseValue) != .none) { text in
                                        text.foregroundStyle(AmberTheme.cgaRed)
                                    }
                            } else {
                                Text(verbatim: sensorGlucose.glucoseValue.asGlucose(glucoseUnit: store.state.glucoseUnit, withUnit: true))
                                    .monospacedDigit()
                                    .if(store.state.isAlarm(glucoseValue: sensorGlucose.glucoseValue) != .none) { text in
                                        text.foregroundStyle(AmberTheme.cgaRed)
                                    }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                sensorGlucoseValues.removeAll { $0.id == sensorGlucose.id }
                                store.dispatch(.deleteSensorGlucose(glucose: sensorGlucose))
                                loggedEntryToast.show(.deletedSensorGlucose(sensorGlucose))
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.grouped)
        .onAppear {
            DirectLog.info("onAppear")
            self.sensorGlucoseValues = store.state.sensorGlucoseValues.reversed()
        }
        .onChange(of: store.state.sensorGlucoseValues) { _, glucoseValues in
            DirectLog.info("onChange")
            self.sensorGlucoseValues = glucoseValues.reversed()
        }
    }

    // MARK: Private

    @State private var sensorGlucoseValues: [SensorGlucose] = []
}
