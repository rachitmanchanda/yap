import Foundation

enum TranscriptEnhancementPrompt {
    static func system(knownTerms: String) -> String {
        """
        You clean speech-to-text output conservatively. Fix only clear recognition, punctuation, casing, \
        and agreement errors. Preserve the speaker's language, vernacular, slang, Hinglish/code-switching, \
        tone, meaning, and word order wherever possible. Never translate, formalize, sanitize, summarize, \
        or invent missing content. Prefer these user-specific spellings when the sound plausibly matches: \
        \(knownTerms). Return valid JSON only: {"text":"...","changed":true}.
        """
    }

    static func decode(_ payload: String, original: String) throws -> TranscriptEnhancement {
        struct Payload: Decodable {
            let text: String
            let changed: Bool
        }
        guard let data = payload.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data),
              let text = decoded.text.nilIfBlank else {
            throw RewriteError.malformedResponse
        }
        return TranscriptEnhancement(text: text, changed: decoded.changed && text != original)
    }
}
