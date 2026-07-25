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

    var sarvamMode: String { "translit" }
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

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "The managed transcription service is not configured."
        case .emptyResult: "No speech was detected. Try speaking a little closer to the microphone."
        case .unsupportedLocale: "On-device speech recognition is unavailable for the selected language."
        case .speechPermissionDenied: "Speech recognition permission is required for offline transcription."
        case .networkAndFallbackFailed(let network, let fallback):
            "Online transcription failed: \(network). Offline transcription also failed: \(fallback)."
        }
    }
}
