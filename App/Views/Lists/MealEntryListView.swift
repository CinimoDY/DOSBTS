//
//  MealEntryListView.swift
//  DOSBTSApp
//

import SwiftUI

struct MealEntryListView: View {
    /// UserDefaults persistence key for this section's expanded state —
    /// must stay stable across releases (display name may change freely).
    private let sectionKey = "Meals"

    // MARK: Internal

    @EnvironmentObject var store: DirectStore
    @EnvironmentObject var addedHighlighter: AddedEntryHighlighter

    var body: some View {
        Group {
            CollapsableSection(
                label: Label {
                    Text("Meals")
                } icon: {
                    AppleIcon().frame(width: 16, height: 16)
                },
                accessory: SelectedDatePager().padding(.trailing),
                sectionName: "Meals",
                count: mealEntryValues.count,
                collapsed: !store.state.listSectionExpanded[sectionKey, default: false],
                collapsible: !mealEntryValues.isEmpty,
                onCollapsedChange: { isCollapsed in
                    store.dispatch(.setListSectionExpanded(sectionName: sectionKey, isExpanded: !isCollapsed))
                })
            {
                if !mealEntryValues.isEmpty {
                    ForEach(mealEntryValues) { mealEntry in
                        MealItemRow(
                            meal: mealEntry,
                            variant: .list,
                            onLogAgain: { logAgain(mealEntry) },
                            onAddToFavorite: { addToFavorites(mealEntry) },
                            onDelete: { delete(mealEntry) }
                        )
                        .dosAddedHighlight(addedHighlighter.highlightedID == mealEntry.id)
                    }
                }
            }
        }
        .listStyle(.grouped)
        .onAppear {
            DirectLog.info("onAppear")
            self.mealEntryValues = store.state.mealEntryValues.reversed()
        }
        .onChange(of: store.state.mealEntryValues) { _, mealEntryValues in
            DirectLog.info("onChange")
            self.mealEntryValues = mealEntryValues.reversed()
        }
    }

    // MARK: Private

    @State private var mealEntryValues: [MealEntry] = []

    private func logAgain(_ mealEntry: MealEntry) {
        let newEntry = FavoriteFood.from(mealEntry: mealEntry).toMealEntry()
        store.dispatch(.addMealEntry(mealEntryValues: [newEntry]))
        addedHighlighter.flash(newEntry.id)
    }

    private func delete(_ mealEntry: MealEntry) {
        DirectLog.info("delete meal entry: \(mealEntry.id)")
        mealEntryValues.removeAll { $0.id == mealEntry.id }
        store.dispatch(.deleteMealEntry(mealEntry: mealEntry))
    }

    private func addToFavorites(_ mealEntry: MealEntry) {
        store.dispatch(.addFavoriteFoodValues(favoriteFoodValues: [FavoriteFood.from(mealEntry: mealEntry)]))
    }
}
