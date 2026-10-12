//
//  ClaudeMiddleware.swift
//  DOSBTS
//

import Combine
import Foundation

func claudeMiddleware() -> Middleware<DirectState, DirectAction> {
    return claudeMiddleware(service: LazyService<ClaudeService>(initialization: {
        ClaudeService()
    }))
}

private func claudeMiddleware(service: LazyService<ClaudeService>) -> Middleware<DirectState, DirectAction> {
    return { state, action, _ in
        switch action {
        case .analyzeFood(let imageData):
            guard state.aiConsentFoodPhoto else {
                return Empty().eraseToAnyPublisher()
            }

            return Future<DirectAction, DirectError> { promise in
                Task {
                    do {
                        // Read personal context from DirectState (loaded by FoodCorrectionStore)
                        let result = try await service.value.analyzeFood(
                            imageData: imageData,
                            thumbWidthMM: state.thumbCalibrationMM,
                            personalFoods: state.personalFoodValues,
                            recentCorrections: state.recentFoodCorrections
                        )
                        promise(.success(.setFoodAnalysisResult(result: result)))
                    } catch {
                        promise(.success(.setFoodAnalysisError(error: error.localizedDescription)))
                    }
                }
            }
            .eraseToAnyPublisher()

        case .analyzeFoodText(let query, let history):
            guard state.aiConsentFoodPhoto else {
                return Empty().eraseToAnyPublisher()
            }

            return Future<DirectAction, DirectError> { promise in
                Task {
                    do {
                        // Text path: personal dictionary only, no photo corrections
                        let analysisResult = try await service.value.analyzeFoodText(
                            query: query,
                            personalFoods: state.personalFoodValues,
                            history: history
                        )
                        // Attach raw JSON to estimate for multi-turn follow-up
                        var estimate = analysisResult.estimate
                        estimate.rawAssistantJSON = analysisResult.rawAssistantJSON
                        promise(.success(.setFoodAnalysisResult(result: estimate)))
                    } catch {
                        promise(.success(.setFoodAnalysisError(error: error.localizedDescription)))
                    }
                }
            }
            .eraseToAnyPublisher()

        case .analyzeFoodItem(let itemID, let query):
            // Item-scoped ASK AI from the staging plate's REPLACE panel
            // (DMNC-1561). Single-turn on purpose: no history means the full
            // system prompt applies. Answers land in `foodItemAnalysisResult`,
            // NEVER `foodAnalysisResult` — that would replace the whole plate.
            // The reducer already set the loading flag, so a refusal must emit
            // an error rather than return Empty (which would strand the row).
            guard state.aiConsentFoodPhoto else {
                return Just(DirectAction.setFoodItemAnalysisError(
                    itemID: itemID,
                    error: LocalizedString("Enable AI food analysis in Settings first.")
                ))
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()
            }

            return Future<DirectAction, DirectError> { promise in
                Task {
                    do {
                        let analysisResult = try await service.value.analyzeFoodText(
                            query: query,
                            personalFoods: state.personalFoodValues
                        )
                        // An empty answer is an error for THIS row, decided here
                        // so the reducer's waiting-row guard still applies.
                        guard !analysisResult.estimate.items.isEmpty else {
                            promise(.success(.setFoodItemAnalysisError(
                                itemID: itemID,
                                error: LocalizedString("Couldn't identify that food. Try a different name.")
                            )))
                            return
                        }
                        promise(.success(.setFoodItemAnalysisResult(itemID: itemID, estimate: analysisResult.estimate)))
                    } catch {
                        promise(.success(.setFoodItemAnalysisError(itemID: itemID, error: error.localizedDescription)))
                    }
                }
            }
            .eraseToAnyPublisher()

        case .analyzeFoodBarcode(let code):
            // No consent gate — OFF is free, no API key needed
            return Future<DirectAction, DirectError> { promise in
                Task {
                    do {
                        let result = try await lookupBarcodeInOpenFoodFacts(code)
                        promise(.success(.setFoodAnalysisResult(result: result)))
                    } catch {
                        promise(.success(.setFoodAnalysisError(error: error.localizedDescription)))
                    }
                }
            }
            .eraseToAnyPublisher()

        case .validateClaudeAPIKey:
            return Future<DirectAction, DirectError> { promise in
                Task {
                    guard let apiKey = KeychainService.read(key: ClaudeService.keychainKey),
                          !apiKey.isEmpty
                    else {
                        promise(.success(.setClaudeAPIKeyValid(isValid: false)))
                        return
                    }

                    do {
                        try await service.value.validateAPIKey(apiKey)
                        promise(.success(.setClaudeAPIKeyValid(isValid: true)))
                    } catch {
                        if case ClaudeError.invalidAPIKey = error {
                            KeychainService.delete(key: ClaudeService.keychainKey)
                            promise(.success(.setClaudeAPIKeyValid(isValid: false)))
                        } else if case ClaudeError.networkUnavailable = error {
                            // Network unavailable — key might be valid, keep it
                            promise(.success(.setClaudeAPIKeyValid(isValid: true)))
                        } else {
                            // Server error — don't assume key is valid
                            promise(.success(.setClaudeAPIKeyValid(isValid: false)))
                        }
                    }
                }
            }
            .eraseToAnyPublisher()

        case .deleteClaudeAPIKey:
            KeychainService.delete(key: ClaudeService.keychainKey)

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}

// MARK: - Open Food Facts Barcode Lookup (inlined, no separate service file)

/// Direct OFF barcode lookup. For standard Redux flow, dispatch `.analyzeFoodBarcode` instead.
/// Called directly by `ItemBarcodeScannerView` to avoid colliding with `foodAnalysisResult` state.
func lookupBarcodeInOpenFoodFacts(_ code: String) async throws -> NutritionEstimate {
    // Validate barcode: digits only, 8-14 chars
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.allSatisfy(\.isNumber), (8 ... 14).contains(trimmed.count) else {
        throw ClaudeError.invalidResponse
    }

    let urlString = "https://world.openfoodfacts.org/api/v2/product/\(trimmed).json?fields=product_name,brands,serving_size,serving_quantity,nutriments"
    guard let url = URL(string: urlString) else {
        throw ClaudeError.invalidResponse
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = 10
    request.setValue("DOSBTS/1.0 (iOS CGM app)", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        throw ClaudeError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    let offResponse = try JSONDecoder().decode(OFFResponse.self, from: data)

    guard offResponse.status == 1, let product = offResponse.product else {
        throw ClaudeError.invalidResponse
    }

    return product.toNutritionEstimate()
}

// MARK: - Open Food Facts Response Types

struct OFFResponse: Decodable {
    let status: Int
    let product: OFFProduct?
}

struct OFFProduct: Decodable {
    let productName: String?
    let brands: String?
    let servingSize: String?
    let servingQuantity: Double?
    let nutriments: OFFNutriments?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brands
        case servingSize = "serving_size"
        case servingQuantity = "serving_quantity"
        case nutriments
    }

    func toNutritionEstimate() -> NutritionEstimate {
        let name = [brands, productName].compactMap { $0 }.joined(separator: " - ")
        let clampedName = String(name.prefix(200))

        let hasServing = (servingQuantity ?? 0) > 0
        let n = nutriments

        // Use per-serving if available, otherwise per-100g
        let carbs = clampValue(hasServing ? n?.carbohydratesServing : n?.carbohydrates100g)
        let protein = clampValue(hasServing ? n?.proteinsServing : n?.proteins100g)
        let fat = clampValue(hasServing ? n?.fatServing : n?.fat100g)
        let fiber = clampFiber(hasServing ? n?.fiberServing : n?.fiber100g)
        let calories = clampCalories(hasServing ? n?.energyKcalServing : n?.energyKcal100g)
            ?? clampCalories((hasServing ? n?.energyKjServing : n?.energyKj100g).map { $0 / 4.184 })

        let servingLabel = hasServing ? (servingSize ?? "1 serving") : "per 100g"

        // Confidence: medium if we have carbs, low if missing key fields
        let confidence: NutritionEstimate.Confidence = (carbs != nil) ? .medium : .low

        let item = NutritionItem(
            name: clampedName.isEmpty ? "Unknown product" : clampedName,
            carbsG: carbs ?? 0,
            proteinG: protein,
            fatG: fat,
            calories: calories,
            fiberG: fiber,
            servingSize: servingLabel
        )

        return NutritionEstimate(
            description: clampedName.isEmpty ? "Scanned product" : clampedName,
            items: [item],
            totalCarbsG: carbs ?? 0,
            totalCalories: calories,
            confidence: confidence,
            confidenceNotes: hasServing ? "Per serving (\(servingLabel))" : "Per 100g — adjust portion on staging plate"
        )
    }

    // Bounds-clamp before HealthKit: carbs 0-1000, protein/fat 0-500
    private func clampValue(_ value: Double?) -> Double? {
        value.flatMap { $0 >= 0 && $0 <= 1000 ? $0 : nil }
    }

    private func clampCalories(_ value: Double?) -> Double? {
        value.flatMap { $0 >= 0 && $0 <= 10000 ? $0 : nil }
    }

    private func clampFiber(_ value: Double?) -> Double? {
        value.flatMap { $0 >= 0 && $0 <= 200 ? $0 : nil }
    }
}

// OFF nutriments — all optional, handles mixed number/string types
struct OFFNutriments: Decodable {
    let carbohydrates100g: Double?
    let carbohydratesServing: Double?
    let proteins100g: Double?
    let proteinsServing: Double?
    let fat100g: Double?
    let fatServing: Double?
    let fiber100g: Double?
    let fiberServing: Double?
    let energyKcal100g: Double?
    let energyKcalServing: Double?
    let energyKj100g: Double?
    let energyKjServing: Double?

    enum CodingKeys: String, CodingKey {
        case carbohydrates100g = "carbohydrates_100g"
        case carbohydratesServing = "carbohydrates_serving"
        case proteins100g = "proteins_100g"
        case proteinsServing = "proteins_serving"
        case fat100g = "fat_100g"
        case fatServing = "fat_serving"
        case fiber100g = "fiber_100g"
        case fiberServing = "fiber_serving"
        case energyKcal100g = "energy-kcal_100g"
        case energyKcalServing = "energy-kcal_serving"
        case energyKj100g = "energy-kj_100g"
        case energyKjServing = "energy-kj_serving"
    }
}
