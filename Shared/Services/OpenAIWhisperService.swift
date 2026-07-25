import Foundation

struct OpenAIWhisperService: TranscriptionService {
    let keys: any APIKeyProviding
    var client: any HTTPClient = URLSessionHTTPClient()

    func transcribe(
        audioURL: URL,
        language: TranscriptionLanguage,
        outputStyle: TranscriptionOutputStyle,
        vocabularyHints: [String]
    ) async throws -> TranscriptionResult {
        guard let key = try keys.openAIKey()?.nilIfBlank else { throw TranscriptionError.missingAPIKey }
        let boundary = "VoiceCards-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try multipartBody(
            audioURL: audioURL,
            language: language,
            vocabularyHints: vocabularyHints,
            boundary: boundary
        )

        let response = try await client.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: response.data)
            throw HTTPServiceError.rejected(status: response.statusCode, message: envelope?.error?.message)
        }
        let payload = try JSONDecoder().decode(WhisperResponse.self, from: response.data)
        guard let text = payload.text.nilIfBlank else { throw TranscriptionError.emptyResult }
        return TranscriptionResult(
            text: RomanScriptNormalizer.normalize(text, for: outputStyle),
            usedOnDeviceFallback: false
        )
    }

    private func multipartBody(
        audioURL: URL,
        language: TranscriptionLanguage,
        vocabularyHints: [String],
        boundary: String
    ) throws -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1\r\n")
        if let language = language.apiCode {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\n\(language)\r\n")
        }
        if !vocabularyHints.isEmpty {
            let hints = vocabularyHints.joined(separator: ", ")
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"prompt\"\r\n\r\nNames and phrases: \(hints)\r\n")
        }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.m4a\"\r\n")
        append("Content-Type: audio/mp4\r\n\r\n")
        body.append(try Data(contentsOf: audioURL))
        append("\r\n--\(boundary)--\r\n")
        return body
    }
}

private struct WhisperResponse: Decodable {
    let text: String
}
