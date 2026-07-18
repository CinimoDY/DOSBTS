//
//  BloodGlucoseList.swift
//  DOSBTSApp
//

import SwiftUI

struct BloodGlucoseListView: View {
    /// UserDefaults persistence key for this section's expanded state —
    /// must stay stable across releases (display name may change freely).
    private let sectionKey = "Blood glucose"

    // MARK: Internal

    @EnvironmentObject var store: DirectStore
    @EnvironmentObject var addedHighlighter: AddedEntryHighlighter
    @EnvironmentObject var loggedEntryToast: LoggedEntryToastController

    var body: some View {
        Group {
            CollapsableSection(
                label: Label("Blood glucose values", systemImage: "drop"),
                accessory: SelectedDatePager().padding(.trailing),
                sectionName: "Blood glucose",
                count: bloodGlucoseValues.count,
                collapsed: !store.state.listSectionExpanded[sectionKey, default: false],
                collapsible: !bloodGlucoseValues.isEmpty,
                onCollapsedChange: { isCollapsed in
                    store.dispatch(.setListSectionExpanded(sectionName: sectionKey, isExpanded: !isCollapsed))
                })
            {
                if !bloodGlucoseValues.isEmpty {
                    ForEach(bloodGlucoseValues) { bloodGlucose in
                        HStack {
                            Text(verbatim: bloodGlucose.timestamp.toLocalDateTime())
                                .monospacedDigit()

                            Spacer()

                            Text(verbatim: bloodGlucose.glucoseValue.asGlucose(glucoseUnit: store.state.glucoseUnit, withUnit: true))
                                .monospacedDigit()
                                .if(store.state.isAlarm(glucoseValue: bloodGlucose.glucoseValue) != .none) { text in
                                    text.foregroundStyle(AmberTheme.cgaRed)
                                }
                        }
                        .dosAddedHighlight(addedHighlighter.highlightedID == bloodGlucose.id)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                bloodGlucoseValues.removeAll { $0.id == bloodGlucose.id }
                                store.dispatch(.deleteBloodGlucose(glucose: bloodGlucose))
                                loggedEntryToast.show(.deletedBloodGlucose(bloodGlucose))
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
            self.bloodGlucoseValues = store.state.bloodGlucoseValues.reversed()
        }
        .onChange(of: store.state.bloodGlucoseValues) { _, glucoseValues in
            DirectLog.info("onChange")
            self.bloodGlucoseValues = glucoseValues.reversed()
        }
    }

    // MARK: Private

    @State private var bloodGlucoseValues: [BloodGlucose] = []
}
