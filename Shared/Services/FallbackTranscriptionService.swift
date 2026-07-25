import Foundation

struct FallbackTranscriptionService: TranscriptionService {
    let online: any TranscriptionService
    let offline: any TranscriptionService

    func transcribe(
        audioURL: URL,
        language: TranscriptionLanguage,
        outputStyle: TranscriptionOutputStyle,
        vocabularyHints: [String]
    ) async throws -> TranscriptionResult {
        do {
            return try await online.transcribe(
                audioURL: audioURL,
                language: language,
                outputStyle: outputStyle,
                vocabularyHints: vocabularyHints
            )
        } catch {
            let networkMessage = error.localizedDescription
            do {
                return try await offline.transcribe(
                    audioURL: audioURL,
                    language: language,
                    outputStyle: outputStyle,
                    vocabularyHints: vocabularyHints
                )
            } catch {
                throw TranscriptionError.networkAndFallbackFailed(
                    network: networkMessage,
                    fallback: error.localizedDescription
                )
            }
        }
    }
}
