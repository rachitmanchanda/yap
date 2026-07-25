import Foundation

/// Audio is sent to our Edge Function so provider credentials never ship in the app.
struct SupabaseTranscriptionService: TranscriptionService {
    var client: any HTTPClient = URLSessionHTTPClient()
    private let sessionStore = AuthSessionStore()

    func transcribe(
        audioURL: URL,
        language: TranscriptionLanguage,
        outputStyle: TranscriptionOutputStyle,
        vocabularyHints: [String]
    ) async throws -> TranscriptionResult {
        let boundary = "VoiceCards-\(UUID().uuidString)"
        var request = URLRequest(url: SupabaseConfiguration.functionURL(named: "transcribe"))
        request.httpMethod = "POST"
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let token = try? sessionStore.load()?.accessToken.nilIfBlank {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            // Temporary ten-tap development bypass; production requests use the user's JWT.
            request.setValue(
                "Bearer \(SupabaseConfiguration.publishableKey)",
                forHTTPHeaderField: "Authorization"
            )
        }

        var body = Data()
        func append(_ value: String) { body.append(Data(value.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"language_code\"\r\n\r\n")
        append("\(language.sarvamCode)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"mode\"\r\n\r\n")
        append("\(outputStyle.sarvamMode)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"vocabulary\"\r\n\r\n")
        append("\(vocabularyHints.joined(separator: "\\n"))\r\n")
        append("--\(boundary)\r\n")
        let fileExtension = audioURL.pathExtension.lowercased()
        let uploadType = fileExtension == "wav" ? "audio/wav" : "audio/mp4"
        let uploadName = fileExtension == "wav" ? "speech.wav" : "speech.m4a"
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(uploadName)\"\r\n")
        append("Content-Type: \(uploadType)\r\n\r\n")
        body.append(try Data(contentsOf: audioURL))
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let response = try await client.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let envelope = try? JSONDecoder().decode(ManagedTranscriptionError.self, from: response.data)
            throw HTTPServiceError.rejected(
                status: response.statusCode,
                message: envelope?.error ?? envelope?.message
            )
        }
        let payload = try JSONDecoder().decode(ManagedTranscriptionResponse.self, from: response.data)
        guard let text = payload.transcript.nilIfBlank else { throw TranscriptionError.emptyResult }
        return TranscriptionResult(text: text, usedOnDeviceFallback: false)
    }
}

private struct ManagedTranscriptionResponse: Decodable {
    let transcript: String
}

private struct ManagedTranscriptionError: Decodable {
    let error: String?
    let message: String?
}
