//
//  MealEntryListView.swift
//  DOSBTSApp
//

import SwiftUI

struct MealEntryListView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore

    var body: some View {
        Group {
            CollapsableSection(
                teaser: Text(getTeaser(mealEntryValues.count)),
                header: HStack {
                    Label("Meals", systemImage: "fork.knife")
                    Spacer()
                    SelectedDatePager().padding(.trailing)
                }.buttonStyle(.plain),
                collapsed: true,
                collapsible: !mealEntryValues.isEmpty)
            {
                if mealEntryValues.isEmpty {
                    Text(getTeaser(mealEntryValues.count))
                } else {
                    ForEach(mealEntryValues) { mealEntry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: mealEntry.timestamp.toLocalDateTime())
                                    .monospacedDigit()

                                Text(verbatim: mealEntry.mealDescription)
                                    .opacity(0.5)
                                    .font(DOSTypography.caption)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                if let carbs = mealEntry.carbsGrams {
                                    Text(verbatim: "\(Int(carbs))g carbs")
                                        .monospacedDigit()
                                }

                                HStack(spacing: DOSSpacing.xs) {
                                    if let p = mealEntry.proteinGrams {
                                        Text(verbatim: "\(Int(p))g P")
                                    }
                                    if let f = mealEntry.fatGrams {
                                        Text(verbatim: "\(Int(f))g F")
                                    }
                                    if let cal = mealEntry.calories {
                                        Text(verbatim: "\(Int(cal)) kcal")
                                    }
                                }
                                .font(DOSTypography.caption)
                                .foregroundStyle(AmberTheme.amberDark)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                logAgain(mealEntry)
                            } label: {
                                Label("Log Again", systemImage: "arrow.counterclockwise")
                            }
                            .tint(AmberTheme.cgaGreen)
                        }
                        .contextMenu {
                            Button {
                                logAgain(mealEntry)
                            } label: {
                                Label("Log Again", systemImage: "arrow.counterclockwise")
                            }

                            Button {
                                addToFavorites(mealEntry)
                            } label: {
                                Label("Add to Favorites", systemImage: "star")
                            }
                        }
                    }.onDelete { offsets in
                        DirectLog.info("onDelete: \(offsets)")

                        let deletables = offsets.map { i in
                            (index: i, mealEntry: mealEntryValues[i])
                        }

                        deletables.forEach { delete in
                            mealEntryValues.remove(at: delete.index)
                            store.dispatch(.deleteMealEntry(mealEntry: delete.mealEntry))
                        }
                    }
                }
            }
        }
        .listStyle(.grouped)
        .onAppear {
            DirectLog.info("onAppear")
            self.mealEntryValues = store.state.mealEntryValues.reversed()
        }
        .onChange(of: store.state.mealEntryValues) { mealEntryValues in
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
    }

    private func addToFavorites(_ mealEntry: MealEntry) {
        store.dispatch(.addFavoriteFoodValues(favoriteFoodValues: [FavoriteFood.from(mealEntry: mealEntry)]))
    }
}
