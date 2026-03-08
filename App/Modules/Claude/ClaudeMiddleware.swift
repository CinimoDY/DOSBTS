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
                DirectLog.info("AI consent not granted for food photo analysis")
                return Empty().eraseToAnyPublisher()
            }

            return Future<DirectAction, DirectError> { promise in
                Task {
                    do {
                        let result = try await service.value.analyzeFood(imageData: imageData)
                        promise(.success(.setFoodAnalysisResult(result: result)))
                    } catch {
                        promise(.success(.setFoodAnalysisError(error: error.localizedDescription)))
                    }
                }
            }
            .eraseToAnyPublisher()

        case .validateClaudeAPIKey(let apiKey):
            return Future<DirectAction, DirectError> { promise in
                Task {
                    do {
                        try await service.value.validateAPIKey(apiKey)
                        // Key is valid — save to Keychain
                        try? KeychainService.save(key: ClaudeService.keychainKey, value: apiKey)
                        promise(.success(.setClaudeAPIKeyValid(isValid: true)))
                    } catch let error as ClaudeError {
                        switch error {
                        case .invalidAPIKey:
                            promise(.success(.setClaudeAPIKeyValid(isValid: false)))
                        default:
                            // Network error — save key anyway, validate on first use
                            try? KeychainService.save(key: ClaudeService.keychainKey, value: apiKey)
                            promise(.success(.setClaudeAPIKeyValid(isValid: true)))
                        }
                    } catch {
                        try? KeychainService.save(key: ClaudeService.keychainKey, value: apiKey)
                        promise(.success(.setClaudeAPIKeyValid(isValid: true)))
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
