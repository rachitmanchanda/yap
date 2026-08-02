import Foundation

enum TranscriptionLanguage: String, CaseIterable, Sendable {
    case automatic
    case english
    case hindi
    case bengali
    case gujarati
    case kannada
    case malayalam
    case marathi
    case punjabi
    case tamil
    case telugu

    var apiCode: String? {
        switch self {
        case .automatic: nil
        case .english: "en"
        case .hindi: "hi"
        case .bengali: "bn"
        case .gujarati: "gu"
        case .kannada: "kn"
        case .malayalam: "ml"
        case .marathi: "mr"
        case .punjabi: "pa"
        case .tamil: "ta"
        case .telugu: "te"
        }
    }

    var sarvamCode: String {
        switch self {
        case .automatic: "unknown"
        case .english: "en-IN"
        case .hindi: "hi-IN"
        case .bengali: "bn-IN"
        case .gujarati: "gu-IN"
        case .kannada: "kn-IN"
        case .malayalam: "ml-IN"
        case .marathi: "mr-IN"
        case .punjabi: "pa-IN"
        case .tamil: "ta-IN"
        case .telugu: "te-IN"
        }
    }

    var displayName: String {
        self == .hindi ? "Hinglish" : rawValue.capitalized
    }
}

enum TranscriptionOutputStyle: String, Sendable {
    case romanHinglish

    /// Code-mix recognition preserves English words as lexical English instead of spelling
    /// them phonetically. The cleanup pass Romanizes only the Indic-script spans afterward.
    var sarvamMode: String { "codemix" }
}

enum TranscriptionQualityGate {
    /// An apostrophe-split phonetic token is a strong signal that ASR decoded a common word
    /// as sounds (for example, `ta'ima`) rather than vocabulary. Final text is held to a
    /// stricter standard than live preview because quality matters more than a fast paste.
    static func shouldRetryCompletedAudio(_ text: String) -> Bool {
        let tokens = text.split(whereSeparator: { $0.isWhitespace })
        guard tokens.count >= 4 else { return false }

        let commonContractions = Set([
            "i'm", "i've", "i'll", "don't", "can't", "won't", "it's", "that's",
            "we're", "we've", "we'll", "you're", "you've", "you'll", "they're",
            "they've", "they'll", "didn't", "wouldn't", "couldn't", "shouldn't",
            "isn't", "aren't", "wasn't", "weren't", "hasn't", "haven't", "hadn't",
            "let's", "there's", "here's", "what's", "who's"
        ])
        let suspiciousTokens = tokens.filter { token in
            guard token.contains("'") || token.contains("’") else { return false }
            let normalized = token
                .lowercased()
                .trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "'’")))
                .replacingOccurrences(of: "’", with: "'")
            return !commonContractions.contains(normalized)
        }

        return !suspiciousTokens.isEmpty
    }
}

struct TranscriptionResult: Sendable {
    let text: String
    let usedOnDeviceFallback: Bool
}

/// A provider boundary keeps audio capture independent from Whisper, on-device speech, or a future proxy.
protocol TranscriptionService: Sendable {
    func transcribe(
        audioURL: URL,
        language: TranscriptionLanguage,
        outputStyle: TranscriptionOutputStyle,
        vocabularyHints: [String]
    ) async throws -> TranscriptionResult
}

enum TranscriptionError: LocalizedError {
    case missingAPIKey
    case emptyResult
    case unsupportedLocale
    case speechPermissionDenied
    case networkAndFallbackFailed(network: String, fallback: String)
    case lowQualityResult

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "The managed transcription service is not configured."
        case .emptyResult: "No speech was detected. Try speaking a little closer to the microphone."
        case .unsupportedLocale: "On-device speech recognition is unavailable for the selected language."
        case .speechPermissionDenied: "Speech recognition permission is required for offline transcription."
        case .networkAndFallbackFailed(let network, let fallback):
            "Online transcription failed: \(network). Offline transcription also failed: \(fallback)."
        case .lowQualityResult:
            "The transcription was not clear enough to insert. Try speaking again a little closer to the microphone."
        }
    }
}
