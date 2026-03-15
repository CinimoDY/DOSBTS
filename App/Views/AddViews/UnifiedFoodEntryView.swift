//
//  UnifiedFoodEntryView.swift
//  DOSBTSApp
//

import SwiftUI

struct UnifiedFoodEntryView: View {
    @EnvironmentObject var store: DirectStore
    @Environment(\.dismiss) var dismiss

    @State private var searchText = ""
    @State private var showingAddMealView = false
    @State private var showingFoodPhotoView = false
    @State private var toastMealEntry: MealEntry?
    @State private var toastTimer: Timer?

    var body: some View {
        NavigationView {
            List {
                if !store.state.favoriteFoodValues.isEmpty {
                    favoritesSection
                }

                recentsSection

                actionsSection
            }
            .listStyle(.grouped)
            .searchable(text: $searchText, prompt: "Search foods...")
            .navigationTitle("Log Meal")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let meal = toastMealEntry {
                    toastView(meal: meal)
                }
            }
        }
        .onAppear {
            store.dispatch(.loadFavoriteFoodValues)
            store.dispatch(.loadRecentMealEntries)
        }
    }

    // MARK: - Favorites Section

    @ViewBuilder
    private var favoritesSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DOSSpacing.xs) {
                    ForEach(filteredFavorites.prefix(8)) { favorite in
                        Button {
                            logFavorite(favorite)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(favorite.mealDescription)
                                    .font(DOSTypography.caption)
                                    .lineLimit(1)

                                if let carbs = favorite.carbsGrams {
                                    Text("\(Int(carbs))g")
                                        .font(DOSTypography.caption)
                                        .foregroundColor(favorite.isHypoTreatment ? AmberTheme.cgaGreen : AmberTheme.amber)
                                }
                            }
                            .padding(.horizontal, DOSSpacing.sm)
                            .padding(.vertical, DOSSpacing.xs)
                            .background(Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(favorite.isHypoTreatment ? AmberTheme.cgaGreen : AmberTheme.amber, lineWidth: 1)
                            )
                        }
                        .foregroundColor(favorite.isHypoTreatment ? AmberTheme.cgaGreen : AmberTheme.amber)
                    }
                }
                .padding(.vertical, DOSSpacing.xs)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: DOSSpacing.sm, bottom: 0, trailing: DOSSpacing.sm))
        } header: {
            Text("> QUICK")
                .font(DOSTypography.caption)
                .foregroundColor(AmberTheme.amberDark)
        }
    }

    // MARK: - Recents Section

    @ViewBuilder
    private var recentsSection: some View {
        Section {
            if filteredRecents.isEmpty {
                if searchText.isEmpty {
                    Text("Log your first meal to see recents here")
                        .font(DOSTypography.bodySmall)
                        .foregroundColor(AmberTheme.amberDark)
                } else {
                    Text("No matches for \"\(searchText)\"")
                        .font(DOSTypography.bodySmall)
                        .foregroundColor(AmberTheme.amberDark)
                }
            } else {
                ForEach(filteredRecents) { meal in
                    Button {
                        logRecent(meal)
                    } label: {
                        HStack {
                            Text("> ")
                                .font(DOSTypography.bodySmall)
                                .foregroundColor(AmberTheme.amberDark)

                            Text(meal.mealDescription)
                                .font(DOSTypography.bodySmall)
                                .foregroundColor(AmberTheme.amber)
                                .lineLimit(1)

                            Spacer()

                            if let carbs = meal.carbsGrams {
                                Text("\(Int(carbs))g carbs")
                                    .font(DOSTypography.caption)
                                    .foregroundColor(AmberTheme.amber)
                            }
                        }
                    }
                    .contextMenu {
                        Button {
                            addToFavorites(meal)
                        } label: {
                            Label("Add to Favorites", systemImage: "star")
                        }
                    }
                }
            }
        } header: {
            Text("> RECENT")
                .font(DOSTypography.caption)
                .foregroundColor(AmberTheme.amberDark)
        }
    }

    // MARK: - Actions Section

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            HStack(spacing: DOSSpacing.sm) {
                Button {
                    showingAddMealView = true
                } label: {
                    HStack {
                        Image(systemName: "keyboard")
                            .font(DOSTypography.caption)
                        Text("MANUAL")
                            .font(DOSTypography.bodySmall)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(AmberTheme.amberDark)
                }
                .sheet(isPresented: $showingAddMealView) {
                    AddMealView { time, description, carbs in
                        let mealEntry = MealEntry(timestamp: time, mealDescription: description, carbsGrams: carbs)
                        store.dispatch(.addMealEntry(mealEntryValues: [mealEntry]))
                    }
                }

                if store.state.claudeAPIKeyValid || store.state.aiConsentFoodPhoto {
                    Button {
                        showingFoodPhotoView = true
                    } label: {
                        HStack {
                            Image(systemName: "camera.viewfinder")
                                .font(DOSTypography.caption)
                            Text("PHOTO")
                                .font(DOSTypography.bodySmall)
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(AmberTheme.amberDark)
                    }
                    .sheet(isPresented: $showingFoodPhotoView) {
                        FoodPhotoAnalysisView()
                            .environmentObject(store)
                    }
                }
            }
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Toast

    @ViewBuilder
    private func toastView(meal: MealEntry) -> some View {
        HStack {
            Text("Logged: \(meal.mealDescription)")
                .font(DOSTypography.caption)
                .foregroundColor(AmberTheme.amber)
                .lineLimit(1)

            Spacer()

            Button("UNDO") {
                store.dispatch(.deleteMealEntry(mealEntry: meal))
                dismissToast()
            }
            .font(DOSTypography.caption)
            .foregroundColor(AmberTheme.cgaGreen)
        }
        .padding(DOSSpacing.sm)
        .background(Color.black.opacity(0.95))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(AmberTheme.amberDark, lineWidth: 1)
        )
        .padding(.horizontal, DOSSpacing.md)
        .padding(.bottom, DOSSpacing.md)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Filtering (local, no Redux dispatch)

    private var filteredFavorites: [FavoriteFood] {
        guard !searchText.isEmpty else { return store.state.favoriteFoodValues }
        return store.state.favoriteFoodValues.filter {
            $0.mealDescription.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredRecents: [MealEntry] {
        guard !searchText.isEmpty else { return store.state.recentMealEntries }
        return store.state.recentMealEntries.filter {
            $0.mealDescription.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Actions

    private func logFavorite(_ favorite: FavoriteFood) {
        store.dispatch(.logFavoriteFood(favoriteFood: favorite))

        // Find the created meal entry for undo (use description match since it was just created)
        let mealEntry = MealEntry(
            timestamp: Date(),
            mealDescription: favorite.mealDescription,
            carbsGrams: favorite.carbsGrams,
            proteinGrams: favorite.proteinGrams,
            fatGrams: favorite.fatGrams,
            calories: favorite.calories,
            fiberGrams: favorite.fiberGrams
        )
        showToast(for: mealEntry)
    }

    private func logRecent(_ meal: MealEntry) {
        let newEntry = MealEntry(
            timestamp: Date(),
            mealDescription: meal.mealDescription,
            carbsGrams: meal.carbsGrams,
            proteinGrams: meal.proteinGrams,
            fatGrams: meal.fatGrams,
            calories: meal.calories,
            fiberGrams: meal.fiberGrams
        )
        store.dispatch(.addMealEntry(mealEntryValues: [newEntry]))
        showToast(for: newEntry)
    }

    private func addToFavorites(_ meal: MealEntry) {
        let favorite = FavoriteFood(
            mealDescription: meal.mealDescription,
            carbsGrams: meal.carbsGrams,
            proteinGrams: meal.proteinGrams,
            fatGrams: meal.fatGrams,
            calories: meal.calories,
            fiberGrams: meal.fiberGrams
        )
        store.dispatch(.addFavoriteFoodValues(favoriteFoodValues: [favorite]))
    }

    private func showToast(for meal: MealEntry) {
        withAnimation(.linear(duration: 0.2)) {
            toastMealEntry = meal
        }
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            dismissToast()
        }
    }

    private func dismissToast() {
        toastTimer?.invalidate()
        toastTimer = nil
        withAnimation(.linear(duration: 0.2)) {
            toastMealEntry = nil
        }
    }
}
