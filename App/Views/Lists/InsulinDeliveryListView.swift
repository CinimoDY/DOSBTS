//
//  InsulinList.swift
//  DOSBTSApp
//

import SwiftUI

struct InsulinDeliveryListView: View {
    /// UserDefaults persistence key for this section's expanded state —
    /// must stay stable across releases (display name may change freely).
    private let sectionKey = "Insulin"

    // MARK: Internal

    @EnvironmentObject var store: DirectStore
    @EnvironmentObject var addedHighlighter: AddedEntryHighlighter

    var body: some View {
        Group {
            CollapsableSection(
                teaser: Text(getTeaser(insulinDeliveryValues.count)),
                header: HStack {
                    Label("Insulin", systemImage: "syringe")
                    Spacer()
                    SelectedDatePager().padding(.trailing)
                }.buttonStyle(.plain),
                sectionName: "Insulin",
                collapsed: !store.state.listSectionExpanded[sectionKey, default: false],
                collapsible: !insulinDeliveryValues.isEmpty,
                onCollapsedChange: { isCollapsed in
                    store.dispatch(.setListSectionExpanded(sectionName: sectionKey, isExpanded: !isCollapsed))
                })
            {
                if insulinDeliveryValues.isEmpty {
                    Text(getTeaser(insulinDeliveryValues.count))
                } else {
                    ForEach(insulinDeliveryValues) { insulinDeliveryValue in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(verbatim: insulinDeliveryValue.starts.toLocalDateTime())
                                    .monospacedDigit()

                                if insulinDeliveryValue.type == .basal {
                                    Text(verbatim: insulinDeliveryValue.ends.toLocalDateTime())
                                        .monospacedDigit()
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing) {
                                Text(verbatim: insulinDeliveryValue.units.asInsulinUnits())
                                    .monospacedDigit()

                                Text(verbatim: insulinDeliveryValue.type.localizedDescription)
                                    .opacity(0.5)
                                    .font(DOSTypography.caption)
                            }
                        }
                        .dosAddedHighlight(addedHighlighter.highlightedID == insulinDeliveryValue.id)
                    }.onDelete { offsets in
                        DirectLog.info("onDelete: \(offsets)")

                        let deletables = offsets.map { i in
                            (index: i, insulinDelivery: insulinDeliveryValues[i])
                        }

                        deletables.forEach { delete in
                            insulinDeliveryValues.remove(at: delete.index)
                            store.dispatch(.deleteInsulinDelivery(insulinDelivery: delete.insulinDelivery))
                        }
                    }
                }
            }
        }
        .listStyle(.grouped)
        .onAppear {
            DirectLog.info("onAppear")
            self.insulinDeliveryValues = store.state.insulinDeliveryValues.reversed()
        }
        .onChange(of: store.state.insulinDeliveryValues) { _, insulinDeliveryValues in
            DirectLog.info("onChange")
            self.insulinDeliveryValues = insulinDeliveryValues.reversed()
        }
    }

    // MARK: Private

    @State private var insulinDeliveryValues: [InsulinDelivery] = []

    private func getTeaser(_ count: Int) -> String {
        return count.pluralizeLocalization(singular: "%@ Entry", plural: "%@ Entries")
    }
}
