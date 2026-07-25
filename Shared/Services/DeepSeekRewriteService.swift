import Foundation

struct DeepSeekRewriteService: RewriteService {
    let keys: any APIKeyProviding
    var client: any HTTPClient = URLSessionHTTPClient()

    func rewrite(text: String, mode: ModeDefinition) async throws -> RewriteResult {
        guard let input = text.nilIfBlank else { throw RewriteError.emptyInput }
        let content = try await complete(
            system: mode.prompt + "\nReturn JSON only with rewrittenText and a factual 4–6 word title.",
            user: input,
            json: true
        )
        guard let data = content.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(DeepSeekRewrite.self, from: data),
              let rewritten = decoded.rewrittenText.nilIfBlank,
              let title = decoded.title.nilIfBlank else {
            throw RewriteError.malformedResponse
        }
        return RewriteResult(rewrittenText: rewritten, title: title)
    }

    func title(for text: String) async throws -> String {
        try await complete(
            system: "Create only a factual 4–6 word title without quotation marks or end punctuation.",
            user: text,
            json: false
        )
    }

    func enhance(transcript: String, knownTerms: [String]) async throws -> TranscriptEnhancement {
        guard transcript.nilIfBlank != nil else { throw RewriteError.emptyInput }
        let terms = knownTerms.isEmpty ? "None yet" : knownTerms.joined(separator: ", ")
        let content = try await complete(
            system: TranscriptEnhancementPrompt.system(knownTerms: terms),
            user: transcript,
            json: true
        )
        return try TranscriptEnhancementPrompt.decode(content, original: transcript)
    }

    private func complete(system: String, user: String, json: Bool) async throws -> String {
        guard let key = try keys.deepSeekKey()?.nilIfBlank else { throw RewriteError.missingAPIKey }
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(DeepSeekRequest(
            model: "deepseek-v4-flash",
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)],
            temperature: 0.4,
            maxTokens: 1_000,
            responseFormat: json ? .init(type: "json_object") : nil,
            thinking: .init(type: "disabled")
        ))
        let response = try await client.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw HTTPServiceError.rejected(status: response.statusCode, message: nil)
        }
        let decoded = try JSONDecoder().decode(DeepSeekResponse.self, from: response.data)
        guard let content = decoded.choices.first?.message.content?.nilIfBlank else {
            throw RewriteError.malformedResponse
        }
        return content
    }
}

private struct DeepSeekRewrite: Decodable {
    let rewrittenText: String
    let title: String
}

private struct DeepSeekRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    struct ResponseFormat: Encodable { let type: String }
    struct Thinking: Encodable { let type: String }
    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int
    let responseFormat: ResponseFormat?
    let thinking: Thinking?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, thinking
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }
}

private struct DeepSeekResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
}
