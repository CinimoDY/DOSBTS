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
                        let result = try await service.value.analyzeFood(imageData: imageData, thumbWidthMM: state.thumbCalibrationMM)
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
