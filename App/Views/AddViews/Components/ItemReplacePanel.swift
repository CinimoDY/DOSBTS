//
//  ItemReplacePanel.swift
//  DOSBTS
//
//  Inline REPLACE panel under one expanded staging-plate row (DMNC-1561).
//
//  Type or say a food; pick a candidate from your own history (favourites,
//  PersonalFood, single-food meals) and the row is rewritten in place. An
//  optional last row asks the AI about THIS item only.
//
//  Voice follows the DictationControl rule: the transcript lands in the field
//  and nothing is dispatched until the user taps a row — ASK AI is a paid call.
//

import SwiftUI

struct ItemReplacePanel: View {
    @EnvironmentObject var store: DirectStore

    let itemID: UUID
    /// Recognition bias for the mic (plate items + favourites + recents).
    let contextualStrings: [String]
    /// Bumped by the plate before it pushes a barcode scanner (design doc R1).
    let dictationStopToken: Int
    let onPick: (FoodItemCandidate) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DOSSpacing.xs) {
            HStack {
                Text("Replace item").dosHeader()
                Spacer()
                Button(action: onClose) {
                    Text("CLOSE")
                        .font(DOSTypography.caption)
                        .foregroundStyle(AmberTheme.amberDark)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }

            TextField("Search history or say a food", text: $query)
                .font(DOSTypography.body)
                .foregroundStyle(AmberTheme.amber)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .dosCard(.stat, padding: DOSSpacing.xs)
                .onChange(of: query) { _, newValue in
                    debounceSearch(newValue)
                }

            DictationControl(
                contextualStrings: contextualStrings,
                stopToken: dictationStopToken
            ) { transcript in
                query = transcript
            }

            candidateList

            if showsAskAI {
                askAIRow
            }
        }
        .dosCard(.panel, padding: DOSSpacing.sm)
        .padding(.leading, DOSSpacing.md)
        .onDisappear {
            searchDebounceTask?.cancel()
            searchDebounceTask = nil
            if store.state.plateItemSearchResults != nil {
                store.dispatch(.setPlateItemSearchResults(results: nil))
            }
        }
    }

    // MARK: Private

    @State private var query = ""
    @State private var searchDebounceTask: DispatchWorkItem?
    @State private var showConsentHint = false

    private var normalizedQuery: String {
        FoodHistorySearchModel.normalizedQuery(query)
    }

    private var candidates: [FoodItemCandidate] {
        let normalized = normalizedQuery
        // Drop DB hits answering any other query — an older, slower search can
        // land last because `Store.dispatch` never cancels in-flight work.
        let hits = store.state.plateItemSearchResults.flatMap { $0.query == normalized ? $0 : nil }
        return FoodItemCandidateRanker.rank(
            query: normalized,
            favorites: store.state.favoriteFoodValues,
            recents: store.state.recentMealEntries + (hits?.mealEntries ?? []),
            personalFoods: store.state.personalFoodValues + (hits?.personalFoods ?? [])
        )
    }

    /// Same gate as the Log Meal sheet's PHOTO / ASK AI rows
    /// (UnifiedFoodEntryView), plus the same 3-character threshold.
    private var showsAskAI: Bool {
        (store.state.claudeAPIKeyValid || store.state.aiConsentFoodPhoto)
            && normalizedQuery.count >= FoodHistorySearchModel.minQueryLength
    }

    private var isAskingAI: Bool {
        store.state.foodItemAnalysisLoadingItemID == itemID
    }

    @ViewBuilder
    private var candidateList: some View {
        let rows = candidates
        if normalizedQuery.isEmpty {
            EmptyView()
        } else if rows.isEmpty {
            Text("No matches in your history")
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.amberDark)
        } else {
            ForEach(rows) { candidate in
                Button {
                    onPick(candidate)
                } label: {
                    HStack(spacing: DOSSpacing.xs) {
                        Text(candidate.name)
                            .font(DOSTypography.bodySmall)
                            .foregroundStyle(AmberTheme.amber)
                            .lineLimit(1)
                        Spacer(minLength: DOSSpacing.xs)
                        Text("\(Int(candidate.carbsG.rounded()))g · \(candidate.source.label)")
                            .font(DOSTypography.caption)
                            .foregroundStyle(AmberTheme.amberDark)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(candidate.name), \(Int(candidate.carbsG.rounded())) grams carbs, \(candidate.source.label)")
            }
        }
    }

    @ViewBuilder
    private var askAIRow: some View {
        if isAskingAI {
            HStack(spacing: DOSSpacing.xs) {
                FiguresLoadingView.inline
                Text("Asking AI...")
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.cgaCyan)
            }
        } else {
            Button(action: askAI) {
                HStack(spacing: DOSSpacing.xs) {
                    Image(systemName: "sparkles")
                        .font(DOSTypography.caption)
                    Text("ASK AI: \"\(normalizedQuery.prefix(30))\"")
                        .font(DOSTypography.bodySmall)
                        .lineLimit(1)
                    Spacer()
                }
                .foregroundStyle(AmberTheme.cgaCyan)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // One item-scoped call at a time across the whole plate.
            .disabled(store.state.foodItemAnalysisLoadingItemID != nil)
        }

        if showConsentHint {
            Text("Enable AI food analysis in Settings first.")
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.cgaRed)
        } else if let error = store.state.foodItemAnalysisError, error.itemID == itemID {
            Text(error.message)
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.cgaRed)
        }
    }

    private func askAI() {
        // Without consent the middleware would refuse anyway; say so here
        // rather than spend a round-trip on it.
        guard store.state.aiConsentFoodPhoto else {
            showConsentHint = true
            return
        }
        showConsentHint = false
        let normalized = normalizedQuery
        guard normalized.count >= FoodHistorySearchModel.minQueryLength,
              store.state.foodItemAnalysisLoadingItemID == nil else { return }
        store.dispatch(.analyzeFoodItem(itemID: itemID, query: normalized))
    }

    /// 250 ms debounce, the `DispatchWorkItem` shape from
    /// `UnifiedFoodEntryView.debounceHistorySearch`. Normalized once here; the
    /// middleware echoes this exact string back as the result key.
    private func debounceSearch(_ raw: String) {
        searchDebounceTask?.cancel()
        searchDebounceTask = nil

        let normalized = FoodHistorySearchModel.normalizedQuery(raw)
        guard normalized.count >= FoodHistorySearchModel.minQueryLength else {
            if store.state.plateItemSearchResults != nil {
                store.dispatch(.setPlateItemSearchResults(results: nil))
            }
            return
        }

        let target = store
        let task = DispatchWorkItem { target.dispatch(.searchPlateItems(query: normalized)) }
        searchDebounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250), execute: task)
    }
}
