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
    @State private var showingFavoriteManagement = false
    @State private var toastMealEntry: MealEntry?
    @State private var toastWorkItem: DispatchWorkItem?

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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingFavoriteManagement = true
                    } label: {
                        Image(systemName: "gear")
                            .foregroundColor(AmberTheme.amberDark)
                    }
                    .sheet(isPresented: $showingFavoriteManagement) {
                        FavoriteManagementView()
                            .environmentObject(store)
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
                HStack(spacing: DOSSpacing.xs) {
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
        let mealEntry = favorite.toMealEntry()
        store.dispatch(.addMealEntry(mealEntryValues: [mealEntry]))
        store.dispatch(.logFavoriteFood(favoriteFood: favorite))
        showToast(for: mealEntry)
    }

    private func logRecent(_ meal: MealEntry) {
        let newEntry = FavoriteFood.from(mealEntry: meal).toMealEntry()
        store.dispatch(.addMealEntry(mealEntryValues: [newEntry]))
        showToast(for: newEntry)
    }

    private func addToFavorites(_ meal: MealEntry) {
        store.dispatch(.addFavoriteFoodValues(favoriteFoodValues: [FavoriteFood.from(mealEntry: meal)]))
    }

    private func showToast(for meal: MealEntry) {
        withAnimation(.linear(duration: 0.2)) {
            toastMealEntry = meal
        }
        toastWorkItem?.cancel()
        let workItem = DispatchWorkItem { dismissToast() }
        toastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
    }

    private func dismissToast() {
        toastWorkItem?.cancel()
        toastWorkItem = nil
        withAnimation(.linear(duration: 0.2)) {
            toastMealEntry = nil
        }
    }
}

// MARK: - FavoriteManagementView

struct FavoriteManagementView: View {
    @EnvironmentObject var store: DirectStore
    @Environment(\.dismiss) var dismiss

    @State private var editingFavorite: FavoriteFood?

    var body: some View {
        NavigationView {
            List {
                if store.state.favoriteFoodValues.isEmpty {
                    Text("No favorites yet. Long-press a meal to add it.")
                        .font(DOSTypography.bodySmall)
                        .foregroundColor(AmberTheme.amberDark)
                } else {
                    ForEach(store.state.favoriteFoodValues) { favorite in
                        Button {
                            editingFavorite = favorite
                        } label: {
                            HStack {
                                if favorite.isHypoTreatment {
                                    Image(systemName: "cross.case")
                                        .font(DOSTypography.caption)
                                        .foregroundColor(AmberTheme.cgaGreen)
                                        .frame(height: 16)
                                } else {
                                    Image(systemName: "star.fill")
                                        .font(DOSTypography.caption)
                                        .foregroundColor(AmberTheme.amber)
                                        .frame(height: 16)
                                }

                                Text(favorite.mealDescription)
                                    .font(DOSTypography.bodySmall)
                                    .foregroundColor(AmberTheme.amber)

                                Spacer()

                                if let carbs = favorite.carbsGrams {
                                    Text("\(Int(carbs))g")
                                        .font(DOSTypography.caption)
                                        .foregroundColor(AmberTheme.amberDark)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        let favorites = store.state.favoriteFoodValues
                        offsets.forEach { index in
                            store.dispatch(.deleteFavoriteFood(favoriteFood: favorites[index]))
                        }
                    }
                    .onMove { source, destination in
                        moveFavorites(from: source, to: destination)
                    }
                }
            }
            .listStyle(.grouped)
            .navigationTitle("Favorites")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
            .sheet(item: $editingFavorite) { favorite in
                EditFavoriteView(favorite: favorite)
                    .environmentObject(store)
            }
        }
    }

    private func moveFavorites(from source: IndexSet, to destination: Int) {
        var favorites = store.state.favoriteFoodValues
        favorites.move(fromOffsets: source, toOffset: destination)

        let reordered = favorites.enumerated().map { index, favorite in
            FavoriteFood(
                id: favorite.id,
                mealDescription: favorite.mealDescription,
                carbsGrams: favorite.carbsGrams,
                proteinGrams: favorite.proteinGrams,
                fatGrams: favorite.fatGrams,
                calories: favorite.calories,
                fiberGrams: favorite.fiberGrams,
                sortOrder: index,
                isHypoTreatment: favorite.isHypoTreatment,
                lastUsed: favorite.lastUsed
            )
        }
        store.dispatch(.reorderFavoriteFoods(favoriteFoodValues: reordered))
    }
}

// MARK: - EditFavoriteView

struct EditFavoriteView: View {
    @EnvironmentObject var store: DirectStore
    @Environment(\.dismiss) var dismiss

    let favorite: FavoriteFood

    @State private var mealDescription: String = ""
    @State private var carbsGrams: Double?
    @State private var proteinGrams: Double?
    @State private var fatGrams: Double?
    @State private var calories: Double?
    @State private var fiberGrams: Double?
    @State private var isHypoTreatment: Bool = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Text("Description")
                        TextField("", text: $mealDescription)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Carbs (g)")
                        TextField("", value: $carbsGrams, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Protein (g)")
                        TextField("", value: $proteinGrams, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Fat (g)")
                        TextField("", value: $fatGrams, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Calories")
                        TextField("", value: $calories, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Fiber (g)")
                        TextField("", value: $fiberGrams, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    Toggle("Hypo Treatment", isOn: $isHypoTreatment)
                }
            }
            .navigationTitle("Edit Favorite")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let trimmed = mealDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let clampedDescription = String(trimmed.prefix(200))
                        let clampedCarbs = carbsGrams.flatMap { $0 >= 0 && $0 <= 1000 ? $0 : nil }
                        let clampedProtein = proteinGrams.flatMap { $0 >= 0 && $0 <= 1000 ? $0 : nil }
                        let clampedFat = fatGrams.flatMap { $0 >= 0 && $0 <= 1000 ? $0 : nil }
                        let clampedCalories = calories.flatMap { $0 >= 0 && $0 <= 10000 ? $0 : nil }
                        let clampedFiber = fiberGrams.flatMap { $0 >= 0 && $0 <= 1000 ? $0 : nil }

                        let updated = FavoriteFood(
                            id: favorite.id,
                            mealDescription: clampedDescription,
                            carbsGrams: clampedCarbs,
                            proteinGrams: clampedProtein,
                            fatGrams: clampedFat,
                            calories: clampedCalories,
                            fiberGrams: clampedFiber,
                            sortOrder: favorite.sortOrder,
                            isHypoTreatment: isHypoTreatment,
                            lastUsed: favorite.lastUsed
                        )
                        store.dispatch(.updateFavoriteFood(favoriteFood: updated))
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                mealDescription = favorite.mealDescription
                carbsGrams = favorite.carbsGrams
                proteinGrams = favorite.proteinGrams
                fatGrams = favorite.fatGrams
                calories = favorite.calories
                fiberGrams = favorite.fiberGrams
                isHypoTreatment = favorite.isHypoTreatment
            }
        }
    }
}

