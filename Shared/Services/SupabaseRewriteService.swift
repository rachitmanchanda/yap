import Foundation

/// Rewrites travel through our Edge Function so provider keys and routing can change without an app update.
struct SupabaseRewriteService: RewriteService {
    var client: any HTTPClient = URLSessionHTTPClient()
    private let sessionStore = AuthSessionStore()
    private let latencyStore = RewriteProviderLatencyStore.shared

    func rewrite(text: String, mode: ModeDefinition) async throws -> RewriteResult {
        guard let input = text.nilIfBlank else { throw RewriteError.emptyInput }
        let payload = ManagedRewriteRequest(
            operation: .rewrite,
            text: input,
            mode: .init(id: mode.id, name: mode.name, prompt: mode.prompt),
            knownTerms: nil,
            preferredProvider: await latencyStore.preferredProvider()
        )
        let response = try await perform(payload)
        await latencyStore.record(provider: response.provider, milliseconds: response.latencyMS)
        guard let rewritten = response.text.nilIfBlank else { throw RewriteError.malformedResponse }
        return RewriteResult(
            rewrittenText: rewritten,
            title: response.title?.nilIfBlank ?? rewritten.firstWordsTitle()
        )
    }

    func title(for text: String) async throws -> String {
        guard let input = text.nilIfBlank else { throw RewriteError.emptyInput }
        let response = try await perform(ManagedRewriteRequest(
            operation: .title,
            text: input,
            mode: nil,
            knownTerms: nil,
            preferredProvider: await latencyStore.preferredProvider()
        ))
        await latencyStore.record(provider: response.provider, milliseconds: response.latencyMS)
        guard let title = (response.title ?? response.text).nilIfBlank else {
            throw RewriteError.malformedResponse
        }
        return title
    }

    func enhance(transcript: String, knownTerms: [String]) async throws -> TranscriptEnhancement {
        guard transcript.nilIfBlank != nil else { throw RewriteError.emptyInput }
        let response = try await perform(ManagedRewriteRequest(
            operation: .enhance,
            text: transcript,
            mode: nil,
            knownTerms: knownTerms,
            preferredProvider: await latencyStore.preferredProvider()
        ))
        await latencyStore.record(provider: response.provider, milliseconds: response.latencyMS)
        guard let enhanced = response.text.nilIfBlank else { throw RewriteError.malformedResponse }
        return TranscriptEnhancement(
            text: enhanced,
            changed: response.changed ?? (enhanced != transcript)
        )
    }

    private func perform(_ payload: ManagedRewriteRequest) async throws -> ManagedRewriteResponse {
        var request = URLRequest(url: SupabaseConfiguration.functionURL(named: "rewrite"))
        request.httpMethod = "POST"
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = try? sessionStore.load()?.accessToken.nilIfBlank {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            // The ten-tap development bypass still uses the public client key, never a provider secret.
            request.setValue(
                "Bearer \(SupabaseConfiguration.publishableKey)",
                forHTTPHeaderField: "Authorization"
            )
        }
        request.httpBody = try JSONEncoder().encode(payload)

        let response = try await client.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let envelope = try? JSONDecoder().decode(ManagedRewriteError.self, from: response.data)
            throw HTTPServiceError.rejected(
                status: response.statusCode,
                message: envelope?.error ?? envelope?.message
            )
        }
        return try JSONDecoder().decode(ManagedRewriteResponse.self, from: response.data)
    }
}

private struct ManagedRewriteRequest: Encodable {
    enum Operation: String, Encodable {
        case rewrite, title, enhance
    }

    struct Mode: Encodable {
        let id: String
        let name: String
        let prompt: String
    }

    let operation: Operation
    let text: String
    let mode: Mode?
    let knownTerms: [String]?
    let preferredProvider: String?
}

private struct ManagedRewriteResponse: Decodable {
    let text: String
    let title: String?
    let changed: Bool?
    let provider: String?
    let latencyMS: Double?

    enum CodingKeys: String, CodingKey {
        case text, title, changed, provider
        case latencyMS = "latencyMs"
    }
}

private struct ManagedRewriteError: Decodable {
    let error: String?
    let message: String?
}

/// A tiny persisted EWMA lets the next request prefer whichever provider has been fastest on this device.
private actor RewriteProviderLatencyStore {
    static let shared = RewriteProviderLatencyStore()

    private let defaults = UserDefaults.standard
    private let providers = ["deepseek", "claude"]

    func preferredProvider() -> String? {
        providers
            .compactMap { provider -> (String, Double)? in
                let key = "rewriteLatency.\(provider)"
                guard defaults.object(forKey: key) != nil else { return nil }
                return (provider, defaults.double(forKey: key))
            }
            .min(by: { $0.1 < $1.1 })?
            .0 ?? "deepseek"
    }

    func record(provider: String?, milliseconds: Double?) {
        guard let provider, providers.contains(provider), let milliseconds, milliseconds > 0 else {
            return
        }
        let key = "rewriteLatency.\(provider)"
        let previous = defaults.object(forKey: key) == nil ? milliseconds : defaults.double(forKey: key)
        defaults.set((previous * 0.75) + (milliseconds * 0.25), forKey: key)
    }
}
