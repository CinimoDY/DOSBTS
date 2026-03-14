//
//  FoodPhotoAnalysisView.swift
//  DOSBTS
//

import PhotosUI
import SwiftUI

struct FoodPhotoAnalysisView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                if !store.state.aiConsentFoodPhoto {
                    consentSection
                } else if store.state.foodAnalysisLoading {
                    loadingSection
                } else if let result = store.state.foodAnalysisResult {
                    resultsSection(result)
                } else if let error = store.state.foodAnalysisError {
                    errorSection(error)
                } else {
                    photoPickerSection
                }
            }
            .navigationTitle("AI Meal Analysis")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        store.dispatch(.setFoodAnalysisResult(result: nil))
                        store.dispatch(.setFoodAnalysisLoading(isLoading: false))
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: Private

    @State private var selectedItem: Any?
    @State private var showCamera = false
    @State private var showConsentSheet = false
    @State private var showImagePicker = false

    // Editable fields for confirmation
    @State private var editDescription = ""
    @State private var editCarbs: Double?
    @State private var editProtein: Double?
    @State private var editFat: Double?
    @State private var editCalories: Double?
    @State private var editFiber: Double?
    @State private var editTimestamp = Date()

    // Progress animation
    @State private var analysisPhase = 0
    @State private var progressTimer: Timer?

    private let analysisPhases = [
        "Identifying foods...",
        "Estimating portions...",
        "Calculating nutrition...",
        "Finalizing results...",
    ]

    private var consentSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 48))
                    .foregroundStyle(AmberTheme.amber)

                Text("AI-powered food analysis requires sending your photo to Anthropic (Claude AI).")
                    .font(DOSTypography.body)
                    .multilineTextAlignment(.center)

                Button("Set Up AI Analysis") {
                    showConsentSheet = true
                }
                .buttonStyle(.borderedProminent)
                .tint(AmberTheme.amber)
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
                ProgressView()
                    .tint(AmberTheme.amber)

                Text(analysisPhases[analysisPhase])
                    .font(DOSTypography.body)
                    .foregroundStyle(AmberTheme.amber)
                    .animation(.easeInOut(duration: 0.3), value: analysisPhase)

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
                if #available(iOS 16.0, *) {
                    photosPickerButton
                } else {
                    Button(action: { showImagePicker = true }) {
                        Label("Choose from Library", systemImage: "photo")
                    }
                    .sheet(isPresented: $showImagePicker) {
                        CameraView(sourceType: .photoLibrary) { image in
                            analyzeImage(image)
                        }
                    }
                }

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
                Label("Food photo", systemImage: "fork.knife")
            },
            footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Take a photo of your meal to estimate nutritional content using Claude AI.")
                    if store.state.claudeAPIKeyValid {
                        Text("Estimated cost: less than $0.01 per analysis")
                            .foregroundStyle(AmberTheme.amberDark)
                    } else {
                        Text("Set up your API key in Settings first.")
                            .foregroundStyle(AmberTheme.cgaRed)
                    }
                }
            }
        )
    }

    @available(iOS 16.0, *)
    private var photosPickerButton: some View {
        PhotosPicker(selection: Binding(
            get: { selectedItem as? PhotosPickerItem },
            set: { selectedItem = $0 }
        ), matching: .images) {
            Label("Choose from Library", systemImage: "photo")
        }
        .onChange(of: selectedItem as? PhotosPickerItem) { item in
            guard let item = item else { return }
            handlePhotoSelection(item)
        }
    }

    // MARK: - Error

    private func errorSection(_ error: String) -> some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundStyle(AmberTheme.cgaRed)

                Text(error)
                    .font(DOSTypography.body)
                    .foregroundStyle(AmberTheme.cgaRed)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    store.dispatch(.setFoodAnalysisError(error: ""))
                    store.dispatch(.setFoodAnalysisLoading(isLoading: false))
                }
                .foregroundStyle(AmberTheme.amber)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Results with full nutritional breakdown

    private func resultsSection(_ result: NutritionEstimate) -> some View {
        Group {
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
                    Label("Meal", systemImage: "fork.knife")
                }
            )
            .onAppear {
                editDescription = result.description
                editCarbs = result.totalCarbsG
                editProtein = result.totalProteinG
                editFat = result.totalFatG
                editCalories = result.totalCalories
                editFiber = result.totalFiberG
            }

            // Nutrition totals
            Section(
                content: {
                    macroRow(label: "Carbs", value: $editCarbs, unit: "g")
                    macroRow(label: "Protein", value: $editProtein, unit: "g")
                    macroRow(label: "Fat", value: $editFat, unit: "g")
                    macroRow(label: "Calories", value: $editCalories, unit: "kcal")
                    macroRow(label: "Fiber", value: $editFiber, unit: "g")
                },
                header: {
                    Label("Nutrition totals", systemImage: "chart.bar")
                }
            )

            // Per-item breakdown
            Section(
                content: {
                    ForEach(result.items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.name)
                                    .font(DOSTypography.body)
                                Spacer()
                                if let serving = item.servingSize {
                                    Text(serving)
                                        .font(DOSTypography.caption)
                                        .foregroundStyle(AmberTheme.amberDark)
                                }
                            }

                            HStack(spacing: DOSSpacing.sm) {
                                macroTag("\(Int(item.carbsG))g C", color: AmberTheme.amber)

                                if let p = item.proteinG {
                                    macroTag("\(Int(p))g P", color: AmberTheme.amberLight)
                                }

                                if let f = item.fatG {
                                    macroTag("\(Int(f))g F", color: AmberTheme.amberDark)
                                }

                                if let cal = item.calories {
                                    macroTag("\(Int(cal)) kcal", color: AmberTheme.amberDark)
                                }
                            }
                        }
                    }
                },
                header: {
                    Label("Food items", systemImage: "list.bullet")
                }
            )

            // Confidence
            Section(
                content: {
                    confidenceRow(result.confidence)

                    if let notes = result.confidenceNotes {
                        Text(notes)
                            .font(DOSTypography.caption)
                            .foregroundStyle(AmberTheme.amberDark)
                    }
                },
                header: {
                    Label("Confidence", systemImage: "gauge")
                }
            )

            Section {
                Text("AI estimates are informational only. Consult your healthcare provider for medical decisions.")
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.amberDark)
            }

            Section {
                Button(action: saveAnalysis) {
                    HStack {
                        Spacer()
                        Text("Save Meal")
                            .font(DOSTypography.body)
                        Spacer()
                    }
                }
                .foregroundStyle(AmberTheme.amber)
            }
        }
    }

    private func macroRow(label: String, value: Binding<Double?>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("--", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit)
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.amberDark)
                .frame(width: 36, alignment: .leading)
        }
    }

    private func macroTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(DOSTypography.caption)
            .foregroundStyle(color)
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

    @available(iOS 16.0, *)
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

        let meal = MealEntry(
            id: UUID(),
            timestamp: editTimestamp,
            mealDescription: clampedDescription,
            carbsGrams: clamp(editCarbs),
            proteinGrams: clamp(editProtein),
            fatGrams: clamp(editFat),
            calories: clamp(editCalories),
            fiberGrams: clamp(editFiber)
        )

        store.dispatch(.addMealEntry(mealEntryValues: [meal]))
        store.dispatch(.setFoodAnalysisResult(result: nil))
        dismiss()
    }
}
