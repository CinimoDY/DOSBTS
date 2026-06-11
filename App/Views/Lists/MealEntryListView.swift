//
//  MealEntryListView.swift
//  DOSBTSApp
//

import SwiftUI

struct MealEntryListView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore
    @EnvironmentObject var addedHighlighter: AddedEntryHighlighter

    var body: some View {
        Group {
            CollapsableSection(
                teaser: Text(getTeaser(mealEntryValues.count)),
                header: HStack {
                    Label {
                        Text("Meals")
                    } icon: {
                        AppleIcon().frame(width: 16, height: 16)
                    }
                    Spacer()
                    SelectedDatePager().padding(.trailing)
                }.buttonStyle(.plain),
                sectionName: "Meals",
                collapsed: true,
                collapsible: !mealEntryValues.isEmpty)
            {
                if mealEntryValues.isEmpty {
                    Text(getTeaser(mealEntryValues.count))
                } else {
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

    private func getTeaser(_ count: Int) -> String {
        return count.pluralizeLocalization(singular: "%@ Entry", plural: "%@ Entries")
    }

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
