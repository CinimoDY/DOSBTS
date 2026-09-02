//
//  UnifiedFoodEntryView.swift
//  DOSBTSApp
//

import SwiftUI

/// Pure mapping of the hypo-filtered food entry sheet's structural decisions.
/// During a treatment cycle the MEAL button routes here (R8); a user with
/// zero hypo favourites and zero recents must still have a way to log carbs,
/// so the escape row is always present in filtered mode (DMNC-1028). The view
/// renders this; `HypoFilteredEntryModelTests` pins the no-dead-end guarantee.
struct HypoFilteredEntryModel: Equatable {
    /// "NO HYPO TREATMENTS CONFIGURED" — shown when filtering yields no chips.
    let showsEmptyHypoMessage: Bool
    /// "LOG OTHER FOOD" manual-entry escape row.
    let showsEscapeRow: Bool

    static func make(hypoFavoriteCount: Int, filterToHypoTreatments: Bool) -> HypoFilteredEntryModel {
        HypoFilteredEntryModel(
            showsEmptyHypoMessage: filterToHypoTreatments && hypoFavoriteCount == 0,
            showsEscapeRow: filterToHypoTreatments
        )
    }
}

/// Pure "in-memory recents + DB search hits → displayed rows" mapping for the
/// food entry sheet's RECENT section (DMNC-1484).
///
/// The search box used to filter only `state.recentMealEntries`, so any food
/// older than the recents cap was unreachable by any means. A query of at least
/// `minQueryLength` characters now also hits the database; this model merges the
/// two sources and — critically — rejects results belonging to a *stale* query.
///
/// Stale rejection is load-bearing: `Store.dispatch` fires each middleware
/// publisher and never cancels in-flight work, so typing `ap` then `app` can
/// land the slower `ap` result last and paint the wrong rows. Every result
/// payload carries the query it answered (`MealHistoryResults.query`); anything
/// that doesn't match the current normalized query is ignored and the view stays
/// in its searching state.
///
/// Search is deliberately live in BOTH the normal and the hypo-filtered sheet:
/// the RECENT section is already identical in both modes, and suppressing search
/// during a treatment cycle would produce "No matches" for a food that
/// demonstrably exists — exactly the dead end this change exists to remove.
struct FoodHistorySearchModel: Equatable {
    /// Rows to render in the RECENT section, in display order.
    let rows: [MealEntry]
    /// A search is in flight: the query is long enough, but no result answering
    /// it has landed yet. `rows` still holds the in-memory matches meanwhile.
    let isSearching: Bool

    /// Same threshold as the ASK AI row, so history search and ASK AI appear
    /// together rather than out of phase.
    static let minQueryLength = 3
    /// Mirrors the ASK AI clamp.
    static let maxQueryLength = 500

    /// Trim + clamp. The VIEW calls this exactly once per query — at dispatch
    /// time and for the staleness comparison — and everything downstream echoes
    /// the result verbatim.
    ///
    /// Deliberately NOT idempotent-safe to re-apply: `prefix(maxQueryLength)` can
    /// leave trailing whitespace that a second `trimmingCharacters` would eat, so
    /// re-normalizing an already-normalized query can shorten it. Anything that
    /// re-normalized downstream would echo a key the view can never match, and
    /// the sheet would search forever (typing more cannot recover it, since
    /// appending does not change `prefix`). Pinned by
    /// `normalizedQueryIsNotIdempotent`.
    static func normalizedQuery(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxQueryLength))
    }

    static func make(
        query: String,
        recents: [MealEntry],
        results: MealHistoryResults?
    ) -> FoodHistorySearchModel {
        let normalized = normalizedQuery(query)

        guard !normalized.isEmpty else {
            return FoodHistorySearchModel(rows: recents, isSearching: false)
        }

        let local = recents.filter {
            $0.mealDescription.localizedCaseInsensitiveContains(normalized)
        }

        // Below the threshold the in-memory filter is the whole answer — no DB
        // round-trip, so nothing to wait for.
        guard normalized.count >= minQueryLength else {
            return FoodHistorySearchModel(rows: local, isSearching: false)
        }

        guard let results else {
            return FoodHistorySearchModel(rows: local, isSearching: true)
        }

        if results.query == normalized {
            return FoodHistorySearchModel(rows: merge(local: local, hits: results.entries), isSearching: false)
        }

        // Narrowing a query ("app" → "appl"): a contains-hit set for the longer
        // needle is a SUBSET of the shorter needle's, so the previous result can
        // be re-filtered in Swift and kept on screen while the fresh read is in
        // flight. Without this the rows collapse to the in-memory subset for
        // 250ms and then regrow — a visible flinch on every keystroke.
        // `isSearching` stays true because the old result was `limit`-capped and
        // may be missing rows the narrower query would have reached.
        if normalized.hasPrefix(results.query) {
            let narrowed = results.entries.filter {
                $0.mealDescription.localizedCaseInsensitiveContains(normalized)
            }
            return FoodHistorySearchModel(rows: merge(local: local, hits: narrowed), isSearching: true)
        }

        // Any other mismatch is a STALE result — an older, slower query landing
        // late. Ignore it entirely and keep waiting.
        return FoodHistorySearchModel(rows: local, isSearching: true)
    }

    /// Recents first, then DB hits that aren't already present. Recents win over
    /// duplicates: same food, fresher row. Dedupe on name, case-insensitively
    /// (`.lowercased()` folds non-ASCII too, unlike SQL's `COLLATE NOCASE`).
    private static func merge(local: [MealEntry], hits: [MealEntry]) -> [MealEntry] {
        var seen = Set(local.map { $0.mealDescription.lowercased() })
        var merged = local
        for entry in hits {
            let key = entry.mealDescription.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            merged.append(entry)
        }
        return merged
    }
}

struct UnifiedFoodEntryView: View {
    @EnvironmentObject var store: DirectStore
    @EnvironmentObject var addedHighlighter: AddedEntryHighlighter
    @EnvironmentObject var loggedEntryToast: LoggedEntryToastController
    @Environment(\.dismiss) var dismiss

    var filterToHypoTreatments: Bool = false

    @State private var searchText = ""
    @State private var showingFavoriteManagement = false
    @State private var quickExpanded = false
    @StateObject private var toast = LoggedMealToastController()
    @State private var relogMeal: MealEntry?
    @State private var askAINavigating = false
    @State private var searchDebounceTask: DispatchWorkItem?
    /// Bumped to force the mic down before SCAN/PHOTO push — `AVCaptureSession`
    /// and `AVAudioEngine` must never run at the same time (DMNC-1486 R1).
    @State private var dictationStopToken = 0
    /// Entry logged straight from a QUICK chip. The chips sit ABOVE the RECENT
    /// list, so the follow-the-new-entry scroll below would push them off screen
    /// and force a scroll back up before the next tap — the exact opposite of
    /// what QUICK is for (log several items in a row). Chip logs park their id
    /// here and the follow skips it; every other path (staging plate, recents
    /// hold-to-log, photo analysis) still follows as before.
    @State private var quickLoggedID: UUID?

    private var displayedFavorites: [FavoriteFood] {
        if filterToHypoTreatments {
            return store.state.favoriteFoodValues.filter(\.isHypoTreatment)
        }
        return store.state.favoriteFoodValues
    }

    private var entryModel: HypoFilteredEntryModel {
        HypoFilteredEntryModel.make(
            hypoFavoriteCount: displayedFavorites.count,
            filterToHypoTreatments: filterToHypoTreatments
        )
    }

    private var searchModel: FoodHistorySearchModel {
        FoodHistorySearchModel.make(
            query: searchText,
            recents: store.state.recentMealEntries,
            results: store.state.mealHistoryResults
        )
    }

    var body: some View {
        // Resolve the structural model once per render (it filters favourites).
        let model = entryModel
        // Same for the search model — it filters + merges two collections.
        let search = searchModel
        // NavigationStack, not NavigationView: navigationDestination modifiers
        // (relog + ASK AI) are silently ignored inside NavigationView.
        return NavigationStack {
            ScrollViewReader { scrollProxy in
            List {
                if filterToHypoTreatments {
                    if model.showsEmptyHypoMessage {
                        Section {
                            DOSEmptyState(
                                title: "NO HYPO TREATMENTS CONFIGURED",
                                detail: "Add hypo treatments in Favorites to see them here"
                            )
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

                recentsSection(search)

                if model.showsEscapeRow {
                    escapeSection
                }
            }
            .listStyle(.grouped)
            .searchable(text: $searchText, prompt: "Search foods...")
            // Follow the just-logged entry: once the reloaded recents contain
            // it, bring its (still glowing) row into view so the user sees
            // where the meal landed.
            .onChange(of: store.state.recentMealEntries) { _, recents in
                guard let id = addedHighlighter.highlightedID,
                      id != quickLoggedID,
                      recents.contains(where: { $0.id == id }) else { return }
                withAnimation(AnimationTokens.easeStandard) {
                    scrollProxy.scrollTo(id, anchor: .center)
                }
            }
            // Reaching past the in-memory recents into the full history
            // (DMNC-1484). Debounced so a burst of keystrokes costs one query.
            .onChange(of: searchText) { _, newValue in
                debounceHistorySearch(newValue)
            }
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
                            .foregroundStyle(AmberTheme.amberDark)
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
                .animation(AnimationTokens.easeStandard, value: toast.meal)
            }
            // No .navigationBarHidden: FoodPhotoAnalysisView's title + Cancel live
            // in the toolbar, which the parent NavigationStack's bar hosts.
            .navigationDestination(item: $relogMeal) { meal in
                FoodPhotoAnalysisView(relogMeal: meal)
                    .environmentObject(store)
            }
            .navigationDestination(isPresented: $askAINavigating) {
                FoodPhotoAnalysisView()
                    .environmentObject(store)
            }
            }
        }
        .sheet(isPresented: $showingFavoriteManagement) {
            FavoriteManagementView()
                .environmentObject(store)
        }
        .onAppear {
            store.dispatch(.loadFavoriteFoodValues)
            store.dispatch(.loadRecentMealEntries)
            // A result that landed AFTER the last onDisappear is still resident
            // (the middleware publisher outlives the sheet), so a reopen with the
            // same query would paint cached rows before the fresh read. Drop it,
            // then re-arm if the field still holds a searchable query — on a
            // fresh sheet `searchText` is "" and this is a no-op.
            clearHistoryResults()
            debounceHistorySearch(searchText)
        }
        // Re-arm after backgrounding. A debounce timer that fired while the scene
        // was inactive was swallowed by the middleware's `.active` guard, and the
        // middleware deliberately does not re-trigger on `.setAppState(.active)`
        // — so without this the sheet spins forever: `searchText` is unchanged,
        // so its `.onChange` never re-fires. Guarded on `isSearching` so a
        // healthy, already-answered query doesn't re-query on every foreground.
        .onChange(of: store.state.appState) { _, phase in
            guard phase == .active, searchModel.isSearching else { return }
            debounceHistorySearch(searchText)
        }
        // Attached to the NavigationStack, NOT the List: pushing a destination
        // (relog plate / ASK AI) tears the List down, and clearing results there
        // would leave a stale query searching forever when the user pops back.
        .onDisappear {
            searchDebounceTask?.cancel()
            searchDebounceTask = nil
            clearHistoryResults()
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
                withAnimation(AnimationTokens.easeSnap) {
                    quickExpanded.toggle()
                }
            } label: {
                HStack(spacing: DOSSpacing.xs) {
                    Text("QUICK").dosHeader()
                    Image(systemName: "chevron.right")
                        .font(DOSTypography.mono(size: 9, weight: .semibold))
                        .foregroundStyle(AmberTheme.amber)
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
    private func recentsSection(_ search: FoodHistorySearchModel) -> some View {
        Section {
            if search.rows.isEmpty {
                if searchText.isEmpty {
                    Text("Log your first meal to see recents here")
                        .font(DOSTypography.bodySmall)
                        .foregroundStyle(AmberTheme.amber)
                } else if search.isSearching {
                    searchingRow
                } else {
                    Text("No matches for \"\(searchText)\"")
                        .font(DOSTypography.bodySmall)
                        .foregroundStyle(AmberTheme.amber)
                }
            } else {
                ForEach(search.rows) { meal in
                    // Tap stages, hold insta-logs. No context menu — it can't
                    // coexist with the hold recognizer (DMNC-796 KTD-3). The
                    // swipe affordance hangs off the hold wrapper, not inside
                    // the row, so it reliably reaches the List row.
                    HoldToCommitProgress(
                        onTap: { openOnStagingPlate(meal) },
                        onCommit: { logRecent(meal) }
                    ) {
                        MealItemRow(meal: meal, variant: .recent)
                    }
                    .id(meal.id)
                    .dosAddedHighlight(addedHighlighter.highlightedID == meal.id)
                    .swipeActions(edge: .trailing) {
                        Button {
                            addToFavorites(meal)
                        } label: {
                            Label("Add to Favorites", systemImage: "star")
                        }
                        .tint(AmberTheme.amber)
                    }
                }

                // In-memory matches are already on screen; the history query is
                // still running and may append older foods below them.
                if search.isSearching {
                    searchingRow
                }
            }
        } header: {
            Text("RECENT").dosHeader()
        }
    }

    /// FiguresLoadingView, never a system spinner (StyleGuard rule 6).
    private var searchingRow: some View {
        HStack(spacing: DOSSpacing.xs) {
            FiguresLoadingView.inline
            Text("Searching history...")
                .font(DOSTypography.bodySmall)
                .foregroundStyle(AmberTheme.amberDark)
        }
    }

    // MARK: - Escape Section (filtered mode only)

    /// DMNC-1028: guarantees a way out of the hypo-filtered sheet even with
    /// zero hypo favourites and zero recents. Manual entry only — PHOTO/ASK AI
    /// are deliberately kept out of the hypo flow.
    @ViewBuilder
    private var escapeSection: some View {
        Section {
            manualEntryLink(icon: "keyboard", title: "LOG OTHER FOOD")
        } header: {
            Text("OTHER").dosHeader()
        }
    }

    /// Shared "type a meal + carbs" destination. Used by both the unfiltered
    /// actions section (MANUAL) and the filtered escape row (LOG OTHER FOOD).
    @ViewBuilder
    private func manualEntryLink(icon: String, title: String) -> some View {
        NavigationLink {
            // No .navigationBarHidden here: AddMealView's Cancel/Add live in the
            // toolbar hosted by the parent NavigationStack's bar (post-#72). Hiding
            // it dropped those buttons — a dead-end mid-hypo from the escape row
            // this feature exists to prevent (DMNC-1028).
            AddMealView { time, description, carbs in
                let mealEntry = MealEntry(timestamp: time, mealDescription: description, carbsGrams: carbs)
                store.dispatch(.addMealEntry(mealEntryValues: [mealEntry]))
                addedHighlighter.flash(mealEntry.id)
                DirectNotifications.shared.hapticNotification(.success)
                loggedEntryToast.stage(.meal(mealEntry))
                dismiss()
            }
        } label: {
            HStack {
                Image(systemName: icon)
                    .font(DOSTypography.caption)
                Text(title)
                    .font(DOSTypography.bodySmall)
            }
            .foregroundStyle(AmberTheme.amber)
        }
        // Keep the visible label ("MANUAL" / "LOG OTHER FOOD") as the VoiceOver
        // label so the two rows stay distinguishable; the shared destination is
        // described as a hint, not an overriding label (DMNC-1028 review).
        .accessibilityHint("Log a meal by typing carbs")
    }

    // MARK: - Actions Section

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            // Voice (DMNC-1486). One more row, not a special guest: the
            // transcript lands in `searchText`, which is what makes the ASK AI
            // row below appear at >= 3 chars. There is deliberately no second
            // dispatch path — spoken and typed input are identical downstream.
            DictationControl(
                contextualStrings: foodContextualStrings,
                stopToken: dictationStopToken
            ) { transcript in
                searchText = transcript
            }

            manualEntryLink(icon: "keyboard", title: "MANUAL")

            // SCAN — always available (OFF is free, no API key needed)
            NavigationLink {
                // No .navigationBarHidden here: BarcodeScannerView's Cancel lives
                // in the toolbar, which the parent NavigationStack's bar hosts.
                BarcodeScannerView()
                    .environmentObject(store)
            } label: {
                HStack {
                    Image(systemName: "barcode.viewfinder")
                        .font(DOSTypography.caption)
                    Text("SCAN")
                        .font(DOSTypography.bodySmall)
                }
                .foregroundStyle(AmberTheme.amber)
            }
            // Additive, so the link still activates normally. The scanner starts
            // its AVCaptureSession during the push — possibly before this List's
            // onDisappear lands — so the mic has to come down first, not after.
            .simultaneousGesture(TapGesture().onEnded { dictationStopToken += 1 })

            if store.state.claudeAPIKeyValid || store.state.aiConsentFoodPhoto {
                NavigationLink {
                    FoodPhotoAnalysisView()
                        .environmentObject(store)
                } label: {
                    HStack {
                        Image(systemName: "camera.viewfinder")
                            .font(DOSTypography.caption)
                        Text("PHOTO")
                            .font(DOSTypography.bodySmall)
                    }
                    .foregroundStyle(AmberTheme.amber)
                }
                .simultaneousGesture(TapGesture().onEnded { dictationStopToken += 1 })

                // NL text parsing — appears when search text >= 3 chars
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 {
                    if store.state.foodAnalysisLoading {
                        HStack {
                            FiguresLoadingView.inline
                            Text("Analyzing...")
                                .font(DOSTypography.bodySmall)
                                .foregroundStyle(AmberTheme.amber)
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
                            // Guard: only dispatch if not already loading/loaded.
                            // Consent gate matters: without it the middleware
                            // swallows analyzeFoodText silently and the loading
                            // flag would stick forever — the destination shows
                            // the consent screen instead, and a re-tap after
                            // granting starts a real analysis.
                            if store.state.aiConsentFoodPhoto,
                               !store.state.foodAnalysisLoading, store.state.foodAnalysisResult == nil {
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
                                    .foregroundStyle(AmberTheme.amberDark)
                            }
                            .foregroundStyle(AmberTheme.amber)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recognition bias

    /// The single biggest quality lever in voice input (DMNC-1486 D5/R3).
    ///
    /// `SFSpeechRecognizer.contextualStrings` takes ~100 short phrases and
    /// weights them during decoding, so seeding it with the foods THIS user
    /// actually logs is what makes "Dextro Energy" and German food nouns come
    /// back spelled right instead of phonetically mangled. Keyboard dictation
    /// cannot do this at all — it is the reason an in-app mic exists.
    ///
    /// Favourites first (the foods worth one tap are the foods most likely to be
    /// spoken), then recents newest-first. Deduped with `lowercased()`, which
    /// folds non-ASCII — the SQL `LIKE`/`NOCASE` trap from DMNC-1484 applies to
    /// case folding generally, not just to search.
    private var foodContextualStrings: [String] {
        let candidates = store.state.favoriteFoodValues.map(\.mealDescription)
            + store.state.recentMealEntries.map(\.mealDescription)

        var seen = Set<String>()
        var phrases: [String] = []
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            phrases.append(trimmed)
            if phrases.count == 100 { break }
        }
        return phrases
    }

    // MARK: - Filtering

    /// Favourites stay a purely local filter — the favourites list is small and
    /// fully in memory, so there is nothing further back to reach for.
    private var filteredFavorites: [FavoriteFood] {
        let base = filterToHypoTreatments ? displayedFavorites : store.state.favoriteFoodValues
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.mealDescription.localizedCaseInsensitiveContains(searchText)
        }
    }

    // Recents are NO LONGER a purely local filter: past `minQueryLength`
    // characters the query also goes to the database via `.searchMealHistory`
    // and the two sources are merged by `FoodHistorySearchModel` (DMNC-1484).

    /// Debounced history search. Copies ChartView's proven `DispatchWorkItem`
    /// shape (`App/Views/Overview/ChartView.swift`): cancel the pending task on
    /// every keystroke, re-arm, fire once typing settles. 250ms suits a DB
    /// round-trip — ChartView's 100ms is tuned for local chart math.
    private func debounceHistorySearch(_ raw: String) {
        searchDebounceTask?.cancel()
        searchDebounceTask = nil

        let query = FoodHistorySearchModel.normalizedQuery(raw)
        guard query.count >= FoodHistorySearchModel.minQueryLength else {
            // Back under the threshold (including a cleared field): the
            // in-memory filter is authoritative again, so drop any result set
            // rather than let it resurface behind a shorter query.
            clearHistoryResults()
            return
        }

        // Capture the store itself, not the view struct, so the work item holds
        // exactly what it needs.
        let target = store
        let task = DispatchWorkItem { target.dispatch(.searchMealHistory(query: query)) }
        searchDebounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250), execute: task)
    }

    private func clearHistoryResults() {
        guard store.state.mealHistoryResults != nil else { return }
        store.dispatch(.setMealHistoryResults(results: nil))
    }

    // MARK: - Actions

    private func logFavorite(_ favorite: FavoriteFood) {
        let mealEntry = favorite.toMealEntry()
        store.dispatch(.addMealEntry(mealEntryValues: [mealEntry]))
        store.dispatch(.logFavoriteFood(favoriteFood: favorite))
        DirectNotifications.shared.hapticNotification(.success)
        toast.show(mealEntry)
        addedHighlighter.flash(mealEntry.id)
        // Stay put: the chip the user just tapped must still be under their
        // thumb for the next one.
        quickLoggedID = mealEntry.id
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
        DirectNotifications.shared.hapticNotification(.success)
        toast.show(newEntry)
        addedHighlighter.flash(newEntry.id)
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
        NavigationStack {
            List {
                if store.state.favoriteFoodValues.isEmpty {
                    Text("No favorites yet. Swipe left on a recent meal to add it.")
                        .font(DOSTypography.bodySmall)
                        .foregroundStyle(AmberTheme.amber)
                } else {
                    ForEach(store.state.favoriteFoodValues) { favorite in
                        Button {
                            editingFavorite = favorite
                        } label: {
                            HStack {
                                if favorite.isHypoTreatment {
                                    Image(systemName: "cross.case")
                                        .font(DOSTypography.caption)
                                        .foregroundStyle(AmberTheme.cgaGreen)
                                        .frame(height: 16)
                                } else {
                                    Image(systemName: "star.fill")
                                        .font(DOSTypography.caption)
                                        .foregroundStyle(AmberTheme.amber)
                                        .frame(height: 16)
                                }

                                Text(favorite.mealDescription)
                                    .font(DOSTypography.bodySmall)
                                    .foregroundStyle(AmberTheme.amber)

                                Spacer()

                                if let carbs = favorite.carbsGrams {
                                    Text("\(Int(carbs))g")
                                        .font(DOSTypography.caption)
                                        .foregroundStyle(AmberTheme.amber)
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
                lastUsed: favorite.lastUsed,
                shortLabel: favorite.shortLabel
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
        NavigationStack {
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
                    Button("Cancel", role: .cancel) {
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

