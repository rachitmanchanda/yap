import Foundation

struct SelectedRewriteService: RewriteService {
    let anthropic: any RewriteService
    let deepSeek: any RewriteService

    private var selected: any RewriteService {
        AppPreferences.rewriteProvider == .anthropic ? anthropic : deepSeek
    }

    func rewrite(text: String, mode: ModeDefinition) async throws -> RewriteResult {
        try await selected.rewrite(text: text, mode: mode)
    }

    func title(for text: String) async throws -> String {
        try await selected.title(for: text)
    }

    func enhance(transcript: String, knownTerms: [String]) async throws -> TranscriptEnhancement {
        try await selected.enhance(transcript: transcript, knownTerms: knownTerms)
    }
}
