import Foundation

struct VernacularTranscriptionService: TranscriptionService {
    let sarvam: any TranscriptionService
    let whisper: any TranscriptionService

    func transcribe(
        audioURL: URL,
        language: TranscriptionLanguage,
        outputStyle: TranscriptionOutputStyle,
        vocabularyHints: [String]
    ) async throws -> TranscriptionResult {
        let preference = AppPreferences.transcriptionProvider
        let primary: any TranscriptionService
        let secondary: any TranscriptionService

        switch preference {
        case .sarvam:
            primary = sarvam
            secondary = whisper
        case .openAI:
            primary = whisper
            secondary = sarvam
        case .automatic:
            // Sarvam is the better first pass for Indic vernacular and Roman Hinglish.
            primary = language == .english ? whisper : sarvam
            secondary = language == .english ? sarvam : whisper
        }

        do {
            return try await primary.transcribe(
                audioURL: audioURL,
                language: language,
                outputStyle: outputStyle,
                vocabularyHints: vocabularyHints
            )
        } catch {
            return try await secondary.transcribe(
                audioURL: audioURL,
                language: language,
                outputStyle: outputStyle,
                vocabularyHints: vocabularyHints
            )
        }
    }
}
