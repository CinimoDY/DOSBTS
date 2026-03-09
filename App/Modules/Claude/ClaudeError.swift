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
    case apiError(statusCode: Int)
    case invalidResponse

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
        case .apiError(let code):
            return String(format: LocalizedString("API error (%d). Please try again later."), code)
        case .invalidResponse:
            return LocalizedString("Unexpected response from AI service.")
        }
    }
}
