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
    @EnvironmentObject var sheets: SheetCoordinator
    @EnvironmentObject var addedHighlighter: AddedEntryHighlighter
    @EnvironmentObject var loggedEntryToast: LoggedEntryToastController

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
                    ForEach(insulinDeliveryValues) { insulinDelivery in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(verbatim: insulinDelivery.starts.toLocalDateTime())
                                    .monospacedDigit()

                                if insulinDelivery.type == .basal {
                                    Text(verbatim: insulinDelivery.ends.toLocalDateTime())
                                        .monospacedDigit()
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing) {
                                Text(verbatim: insulinDelivery.units.asInsulinUnits())
                                    .monospacedDigit()

                                Text(verbatim: insulinDelivery.type.localizedDescription)
                                    .opacity(0.5)
                                    .font(DOSTypography.caption)
                            }
                        }
                        .dosAddedHighlight(addedHighlighter.highlightedID == insulinDelivery.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            sheets.present(.combinedEntryEdit(markerGroup(for: insulinDelivery)))
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                insulinDeliveryValues.removeAll { $0.id == insulinDelivery.id }
                                store.dispatch(.deleteInsulinDelivery(insulinDelivery: insulinDelivery))
                                loggedEntryToast.show(.deletedInsulin(insulinDelivery))
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

    /// Wraps an insulin delivery in a single-marker ConsolidatedMarkerGroup
    /// so it can be opened in CombinedEntryEditView.
    private func markerGroup(for delivery: InsulinDelivery) -> ConsolidatedMarkerGroup {
        let id = "insulin-\(delivery.id.uuidString)"
        let marker = EventMarker(
            id: id,
            time: delivery.starts,
            type: delivery.type.markerType,
            label: delivery.units.asInsulin(),
            rawValue: delivery.units,
            sourceID: delivery.id
        )
        return ConsolidatedMarkerGroup(
            id: id,
            time: delivery.starts,
            markers: [marker]
        )
    }
}
