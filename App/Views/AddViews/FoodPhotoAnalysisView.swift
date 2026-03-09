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
    @State private var editTimestamp = Date()

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

    private var loadingSection: some View {
        Section {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(AmberTheme.amber)
                Text("Analyzing meal photo...")
                    .font(DOSTypography.body)
                    .foregroundStyle(AmberTheme.amberDark)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

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

    private func resultsSection(_ result: NutritionEstimate) -> some View {
        Group {
            Section(
                content: {
                    HStack {
                        Text("Description")
                        TextField("", text: $editDescription)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Carbs (g)")
                        TextField("", value: $editCarbs, format: .number)
                            .keyboardType(.decimalPad)
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
            }

            Section(
                content: {
                    ForEach(result.items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.name)
                                    .font(DOSTypography.body)
                                Spacer()
                                Text("\(item.carbsG, specifier: "%.0f")g carbs")
                                    .font(DOSTypography.caption)
                                    .foregroundStyle(AmberTheme.amberDark)
                            }

                            if let serving = item.servingSize {
                                Text(serving)
                                    .font(DOSTypography.caption)
                                    .foregroundStyle(AmberTheme.amberDark)
                            }
                        }
                    }
                },
                header: {
                    Label("Food items", systemImage: "list.bullet")
                }
            )

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
        let clampedCarbs = editCarbs.flatMap { $0 >= 0 && $0 <= 1000 ? $0 : nil }

        let meal = MealEntry(
            id: UUID(),
            timestamp: editTimestamp,
            mealDescription: clampedDescription,
            carbsGrams: clampedCarbs
        )

        store.dispatch(.addMealEntry(mealEntryValues: [meal]))
        dismiss()
    }
}
