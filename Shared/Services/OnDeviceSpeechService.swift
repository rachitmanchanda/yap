import Foundation
import Speech

struct OnDeviceSpeechService: TranscriptionService {
    func transcribe(
        audioURL: URL,
        language: TranscriptionLanguage,
        outputStyle: TranscriptionOutputStyle,
        vocabularyHints: [String]
    ) async throws -> TranscriptionResult {
        let authorization = await requestAuthorization()
        guard authorization == .authorized else { throw TranscriptionError.speechPermissionDenied }
        let locale = Locale(identifier: language == .automatic ? "en-IN" : language.sarvamCode)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.unsupportedLocale
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        let text: String = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<String, Error>) in
            var task: SFSpeechRecognitionTask?
            task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    task?.cancel()
                    continuation.resume(throwing: error)
                } else if let result, result.isFinal {
                    task?.finish()
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
        guard let text = text.nilIfBlank else { throw TranscriptionError.emptyResult }
        // Whisper is preferred for Hinglish because Apple's locale-specific recognizer may drop code-switches.
        return TranscriptionResult(
            text: RomanScriptNormalizer.normalize(text, for: outputStyle),
            usedOnDeviceFallback: true
        )
    }

    private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }
}
