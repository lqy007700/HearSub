import Foundation

final class OpenAICompatibleTranslationService: Sendable {
    enum ServiceError: LocalizedError {
        case missingBaseURL
        case invalidBaseURL
        case missingAPIKey
        case missingModel
        case invalidResponse
        case noModels
        case requestFailed(Int, String)

        var errorDescription: String? {
            switch self {
            case .missingBaseURL:
                return "OpenAI-compatible translation base URL is empty."
            case .invalidBaseURL:
                return "OpenAI-compatible translation base URL is invalid."
            case .missingAPIKey:
                return "OpenAI-compatible translation API key is empty."
            case .missingModel:
                return "OpenAI-compatible translation model is empty."
            case .invalidResponse:
                return "OpenAI-compatible translation response was invalid."
            case .noModels:
                return "OpenAI-compatible model list was empty."
            case .requestFailed(let statusCode, let body):
                if body.isEmpty {
                    return "OpenAI-compatible translation request failed with HTTP \(statusCode)."
                }
                return "OpenAI-compatible translation request failed with HTTP \(statusCode): \(body)"
            }
        }
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchModels(settings: OpenAICompatibleTranslationSettings) async throws -> [String] {
        let endpoint = try modelsEndpoint(from: settings.baseURL)
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard apiKey.isEmpty == false else { throw ServiceError.missingAPIKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 12

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.requestFailed(httpResponse.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(ModelListResponse.self, from: data)
        let models = decoded.data
            .map(\.id)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        guard models.isEmpty == false else { throw ServiceError.noModels }
        return models
    }

    func translate(
        _ text: String,
        from sourceLanguageID: String,
        to targetLanguageID: String,
        glossary: [String: String],
        settings: OpenAICompatibleTranslationSettings
    ) async throws -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.isEmpty == false else { return "" }

        let endpoint = try chatCompletionsEndpoint(from: settings.baseURL)
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard apiKey.isEmpty == false else { throw ServiceError.missingAPIKey }
        guard model.isEmpty == false else { throw ServiceError.missingModel }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 12

        let payload = ChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(
                    role: "user",
                    content: userPrompt(
                        text: trimmedText,
                        sourceLanguageID: sourceLanguageID,
                        targetLanguageID: targetLanguageID,
                        glossary: glossary
                    )
                )
            ],
            temperature: 0.1,
            maxTokens: max(64, min(512, trimmedText.count * 2 + 32)),
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.requestFailed(httpResponse.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              content.isEmpty == false else {
            throw ServiceError.invalidResponse
        }

        return stripWrappingQuotes(content)
    }

    private var systemPrompt: String {
        """
        You translate live subtitles. Output only the translated subtitle text. Keep it concise, natural, and readable on screen. Do not explain, annotate, or add alternatives.
        """
    }

    private func userPrompt(
        text: String,
        sourceLanguageID: String,
        targetLanguageID: String,
        glossary: [String: String]
    ) -> String {
        var lines = [
            "Source language: \(sourceLanguageID)",
            "Target language: \(targetLanguageID)",
        ]

        let glossaryLines = glossary
            .map { key, value in
                (
                    key.trimmingCharacters(in: .whitespacesAndNewlines),
                    value.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { $0.0.isEmpty == false && $0.1.isEmpty == false }
            .sorted { lhs, rhs in
                lhs.0.localizedCaseInsensitiveCompare(rhs.0) == .orderedAscending
            }

        if glossaryLines.isEmpty == false {
            lines.append("Glossary:")
            lines.append(contentsOf: glossaryLines.map { "\($0.0) => \($0.1)" })
        }

        lines.append("Subtitle:")
        lines.append(text)
        return lines.joined(separator: "\n")
    }

    private func chatCompletionsEndpoint(from rawBaseURL: String) throws -> URL {
        try endpoint(from: rawBaseURL, suffix: "chat/completions")
    }

    private func modelsEndpoint(from rawBaseURL: String) throws -> URL {
        try endpoint(from: rawBaseURL, suffix: "models")
    }

    private func endpoint(from rawBaseURL: String, suffix: String) throws -> URL {
        let trimmed = rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw ServiceError.missingBaseURL }
        guard var components = URLComponents(string: trimmed),
              components.scheme?.isEmpty == false,
              components.host?.isEmpty == false else {
            throw ServiceError.invalidBaseURL
        }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix(suffix) {
            guard let url = components.url else {
                throw ServiceError.invalidBaseURL
            }
            return url
        }

        if path == "v1" {
            components.path = "/v1/\(suffix)"
        } else if path.isEmpty {
            components.path = "/v1/\(suffix)"
        } else if path.hasSuffix("chat/completions"), suffix == "models" {
            let prefix = path.dropLast("chat/completions".count)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = prefix.isEmpty ? "/v1/models" : "/\(prefix)/models"
        } else {
            components.path = "/" + path + "/\(suffix)"
        }

        guard let url = components.url else {
            throw ServiceError.invalidBaseURL
        }
        return url
    }

    private func stripWrappingQuotes(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let quotePairs: [(Character, Character)] = [
            ("\"", "\""),
            ("'", "'"),
            ("\u{201C}", "\u{201D}"),
            ("\u{300C}", "\u{300D}"),
            ("\u{300E}", "\u{300F}"),
        ]

        for (opening, closing) in quotePairs {
            if trimmed.first == opening, trimmed.last == closing, trimmed.count >= 2 {
                trimmed.removeFirst()
                trimmed.removeLast()
                return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return trimmed
    }
}

private struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct ModelListResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}
