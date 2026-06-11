//
//  UnifiedFoodEntryView.swift
//  DOSBTSApp
//

import SwiftUI

struct UnifiedFoodEntryView: View {
    @EnvironmentObject var store: DirectStore
    @Environment(\.dismiss) var dismiss

    var filterToHypoTreatments: Bool = false

    @State private var searchText = ""
    @State private var showingFavoriteManagement = false
    @State private var quickExpanded = false
    @StateObject private var toast = LoggedMealToastController()
    @State private var relogMeal: MealEntry?
    @State private var askAINavigating = false

    private var displayedFavorites: [FavoriteFood] {
        if filterToHypoTreatments {
            return store.state.favoriteFoodValues.filter(\.isHypoTreatment)
        }
        return store.state.favoriteFoodValues
    }

    var body: some View {
        // NavigationStack, not NavigationView: navigationDestination modifiers
        // (relog + ASK AI) are silently ignored inside NavigationView.
        NavigationStack {
            List {
                if filterToHypoTreatments {
                    if displayedFavorites.isEmpty {
                        Section {
                            Text("NO HYPO TREATMENTS CONFIGURED")
                                .font(DOSTypography.caption)
                                .foregroundColor(AmberTheme.amber)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, DOSSpacing.lg)
                        }
                    } else {
                        favoritesSection
                    }
                } else if !store.state.favoriteFoodValues.isEmpty {
                    favoritesSection
                }

                if !filterToHypoTreatments {
                    actionsSection
                }

                recentsSection
            }
            .listStyle(.grouped)
            .searchable(text: $searchText, prompt: "Search foods...")
            .dosNavigationTitle(filterToHypoTreatments ? "Hypo Treatment" : "Log Meal")
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
                }
            }
            .overlay(alignment: .bottom) {
                Group {
                    if let meal = toast.meal {
                        LoggedMealToast(meal: meal) {
                            store.dispatch(.deleteMealEntry(mealEntry: meal))
                            toast.dismiss()
                        }
                    }
                }
                .animation(.linear(duration: 0.2), value: toast.meal)
            }
            .navigationDestination(item: $relogMeal) { meal in
                FoodPhotoAnalysisView(relogMeal: meal)
                    .environmentObject(store)
                    .navigationBarHidden(true)
            }
            .navigationDestination(isPresented: $askAINavigating) {
                FoodPhotoAnalysisView()
                    .environmentObject(store)
                    .navigationBarHidden(true)
            }
        }
        .sheet(isPresented: $showingFavoriteManagement) {
            FavoriteManagementView()
                .environmentObject(store)
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
            if quickExpanded {
                // All favourites in a wrapping grid — the chevron promised it.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96, maximum: 160), spacing: DOSSpacing.xs, alignment: .leading)],
                    alignment: .leading,
                    spacing: DOSSpacing.xs
                ) {
                    ForEach(filteredFavorites) { favorite in
                        favoriteChip(favorite)
                    }
                }
                .padding(.vertical, DOSSpacing.xs)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: DOSSpacing.sm, bottom: 0, trailing: DOSSpacing.sm))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DOSSpacing.xs) {
                        ForEach(filteredFavorites.prefix(8)) { favorite in
                            favoriteChip(favorite)
                        }
                    }
                    .padding(.vertical, DOSSpacing.xs)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: DOSSpacing.sm, bottom: 0, trailing: DOSSpacing.sm))
            }
        } header: {
            Button {
                withAnimation(.linear(duration: 0.15)) {
                    quickExpanded.toggle()
                }
            } label: {
                HStack(spacing: DOSSpacing.xs) {
                    Text("> QUICK")
                        .font(DOSTypography.caption)
                        .foregroundColor(AmberTheme.amber)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(AmberTheme.amber)
                        .rotationEffect(.degrees(quickExpanded ? 90 : 0))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(quickExpanded ? "Collapse quick favourites" : "Show all quick favourites")
        }
    }

    @ViewBuilder
    private func favoriteChip(_ favorite: FavoriteFood) -> some View {
        if favorite.isHypoTreatment {
            // Hypo treatments stay 1-tap direct log with no hold gesture
            // (R4, KTD-7) — staging or holding during a hypo is wrong.
            AmberChip(
                label: favorite.chipLabel,
                subtitle: favorite.carbsGrams.map { "\(Int($0))g" },
                variant: .quick,
                tint: AmberTheme.cgaGreen
            ) {
                logFavorite(favorite)
            }
        } else {
            HoldToCommitProgress(
                onTap: { stageFavorite(favorite) },
                onCommit: { logFavorite(favorite) }
            ) {
                AmberChipLabel(
                    label: favorite.chipLabel,
                    subtitle: favorite.carbsGrams.map { "\(Int($0))g" },
                    variant: .quick
                )
            }
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
                        .foregroundColor(AmberTheme.amber)
                } else {
                    Text("No matches for \"\(searchText)\"")
                        .font(DOSTypography.bodySmall)
                        .foregroundColor(AmberTheme.amber)
                }
            } else {
                ForEach(filteredRecents) { meal in
                    // Tap stages, hold insta-logs. The old "Log Now" swipe and
                    // context menu are gone — a long-press context menu can't
                    // coexist with the hold recognizer (DMNC-796 KTD-3), which
                    // is why the .recent variant gets only onAddToFavorite.
                    HoldToCommitProgress(
                        onTap: { openOnStagingPlate(meal) },
                        onCommit: { logRecent(meal) }
                    ) {
                        MealItemRow(
                            meal: meal,
                            variant: .recent,
                            onAddToFavorite: { addToFavorites(meal) }
                        )
                    }
                }
            }
        } header: {
            Text("> RECENT")
                .font(DOSTypography.caption)
                .foregroundColor(AmberTheme.amber)
        }
    }

    // MARK: - Actions Section

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            NavigationLink {
                AddMealView { time, description, carbs in
                    let mealEntry = MealEntry(timestamp: time, mealDescription: description, carbsGrams: carbs)
                    store.dispatch(.addMealEntry(mealEntryValues: [mealEntry]))
                    dismiss()
                }
                .navigationBarHidden(true)
            } label: {
                HStack {
                    Image(systemName: "keyboard")
                        .font(DOSTypography.caption)
                    Text("MANUAL")
                        .font(DOSTypography.bodySmall)
                }
                .foregroundColor(AmberTheme.amber)
            }

            // SCAN — always available (OFF is free, no API key needed)
            NavigationLink {
                BarcodeScannerView()
                    .environmentObject(store)
                    .navigationBarHidden(true)
            } label: {
                HStack {
                    Image(systemName: "barcode.viewfinder")
                        .font(DOSTypography.caption)
                    Text("SCAN")
                        .font(DOSTypography.bodySmall)
                }
                .foregroundColor(AmberTheme.amber)
            }

            if store.state.claudeAPIKeyValid || store.state.aiConsentFoodPhoto {
                NavigationLink {
                    FoodPhotoAnalysisView()
                        .environmentObject(store)
                        .navigationBarHidden(true)
                } label: {
                    HStack {
                        Image(systemName: "camera.viewfinder")
                            .font(DOSTypography.caption)
                        Text("PHOTO")
                            .font(DOSTypography.bodySmall)
                    }
                    .foregroundColor(AmberTheme.amber)
                }

                // NL text parsing — appears when search text >= 3 chars
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 {
                    if store.state.foodAnalysisLoading {
                        HStack {
                            ProgressView()
                                .tint(AmberTheme.amber)
                            Text("Analyzing...")
                                .font(DOSTypography.bodySmall)
                                .foregroundColor(AmberTheme.amber)
                        }
                    } else {
                        // Deliberately NOT a NavigationLink: the destination's onAppear
                        // used to flip foodAnalysisLoading, which swapped this row for the
                        // "Analyzing..." branch and removed the link mid-push — SwiftUI then
                        // cancelled the navigation, so the row appeared dead no matter how
                        // often it was tapped. Dispatch first, then navigate via the
                        // navigationDestination(isPresented:) on the List, which survives
                        // row rebuilds.
                        Button {
                            // Guard: only dispatch if not already loading/loaded
                            if !store.state.foodAnalysisLoading, store.state.foodAnalysisResult == nil {
                                let query = String(searchText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
                                store.dispatch(.setFoodAnalysisLoading(isLoading: true))
                                store.dispatch(.analyzeFoodText(query: query))
                            }
                            // Drop the search keyboard before the push; the query text
                            // stays in the field for when the user navigates back.
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            askAINavigating = true
                        } label: {
                            HStack {
                                Image(systemName: "sparkles")
                                    .font(DOSTypography.caption)
                                Text("ASK AI: \"\(searchText.prefix(30))\"")
                                    .font(DOSTypography.bodySmall)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(DOSTypography.caption)
                                    .foregroundColor(AmberTheme.amberDark)
                            }
                            .foregroundColor(AmberTheme.amber)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Filtering (local, no Redux dispatch)

    private var filteredFavorites: [FavoriteFood] {
        let base = filterToHypoTreatments ? displayedFavorites : store.state.favoriteFoodValues
        guard !searchText.isEmpty else { return base }
        return base.filter {
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
        toast.show(mealEntry)
    }

    private func stageFavorite(_ favorite: FavoriteFood) {
        // lastUsed bumps at tap time even if the plate is discarded — it is
        // a sort heuristic, not medical data (DMNC-796 KTD-4).
        store.dispatch(.logFavoriteFood(favoriteFood: favorite))
        relogMeal = favorite.toMealEntry()
    }

    private func logRecent(_ meal: MealEntry) {
        let newEntry = FavoriteFood.from(mealEntry: meal).toMealEntry()
        store.dispatch(.addMealEntry(mealEntryValues: [newEntry]))
        toast.show(newEntry)
    }

    private func openOnStagingPlate(_ meal: MealEntry) {
        relogMeal = meal
    }

    private func addToFavorites(_ meal: MealEntry) {
        store.dispatch(.addFavoriteFoodValues(favoriteFoodValues: [FavoriteFood.from(mealEntry: meal)]))
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
                    Text("No favorites yet. Swipe left on a recent meal to add it.")
                        .font(DOSTypography.bodySmall)
                        .foregroundColor(AmberTheme.amber)
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
                                        .foregroundColor(AmberTheme.amber)
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
            .dosNavigationTitle("Favorites")
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
    @State private var shortLabel: String = ""
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
                        Text("Short label")
                        TextField("Optional — e.g. \"milk\"", text: $shortLabel)
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
            .dosNavigationTitle("Edit Favorite")
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
                            lastUsed: favorite.lastUsed,
                            shortLabel: shortLabel
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
                shortLabel = favorite.shortLabel ?? ""
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

