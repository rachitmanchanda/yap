import Foundation

/// Streams 16 kHz PCM through our relay while the user speaks, keeping Sarvam credentials server-side.
actor SarvamStreamingTranscriptionClient {
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var segments: [String] = []
    private var pendingAudio: [Data] = []
    private var isProviderReady = false
    private var didFail = false
    private var transcriptContinuation: AsyncStream<String>.Continuation?

    func start(
        language: TranscriptionLanguage,
        outputStyle: TranscriptionOutputStyle
    ) -> AsyncStream<String> {
        cancel()
        segments = []
        pendingAudio = []
        isProviderReady = false
        didFail = false

        var components = URLComponents(
            url: SupabaseConfiguration.functionURL(named: "transcribe-stream"),
            resolvingAgainstBaseURL: false
        )!
        components.scheme = "wss"
        components.queryItems = [
            URLQueryItem(name: "language", value: language.sarvamCode),
            URLQueryItem(name: "mode", value: outputStyle.sarvamMode)
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue(
            "Bearer \(accessToken() ?? SupabaseConfiguration.publishableKey)",
            forHTTPHeaderField: "Authorization"
        )
        let task = URLSession.shared.webSocketTask(with: request)
        socket = task
        task.resume()

        let stream = AsyncStream<String> { continuation in
            transcriptContinuation = continuation
        }
        receiver = Task { [weak self] in await self?.receiveMessages() }
        return stream
    }

    func send(pcm16 data: Data) async {
        guard !didFail, !data.isEmpty else { return }
        guard isProviderReady, let socket else {
            // A short bounded buffer hides relay cold starts without growing for a full three minutes.
            pendingAudio.append(data)
            if pendingAudio.count > 150 { pendingAudio.removeFirst() }
            return
        }
        do {
            try await socket.send(.string(audioMessage(for: data)))
        } catch {
            didFail = true
        }
    }

    func finish() async -> String? {
        guard !didFail, let socket else {
            cancel()
            return nil
        }
        do {
            // Give a cold Edge Function a brief chance to connect upstream; otherwise the
            // saved m4a immediately takes the reliable batch-transcription fallback.
            let readinessDeadline = ContinuousClock.now + .milliseconds(600)
            while !isProviderReady, !didFail, ContinuousClock.now < readinessDeadline {
                try await Task.sleep(for: .milliseconds(40))
            }
            guard isProviderReady, !didFail else {
                cancel()
                return nil
            }
            try await socket.send(.string(#"{"type":"flush"}"#))
            let initialCount = segments.count
            let deadline = ContinuousClock.now + .seconds(1.4)
            while ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(80))
                if segments.count > initialCount {
                    try await Task.sleep(for: .milliseconds(180))
                    break
                }
            }
        } catch {
            didFail = true
        }
        let text = segments.joined(separator: " ").nilIfBlank
        cancel()
        return text
    }

    func cancel() {
        receiver?.cancel()
        receiver = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        transcriptContinuation?.finish()
        transcriptContinuation = nil
        pendingAudio = []
        isProviderReady = false
    }

    private func receiveMessages() async {
        while !Task.isCancelled, let socket {
            do {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case .string(let string): data = Data(string.utf8)
                case .data(let value): data = value
                @unknown default: continue
                }
                guard let envelope = try? JSONDecoder().decode(StreamEnvelope.self, from: data) else {
                    continue
                }
                if envelope.type == "provider_ready" {
                    isProviderReady = true
                    let buffered = pendingAudio
                    pendingAudio = []
                    for chunk in buffered {
                        try await socket.send(.string(audioMessage(for: chunk)))
                    }
                } else if envelope.type == "error" {
                    didFail = true
                } else if envelope.type == "data",
                          let transcript = envelope.data?.transcript?.nilIfBlank {
                    if segments.last != transcript { segments.append(transcript) }
                    transcriptContinuation?.yield(segments.joined(separator: " "))
                }
            } catch {
                if !Task.isCancelled { didFail = true }
                break
            }
        }
    }

    private func audioMessage(for data: Data) -> String {
        let payload = StreamAudioMessage(
            audio: .init(data: data.base64EncodedString(), sampleRate: 16_000, encoding: "audio/wav")
        )
        guard let encoded = try? JSONEncoder().encode(payload) else { return "{}" }
        return String(decoding: encoded, as: UTF8.self)
    }

    private func accessToken() -> String? {
        try? AuthSessionStore().load()?.accessToken.nilIfBlank
    }
}

private struct StreamAudioMessage: Encodable {
    struct Audio: Encodable {
        let data: String
        let sampleRate: Int
        let encoding: String

        enum CodingKeys: String, CodingKey {
            case data, encoding
            case sampleRate = "sample_rate"
        }
    }

    let audio: Audio
}

private struct StreamEnvelope: Decodable {
    struct Payload: Decodable {
        let transcript: String?
    }

    let type: String
    let data: Payload?
    let message: String?
}
