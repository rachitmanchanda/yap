import AVFoundation
import Foundation

struct SarvamSpeechService: TranscriptionService {
    let keys: any APIKeyProviding
    var client: any HTTPClient = URLSessionHTTPClient()

    func transcribe(
        audioURL: URL,
        language: TranscriptionLanguage,
        outputStyle: TranscriptionOutputStyle,
        vocabularyHints: [String]
    ) async throws -> TranscriptionResult {
        guard let key = try keys.sarvamKey()?.nilIfBlank else { throw TranscriptionError.missingAPIKey }
        let asset = AVURLAsset(url: audioURL)
        let duration = try await asset.load(.duration).seconds
        guard duration <= 30.5 else { throw SarvamError.requiresBatchAPI }

        let boundary = "VoiceCards-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.sarvam.ai/speech-to-text")!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "api-subscription-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ value: String) { body.append(Data(value.utf8)) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"language_code\"\r\n\r\n\(language.sarvamCode)\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"mode\"\r\n\r\n\(outputStyle.sarvamMode)\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.m4a\"\r\n")
        append("Content-Type: audio/mp4\r\n\r\n")
        body.append(try Data(contentsOf: audioURL))
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let response = try await client.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(SarvamErrorEnvelope.self, from: response.data))?.error?.message
            throw HTTPServiceError.rejected(status: response.statusCode, message: message)
        }
        let payload = try JSONDecoder().decode(SarvamResponse.self, from: response.data)
        guard let text = payload.transcript.nilIfBlank else { throw TranscriptionError.emptyResult }
        return TranscriptionResult(text: text, usedOnDeviceFallback: false)
    }
}

enum SarvamError: LocalizedError {
    case requiresBatchAPI

    var errorDescription: String? {
        "Sarvam’s immediate endpoint accepts recordings up to 30 seconds; using Whisper for this longer capture."
    }
}

private struct SarvamResponse: Decodable {
    let transcript: String
}

private struct SarvamErrorEnvelope: Decodable {
    struct Detail: Decodable { let message: String? }
    let error: Detail?
}
