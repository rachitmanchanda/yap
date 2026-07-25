import Foundation

struct AnthropicRewriteService: RewriteService {
    let keys: any APIKeyProviding
    var client: any HTTPClient = URLSessionHTTPClient()

    func rewrite(text: String, mode: ModeDefinition) async throws -> RewriteResult {
        guard let input = text.nilIfBlank else { throw RewriteError.emptyInput }
        let payload = try await message(
            system: mode.prompt + "\nAlso create a factual 4–6 word title.",
            user: """
            Return valid JSON only, with exactly these string keys:
            {"rewrittenText":"...","title":"..."}

            USER TEXT:
            \(input)
            """
        )
        guard let data = payload.data(using: .utf8),
              let result = try? JSONDecoder().decode(StructuredRewrite.self, from: data),
              let rewritten = result.rewrittenText.nilIfBlank,
              let title = result.title.nilIfBlank else {
            throw RewriteError.malformedResponse
        }
        return RewriteResult(rewrittenText: rewritten, title: title)
    }

    func title(for text: String) async throws -> String {
        guard let input = text.nilIfBlank else { throw RewriteError.emptyInput }
        let result = try await message(
            system: "Create a factual 4–6 word title. Do not use quotation marks or end punctuation.",
            user: input
        )
        guard let title = result.trimmingCharacters(in: CharacterSet(charactersIn: "\"' \n.")).nilIfBlank else {
            throw RewriteError.malformedResponse
        }
        return title
    }

    func enhance(transcript: String, knownTerms: [String]) async throws -> TranscriptEnhancement {
        guard transcript.nilIfBlank != nil else { throw RewriteError.emptyInput }
        let terms = knownTerms.isEmpty ? "None yet" : knownTerms.joined(separator: ", ")
        let payload = try await message(
            system: TranscriptEnhancementPrompt.system(knownTerms: terms),
            user: transcript
        )
        return try TranscriptEnhancementPrompt.decode(payload, original: transcript)
    }

    private func message(system: String, user: String) async throws -> String {
        guard let key = try keys.anthropicKey()?.nilIfBlank else { throw RewriteError.missingAPIKey }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AnthropicRequest(
            model: "claude-sonnet-4-6",
            maxTokens: 1_000,
            temperature: 0.6,
            system: system,
            messages: [.init(role: "user", content: user)]
        ))
        let response = try await client.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let envelope = try? JSONDecoder().decode(AnthropicErrorEnvelope.self, from: response.data)
            throw HTTPServiceError.rejected(status: response.statusCode, message: envelope?.error?.message)
        }
        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: response.data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text?.nilIfBlank else {
            throw RewriteError.malformedResponse
        }
        return text
    }
}

private struct StructuredRewrite: Decodable {
    let rewrittenText: String
    let title: String
}

private struct AnthropicRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let maxTokens: Int
    let temperature: Double
    let system: String
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model, temperature, system, messages
        case maxTokens = "max_tokens"
    }
}

private struct AnthropicResponse: Decodable {
    struct Content: Decodable { let type: String; let text: String? }
    let content: [Content]
}

private struct AnthropicErrorEnvelope: Decodable {
    struct Detail: Decodable { let message: String? }
    let error: Detail?
}
