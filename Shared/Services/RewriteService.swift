import Foundation

struct RewriteResult: Sendable, Equatable {
    let rewrittenText: String
    let title: String
}

struct TranscriptEnhancement: Sendable, Equatable {
    let text: String
    let changed: Bool
}

/// The UI depends on this small contract so direct API calls can later become authenticated proxy calls.
protocol RewriteService: Sendable {
    func rewrite(text: String, mode: ModeDefinition) async throws -> RewriteResult
    func title(for text: String) async throws -> String
    func enhance(transcript: String, knownTerms: [String]) async throws -> TranscriptEnhancement
}

enum RewriteError: LocalizedError {
    case missingAPIKey
    case malformedResponse
    case emptyInput

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add an Anthropic API key in Settings."
        case .malformedResponse: "The rewrite service returned an unexpected response."
        case .emptyInput: "There is no text to rewrite."
        }
    }
}
