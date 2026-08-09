//
//  FoodPhotoAnalysisView.swift
//  DOSBTS
//

import PhotosUI
import SwiftUI

// MARK: - FoodPhotoAnalysisView

struct FoodPhotoAnalysisView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore
    @EnvironmentObject var addedHighlighter: AddedEntryHighlighter
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Relog mode: hydrates staging plate from this past meal, preserves `analysisSessionId`, skips correction tracking.
    var relogMeal: MealEntry?

    var body: some View {
        // Pushed onto the caller's NavigationStack in every path (PHOTO / ASK AI /
        // relog / scan-success). No inner navigation container — a nested
        // NavigationStack drops the title + Cancel toolbar (see
        // docs/solutions/ui-bugs/navigationbarhidden-drops-toolbar-on-navigationstack-push.md).
        formContent
    }

    private var formContent: some View {
        Form {
            Group {
                if !store.state.aiConsentFoodPhoto, relogMeal == nil {
                    consentSection
                } else if store.state.foodAnalysisLoading {
                    loadingSection
                } else if let result = store.state.foodAnalysisResult {
                    resultsSection(result)
                } else if let error = store.state.foodAnalysisError {
                    errorSection(error)
                } else if relogMeal != nil {
                    loadingSection // brief placeholder until hydrateRelogIfNeeded() runs on onAppear
                } else {
                    photoPickerSection
                }
            }
            .listRowBackground(AmberTheme.dosBlack)
            .listRowSeparatorTint(AmberTheme.borderFaint)
        }
        .scrollContentBackground(.hidden)
        .background(AmberTheme.dosBlack.ignoresSafeArea())
        .onAppear { hydrateRelogIfNeeded() }
        .navigationDestination(isPresented: Binding(
            get: { scanTargetID != nil },
            set: { active in if !active { scanTargetID = nil } }
        )) {
            // Guard by stable UUID so a concurrent deletion can't push a blank screen
            if let itemID = scanTargetID, stagedItems.contains(where: { $0.id == itemID }) {
                ItemBarcodeScannerView { scannedEstimate in
                    if let currentIdx = stagedItems.firstIndex(where: { $0.id == itemID }),
                       let scannedItem = scannedEstimate.items.first {
                        let amount = parseBaseServingG(scannedItem.servingSize)
                        let ratio: Double? = amount.flatMap { $0 > 0 ? scannedItem.carbsG / $0 : nil }
                        // Update in-place (preserve ID so ForEach doesn't re-render)
                        stagedItems[currentIdx].name = scannedItem.name
                        stagedItems[currentIdx].carbsG = scannedItem.carbsG
                        stagedItems[currentIdx].baseServingG = amount
                        stagedItems[currentIdx].currentAmountG = amount
                        stagedItems[currentIdx].carbsPerG = ratio
                    }
                }
            }
        }
        .dosNavigationTitle("AI Meal Analysis")
        // Pushed onto the caller's NavigationStack: suppress the system back
        // button so the explicit Cancel is the sole leading control.
        .navigationBarBackButtonHidden(true)
        // Protect an analyzed/staged meal (result, edited portions, follow-ups)
        // from a stray swipe-down that would tear down the whole Log Meal sheet —
        // Cancel / Log Meal use programmatic dismiss() and are unaffected. Empty
        // entry states (consent / photo picker) stay swipe-dismissible.
        .interactiveDismissDisabled(store.state.foodAnalysisResult != nil || !stagedItems.isEmpty)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel", role: .cancel) {
                    store.dispatch(.setFoodAnalysisResult(result: nil))
                    store.dispatch(.setFoodAnalysisLoading(isLoading: false))
                    dismiss()
                }
            }
        }
        .onChange(of: store.state.foodAnalysisLoading) { _, isLoading in
            if !isLoading, store.state.foodAnalysisResult != nil {
                DirectNotifications.shared.hapticNotification(.success)
            }
        }
        .onDisappear {
            // scanTargetID is set synchronously on tap, before onDisappear fires during a push —
            // unlike isItemScanActive (set in the destination's onAppear, which is too late).
            guard scanTargetID == nil else { return }
            // Clear stale state when view is truly popped (back swipe or cancel)
            stopProgressTimer()
            store.dispatch(.setFoodAnalysisResult(result: nil))
            store.dispatch(.setFoodAnalysisLoading(isLoading: false))
            stagedItems = []
            editDescription = ""
            followUpHistory = []
            followUpText = ""
            followUpRoundsUsed = 0
            isFollowingUp = false
            followUpError = nil
            portionMultiplier = 1.0
            baseStagedItems = []
            customPortionText = ""
        }
    }

    // MARK: Private

    @State private var selectedItem: Any?
    @State private var showCamera = false
    @State private var showConsentSheet = false
    // Staging plate state
    @State private var stagedItems: [EditableFoodItem] = []
    @State private var editDescription = ""
    @State private var editTimestamp = Date()
    @State private var didHydrateRelog = false
    @FocusState private var focusedItemID: UUID?

    // Inline item barcode scan — UUID guards onDisappear from clearing during push
    @State private var scanTargetID: UUID?

    // Portion scaling state
    @State private var portionMultiplier: Double = 1.0
    @State private var baseStagedItems: [EditableFoodItem] = []
    @State private var customPortionText = ""

    // Conversational follow-up state
    @State private var followUpHistory: [ConversationTurn] = []
    @State private var followUpText = ""
    @State private var isFollowingUp = false
    @State private var followUpError: String?
    @State private var followUpRoundsUsed = 0

    // Progress animation
    @State private var analysisPhase = 0
    @State private var progressTimer: Timer?

    private let analysisPhases = [
        "Identifying foods...",
        "Estimating portions...",
        "Calculating nutrition...",
        "Finalizing results...",
    ]

    // Auto-computed totals from staged items
    // Show scaled carbs in the banner (base × multiplier)
    private var computedCarbs: Double {
        stagedItems.reduce(0) { $0 + $1.carbsG } * portionMultiplier
    }

    /// Recognition bias for the CLARIFY mic: the foods already on the plate are
    /// exactly the nouns a clarification is most likely to name ("the OAT MILK
    /// was a big glass"). Cheap, and it needs no store access.
    private var followUpContextualStrings: [String] {
        stagedItems.map(\.name)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // Whether the portion picker should show (single-item barcode result with known serving)
    private var showPortionPicker: Bool {
        guard stagedItems.count == 1, let base = stagedItems.first?.baseServingG else { return false }
        return base > 0
    }

    private var consentSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(DOSTypography.mono(size: 48))
                    .foregroundStyle(AmberTheme.amber)

                Text("AI-powered food analysis requires sending your photo and food preferences to Anthropic (Claude AI).")
                    .font(DOSTypography.body)
                    .multilineTextAlignment(.center)

                Button("Set Up AI Analysis") {
                    showConsentSheet = true
                }
                .buttonStyle(.dosPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .sheet(isPresented: $showConsentSheet) {
            AIConsentView {
                store.dispatch(.setAIConsentFoodPhoto(enabled: true))
            }
        }
    }

    // MARK: - Loading with progress phases

    private var loadingSection: some View {
        Section {
            VStack(spacing: DOSSpacing.md) {
                FiguresLoadingView(dotSize: DOSSpacing.xs, spacing: DOSSpacing.xxs)

                Text(analysisPhases[analysisPhase])
                    .font(DOSTypography.body)
                    .foregroundStyle(AmberTheme.amber)
                    .animation(AnimationTokens.adapted(animation: AnimationTokens.easeStandard, reduceMotion: reduceMotion), value: analysisPhase)

                dosProgressBar
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .onAppear { startProgressTimer() }
            .onDisappear { stopProgressTimer() }
        }
    }

    private var dosProgressBar: some View {
        let filled = analysisPhase + 1
        let total = analysisPhases.count
        let bar = String(repeating: "=", count: filled * 3) + String(repeating: " ", count: (total - filled) * 3)
        return Text("[\(bar)]")
            .font(DOSTypography.caption)
            .foregroundStyle(AmberTheme.amberDark)
    }

    private func startProgressTimer() {
        analysisPhase = 0
        progressTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            if analysisPhase < analysisPhases.count - 1 {
                analysisPhase += 1
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - Photo picker

    private var photoPickerSection: some View {
        Section(
            content: {
                photosPickerButton

                Button(action: { showCamera = true }) {
                    Label("Take Photo", systemImage: "camera")
                }
                .sheet(isPresented: $showCamera) {
                    CameraView { image in
                        analyzeImage(image)
                    }
                }
            },
            header: {
                Label {
                    Text("Food photo")
                } icon: {
                    AppleIcon().frame(width: 16, height: 16)
                }
                .dosHeader()
            },
            footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Take a photo of your meal to estimate nutritional content using Claude AI.")
                    if store.state.thumbCalibrationMM != nil {
                        Text("Hold your thumb next to the food for better portion accuracy.")
                            .foregroundStyle(AmberTheme.cgaGreen)
                    }
                    if store.state.claudeAPIKeyValid {
                        Text("Estimated cost: typically less than $0.01 per analysis")
                            .foregroundStyle(AmberTheme.amber)
                    } else {
                        Text("Set up your API key in Settings first.")
                            .foregroundStyle(AmberTheme.cgaRed)
                    }
                }
            }
        )
    }

    private var photosPickerButton: some View {
        PhotosPicker(selection: Binding(
            get: { selectedItem as? PhotosPickerItem },
            set: { selectedItem = $0 }
        ), matching: .images) {
            Label("Choose from Library", systemImage: "photo")
        }
        .onChange(of: selectedItem as? PhotosPickerItem) { _, item in
            guard let item = item else { return }
            handlePhotoSelection(item)
        }
    }

    // MARK: - Error

    private func errorSection(_ error: String) -> some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(DOSTypography.mono(size: 36))
                    .foregroundStyle(AmberTheme.cgaRed)

                Text(error)
                    .font(DOSTypography.body)
                    .foregroundStyle(AmberTheme.cgaRed)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    // setFoodAnalysisLoading(false) reducer nils out both error and result
                    store.dispatch(.setFoodAnalysisLoading(isLoading: false))
                }
                .foregroundStyle(AmberTheme.amber)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Staging Plate Results

    private func resultsSection(_ result: NutritionEstimate) -> some View {
        Group {
            // Empty results guard
            if result.items.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "questionmark.circle")
                            .font(DOSTypography.mono(size: 36))
                            .foregroundStyle(AmberTheme.amber)

                        Text("Couldn't identify any foods. Try being more specific or use manual entry.")
                            .font(DOSTypography.body)
                            .foregroundStyle(AmberTheme.amber)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
            }

            // Nutrition banner — auto-computed from plate items
            Section(
                content: {
                    HStack {
                        Text("\(Int(computedCarbs))g C")
                            .font(DOSTypography.body)
                            .foregroundStyle(AmberTheme.amber)
                        Spacer()
                        Text("from \(stagedItems.count) items")
                            .font(DOSTypography.caption)
                            .foregroundStyle(AmberTheme.amber)
                    }
                },
                header: {
                    Label("Nutrition", systemImage: "chart.bar").dosHeader()
                }
            )
            .onAppear {
                populateStagedItems(from: result)
            }
            .onChange(of: store.state.foodAnalysisResult?.description) {
                // Detect follow-up result: replace staged items if we're in a follow-up.
                // Single observer on description (always unique per result) to avoid
                // double-incrementing followUpRoundsUsed when multiple fields change at once.
                if isFollowingUp, let newResult = store.state.foodAnalysisResult {
                    replaceWithFollowUpResult(newResult)
                }
            }
            .onChange(of: store.state.foodAnalysisError) {
                // Reset follow-up spinner on error
                if isFollowingUp && store.state.foodAnalysisError != nil {
                    isFollowingUp = false
                    followUpError = store.state.foodAnalysisError
                }
            }

            // Portion picker — single-item barcode results with known serving
            if showPortionPicker {
                Section(
                    content: {
                        // Preset chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DOSSpacing.sm) {
                                ForEach(store.state.servingPresets) { preset in
                                    Button {
                                        if let base = stagedItems.first?.baseServingG, base > 0 {
                                            portionMultiplier = min(preset.amountML / base, 20)
                                        }
                                    } label: {
                                        Text(preset.label)
                                            .font(DOSTypography.caption)
                                            .padding(.horizontal, DOSSpacing.sm)
                                            .padding(.vertical, 4)
                                            .background(
                                                Rectangle()
                                                    .stroke(AmberTheme.amberDark, lineWidth: 1)
                                            )
                                    }
                                    .foregroundStyle(AmberTheme.amber)
                                }
                            }
                        }

                        // Custom amount entry
                        HStack {
                            TextField("Custom (g/ml)", text: $customPortionText)
                                .font(DOSTypography.caption)
                                .keyboardType(.decimalPad)
                                .frame(width: 120)

                            Button("Apply") {
                                if let custom = Double(customPortionText),
                                   let base = stagedItems.first?.baseServingG,
                                   base > 0, custom > 0 {
                                    portionMultiplier = min(max(custom / base, 0.1), 20)
                                }
                            }
                            .font(DOSTypography.caption)
                            .foregroundStyle(AmberTheme.amber)

                            Spacer()

                            Text("×\(String(format: "%.1f", portionMultiplier))")
                                .font(DOSTypography.body)
                                .foregroundStyle(AmberTheme.amber)
                        }
                    },
                    header: {
                        Label("Portion", systemImage: "scalemass").dosHeader()
                    }
                )
            }

            // Meal details
            Section(
                content: {
                    HStack {
                        Text("Description")
                        TextField("", text: $editDescription)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        DatePicker("Time", selection: $editTimestamp, displayedComponents: [.date, .hourAndMinute])
                    }
                },
                header: {
                    Label {
                        Text("Meal")
                    } icon: {
                        AppleIcon().frame(width: 16, height: 16)
                    }
                    .dosHeader()
                }
            )

            // Staging plate — editable food items
            Section(
                content: {
                    ForEach($stagedItems) { $item in
                        let itemID = item.id
                        StagingPlateRowView(
                            item: $item,
                            onBarcodeRescan: { _ in
                                scanTargetID = itemID
                            },
                            isExpanded: item.isExpanded,
                            onToggleExpand: {
                                withAnimation(AnimationTokens.easeStandard) { item.isExpanded.toggle() }
                            }
                        )
                    }
                    .onDelete { offsets in
                        focusedItemID = nil
                        stagedItems.remove(atOffsets: offsets)
                    }

                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                            .font(DOSTypography.body)
                            .foregroundStyle(AmberTheme.amber)
                    }
                },
                header: {
                    Label("Food items — tap to edit", systemImage: "list.bullet").dosHeader()
                }
            )

            // Inline clarification — text-path only (rawAssistantJSON != nil), confidence not high, rounds < 3
            if result.confidence != .high && followUpRoundsUsed < 3 && result.rawAssistantJSON != nil {
                Section(
                    content: {
                        if isFollowingUp {
                            HStack {
                                FiguresLoadingView.inline
                                Text("Updating estimate...")
                                    .font(DOSTypography.caption)
                                    .foregroundStyle(AmberTheme.amber)
                            }
                        } else {
                            Text("Can you be more specific? (e.g. portion size, brand, cooking method)")
                                .font(DOSTypography.caption)
                                .foregroundStyle(AmberTheme.amber)

                            if let error = followUpError {
                                Text(error)
                                    .font(DOSTypography.caption)
                                    .foregroundStyle(AmberTheme.cgaRed)
                            }

                            HStack {
                                TextField("e.g. about 10 almonds", text: $followUpText)
                                    .font(DOSTypography.body)
                                    .textFieldStyle(.roundedBorder)

                                Button("Send") {
                                    sendFollowUp(result: result)
                                }
                                .foregroundStyle(AmberTheme.amber)
                                .disabled(followUpText.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                            }

                            // Voice clarification (DMNC-1486, option C). Fills the
                            // field only — SEND stays the single dispatch, with the
                            // 3-round / 4000-char caps untouched.
                            DictationControl(contextualStrings: followUpContextualStrings) { transcript in
                                followUpText = transcript
                            }
                        }
                    },
                    header: {
                        Label("Clarify", systemImage: "questionmark.bubble").dosHeader()
                    }
                )
            } else if followUpRoundsUsed >= 3 {
                Section {
                    Text("Best estimate after clarification.")
                        .font(DOSTypography.caption)
                        .foregroundStyle(AmberTheme.amber)
                }
            }

            // Confidence
            Section(
                content: {
                    confidenceRow(result.confidence)

                    if let notes = result.confidenceNotes {
                        Text(notes)
                            .font(DOSTypography.caption)
                            .foregroundStyle(AmberTheme.amber)
                    }
                },
                header: {
                    Label("Confidence", systemImage: "gauge").dosHeader()
                }
            )

            Section {
                Text("AI estimates are informational only. Consult your healthcare provider for medical decisions.")
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.amber)
            }

            Section {
                Button(action: saveAnalysis) {
                    HStack {
                        Spacer()
                        Text("Log Meal")
                            .font(DOSTypography.body)
                        Spacer()
                    }
                }
                .foregroundStyle(AmberTheme.amber)
            }
        }
    }

    private func populateStagedItems(from result: NutritionEstimate) {
        guard stagedItems.isEmpty else { return }
        editDescription = result.description
        let items = result.items.map { item -> EditableFoodItem in
            let amount = parseBaseServingG(item.servingSize)
            let ratio: Double? = amount.flatMap { $0 > 0 ? item.carbsG / $0 : nil }
            return EditableFoodItem(
                name: item.name,
                carbsG: item.carbsG,
                baseServingG: amount,
                currentAmountG: amount,
                carbsPerG: ratio
            )
        }
        stagedItems = items
        baseStagedItems = items // preserve unscaled originals for corrections
        portionMultiplier = 1.0
    }

    /// Parse numeric grams/ml from serving size string like "per 100g", "1 serving (30g)", "15 g"
    private func parseBaseServingG(_ servingSize: String?) -> Double? {
        guard let s = servingSize else { return nil }
        // Look for a number followed by g or ml
        let pattern = #"(\d+(?:\.\d+)?)\s*(?:g|ml|gram)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let range = Range(match.range(at: 1), in: s),
              let value = Double(s[range]),
              value > 0, value <= 2000 else { return nil }
        return value
    }

    private func sendFollowUp(result: NutritionEstimate) {
        guard !isFollowingUp else { return } // double-tap guard
        let answer = String(followUpText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard answer.count >= 2 else { return }

        // Build conversation history if this is the first follow-up
        if followUpHistory.isEmpty, let rawJSON = result.rawAssistantJSON {
            // Sanitize editDescription (user may have edited it)
            let sanitizedDesc = editDescription
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            followUpHistory.append(ConversationTurn(role: "user", content: String(sanitizedDesc.prefix(500))))
            followUpHistory.append(ConversationTurn(role: "assistant", content: rawJSON))
        } else if let rawJSON = result.rawAssistantJSON {
            // Subsequent rounds: append the latest assistant response
            followUpHistory.append(ConversationTurn(role: "assistant", content: rawJSON))
        }

        // Check history cap before dispatching (not in service — avoids unrecoverable error)
        let totalChars = followUpHistory.reduce(0) { $0 + $1.content.count } + answer.count
        if totalChars > 4000 {
            followUpError = "Conversation too long. Log the current estimate or start over."
            return
        }

        // View owns history — append user answer here, service replays verbatim
        followUpHistory.append(ConversationTurn(role: "user", content: answer))

        isFollowingUp = true
        followUpError = nil
        followUpText = ""

        // Dispatch follow-up — do NOT dispatch setFoodAnalysisLoading (keeps staging plate visible)
        store.dispatch(.analyzeFoodText(query: answer, history: followUpHistory))
    }

    private func replaceWithFollowUpResult(_ result: NutritionEstimate) {
        editDescription = result.description
        let newItems = result.items.map { item in
            EditableFoodItem(name: item.name, carbsG: item.carbsG)
        }
        stagedItems = newItems
        baseStagedItems = newItems
        portionMultiplier = 1.0 // follow-up result is already the correct portion
        customPortionText = ""
        isFollowingUp = false
        followUpRoundsUsed += 1
    }

    private func addItem() {
        let newItem = EditableFoodItem(name: "", carbsG: 0, isExpanded: true)
        stagedItems.append(newItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focusedItemID = newItem.id
        }
    }

    private func confidenceRow(_ confidence: NutritionEstimate.Confidence) -> some View {
        HStack {
            Text("Level")
            Spacer()
            switch confidence {
            case .high:
                Text("High")
                    .foregroundStyle(AmberTheme.cgaGreen)
            case .medium:
                Text("Medium")
                    .foregroundStyle(AmberTheme.amber)
            case .low:
                Text("Low")
                    .foregroundStyle(AmberTheme.cgaRed)
            }
        }
    }

    // MARK: - Actions

    private func handlePhotoSelection(_ item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else { return }
            analyzeImage(image)
        }
    }

    private func analyzeImage(_ image: UIImage) {
        store.dispatch(.setFoodAnalysisLoading(isLoading: true))

        Task.detached {
            guard let imageData = image.preparedForVisionAPI() else {
                await MainActor.run {
                    store.dispatch(.setFoodAnalysisError(error: LocalizedString("Failed to prepare image.")))
                }
                return
            }

            await MainActor.run {
                store.dispatch(.analyzeFood(imageData: imageData))
            }
        }
    }

    private func saveAnalysis() {
        let trimmed = editDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let clampedDescription = String(trimmed.prefix(200))

        func clamp(_ value: Double?) -> Double? {
            value.flatMap { $0 >= 0 && $0 <= 10000 ? $0 : nil }
        }

        // For relog mode: preserve the original analysisSessionId (so the new
        // entry stays linked to the same PersonalFood cluster) and skip
        // correction tracking — the user is repeating a known meal with a
        // tweaked portion, not correcting an AI estimate.
        let sessionId: UUID?
        let corrections: [FoodCorrection]
        if let original = relogMeal {
            sessionId = original.analysisSessionId
            corrections = []
        } else {
            // View creates the MealEntry (UUID ownership per learning)
            sessionId = UUID()
            corrections = computeCorrections()
        }

        // In relog mode carry forward the original meal's non-carb macros (the staging
        // plate only edits carbs, so protein/fat/calories/fiber would otherwise be lost).
        let meal = MealEntry(
            id: UUID(),
            timestamp: editTimestamp,
            mealDescription: clampedDescription,
            carbsGrams: clamp(computedCarbs),
            proteinGrams: clamp(relogMeal?.proteinGrams),
            fatGrams: clamp(relogMeal?.fatGrams),
            calories: clamp(relogMeal?.calories),
            fiberGrams: clamp(relogMeal?.fiberGrams),
            analysisSessionId: sessionId
        )

        // Single dispatch — middleware chains to .addMealEntry
        store.dispatch(.saveMealWithCorrections(meal: meal, corrections: corrections))
        store.dispatch(.setFoodAnalysisResult(result: nil))
        addedHighlighter.flash(meal.id)
        dismiss()
    }

    private func hydrateRelogIfNeeded() {
        guard let meal = relogMeal, !didHydrateRelog else { return }
        didHydrateRelog = true
        editTimestamp = Date() // log "now", not the original meal time
        guard store.state.foodAnalysisResult == nil else { return }
        let estimate = meal.toNutritionEstimate(personalFoods: store.state.personalFoodValues)
        store.dispatch(.setFoodAnalysisResult(result: estimate))
    }

    // MARK: - Correction Computation

    private func computeCorrections() -> [FoodCorrection] {
        guard let original = store.state.foodAnalysisResult else { return [] }

        var corrections: [FoodCorrection] = []
        let originalItems = original.items

        func clampName(_ name: String) -> String {
            String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        }

        func clampCarbs(_ value: Double) -> Double {
            max(0, min(value, 10000))
        }

        // Match staged items to original items by position (best-effort)
        for (index, staged) in stagedItems.enumerated() {
            if index < originalItems.count {
                let orig = originalItems[index]
                let stagedName = clampName(staged.name)
                let stagedCarbs = clampCarbs(staged.carbsG)

                let nameChanged = stagedName.lowercased() != orig.name.lowercased()
                let carbsChanged = abs(stagedCarbs - orig.carbsG) > 0.5

                if nameChanged && carbsChanged {
                    corrections.append(FoodCorrection(
                        correctionType: .nameChange,
                        originalName: orig.name,
                        correctedName: stagedName,
                        originalCarbsG: orig.carbsG,
                        correctedCarbsG: stagedCarbs
                    ))
                } else if nameChanged {
                    corrections.append(FoodCorrection(
                        correctionType: .nameChange,
                        originalName: orig.name,
                        correctedName: stagedName,
                        originalCarbsG: orig.carbsG,
                        correctedCarbsG: nil
                    ))
                } else if carbsChanged {
                    corrections.append(FoodCorrection(
                        correctionType: .carbChange,
                        originalName: orig.name,
                        correctedName: nil,
                        originalCarbsG: orig.carbsG,
                        correctedCarbsG: stagedCarbs
                    ))
                }
            } else {
                // Item added by user (not in original)
                corrections.append(FoodCorrection(
                    correctionType: .added,
                    originalName: nil,
                    correctedName: clampName(staged.name),
                    originalCarbsG: nil,
                    correctedCarbsG: clampCarbs(staged.carbsG)
                ))
            }
        }

        // Items in original beyond staged count were deleted
        for orig in originalItems.dropFirst(stagedItems.count) {
            corrections.append(FoodCorrection(
                correctionType: .deleted,
                originalName: orig.name,
                correctedName: nil,
                originalCarbsG: orig.carbsG,
                correctedCarbsG: nil
            ))
        }

        return corrections
    }
}
