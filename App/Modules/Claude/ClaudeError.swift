//
//  ClaudeError.swift
//  DOSBTS
//

import Foundation

enum ClaudeError: LocalizedError {
    case invalidAPIKey
    case rateLimited(retryAfter: TimeInterval)
    case overloaded
    case networkUnavailable
    case requestTimeout
    case apiError(statusCode: Int, message: String)
    case invalidResponse
    case imageTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return LocalizedString("Invalid API key. Check your key in Settings.")
        case .rateLimited(let seconds):
            return String(format: LocalizedString("Rate limited. Try again in %d seconds."), Int(seconds))
        case .overloaded:
            return LocalizedString("Anthropic servers are busy. Try again in a moment.")
        case .networkUnavailable:
            return LocalizedString("No internet connection.")
        case .requestTimeout:
            return LocalizedString("Request timed out. Check your connection.")
        case .apiError(let code, let msg):
            return "API error (\(code)): \(msg)"
        case .invalidResponse:
            return LocalizedString("Unexpected response from AI service.")
        case .imageTooLarge:
            return LocalizedString("Image too large. Try a different photo.")
        }
    }
}
