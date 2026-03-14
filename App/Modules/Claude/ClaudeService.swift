//
//  ClaudeService.swift
//  DOSBTS
//

import Foundation
import UIKit

// MARK: - ClaudeService

struct ClaudeService {
    // MARK: Internal

    static let keychainKey = "anthropic-api-key"
    static let model = "claude-haiku-4-5-20251001"

    func analyzeFood(imageData: Data, thumbWidthMM: Double? = nil) async throws -> NutritionEstimate {
        let apiKey = try getAPIKey()

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let base64Image = imageData.base64EncodedString()
        let mediaType = detectMediaType(data: imageData)

        let body: [String: Any] = [
            "model": ClaudeService.model,
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": [
                    ["type": "image", "source": [
                        "type": "base64",
                        "media_type": mediaType,
                        "data": base64Image,
                    ]],
                    ["type": "text", "text": buildPrompt(thumbWidthMM: thumbWidthMM)],
                ]],
            ],
            "output_config": [
                "format": [
                    "type": "json_schema",
                    "schema": nutritionSchema,
                ],
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        return try handleResponse(data: data, response: response)
    }

    func validateAPIKey(_ apiKey: String) async throws {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": ClaudeService.model,
            "max_tokens": 10,
            "messages": [
                ["role": "user", "content": "hi"],
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return // Valid
        case 401:
            throw ClaudeError.invalidAPIKey
        case 429:
            return // Rate limited means key is valid
        default:
            throw ClaudeError.apiError(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: Private

    private var baseURL: URL {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            preconditionFailure("Invalid Anthropic API URL")
        }
        return url
    }

    private let nutritionSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "description": ["type": "string", "description": "Brief meal description"],
            "items": ["type": "array", "items": [
                "type": "object",
                "properties": [
                    "name": ["type": "string"],
                    "carbs_g": ["type": "number"],
                    "protein_g": ["type": "number"],
                    "fat_g": ["type": "number"],
                    "calories": ["type": "number"],
                    "fiber_g": ["type": "number"],
                    "serving_size": ["type": "string", "description": "Estimated portion size"],
                ],
                "required": ["name", "carbs_g"],
                "additionalProperties": false,
            ]],
            "total_carbs_g": ["type": "number"],
            "total_calories": ["type": "number"],
            "confidence": ["type": "string", "enum": ["high", "medium", "low"]],
            "confidence_notes": ["type": "string", "description": "Why confidence is high/medium/low"],
        ],
        "required": ["description", "items", "total_carbs_g", "confidence"],
        "additionalProperties": false,
    ]

    private func buildPrompt(thumbWidthMM: Double?) -> String {
        var prompt = "Analyze this meal photo. Identify each food item and estimate nutritional content. Be specific about portion sizes."
        if let mm = thumbWidthMM {
            prompt += " The user's thumb (width: \(Int(mm))mm at the widest joint) may be visible in the photo next to the food as a size reference. If you can see a thumb, use its known width to estimate portion sizes more accurately. The thumb should be at the same depth as the food for reliable scale."
        }
        return prompt
    }

    private func getAPIKey() throws -> String {
        guard let apiKey = KeychainService.read(key: ClaudeService.keychainKey),
              !apiKey.isEmpty
        else {
            throw ClaudeError.invalidAPIKey
        }
        return apiKey
    }

    private func detectMediaType(data: Data) -> String {
        let bytes = [UInt8](data.prefix(4))
        if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            return "image/jpeg"
        }
        if bytes.count >= 4, bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 {
            return "image/png"
        }
        if bytes.count >= 3, bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46 {
            return "image/gif"
        }
        return "image/jpeg"
    }

    private func handleResponse(data: Data, response: URLResponse) throws -> NutritionEstimate {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
            return try claudeResponse.toNutritionEstimate()

        case 401:
            throw ClaudeError.invalidAPIKey

        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after")
                .flatMap { TimeInterval($0) } ?? 60
            throw ClaudeError.rateLimited(retryAfter: retryAfter)

        case 529:
            throw ClaudeError.overloaded

        default:
            throw ClaudeError.apiError(statusCode: httpResponse.statusCode)
        }
    }
}

// MARK: - ClaudeResponse

private struct ClaudeResponse: Codable {
    var content: [ContentBlock]

    struct ContentBlock: Codable {
        var type: String
        var text: String?
    }

    func toNutritionEstimate() throws -> NutritionEstimate {
        guard let textBlock = content.first(where: { $0.type == "text" }),
              let text = textBlock.text,
              let data = text.data(using: .utf8)
        else {
            throw ClaudeError.invalidResponse
        }

        return try JSONDecoder().decode(NutritionEstimate.self, from: data)
    }
}

// MARK: - UIImage extension

extension UIImage {
    func preparedForVisionAPI(maxDimension: CGFloat = 1024) -> Data? {
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.jpegData(withCompressionQuality: 0.7) { context in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
