import Foundation

struct KeyboardDictationSession: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case launching
        case recording
        case stopRequested
        case cancelRequested
        case transcribing
        case awaitingMode
        case insertRequested
        case modeRequested
        case rewriting
        case completed
        case failed
        case consumed
    }

    let id: UUID
    var phase: Phase
    var startedAt: Date?
    var completedText: String?
    var transcriptPreview: String?
    var selectedModeID: String?
    var audioLevel: Float?
    var errorMessage: String?
    var updatedAt: Date

    init(id: UUID = UUID(), phase: Phase = .launching) {
        self.id = id
        self.phase = phase
        audioLevel = nil
        updatedAt = .now
    }
}

/// A tiny App Group state machine lets the main app own audio while the keyboard owns insertion.
struct KeyboardDictationBridge: @unchecked Sendable {
    private static let filename = "KeyboardDictationSession.json"
    private let sessionURL: URL?

    init(sessionURL: URL? = AppGroup.containerURL?.appending(path: Self.filename)) {
        self.sessionURL = sessionURL
    }

    func load() -> KeyboardDictationSession? {
        guard let sessionURL, let data = try? Data(contentsOf: sessionURL) else { return nil }
        return try? JSONDecoder().decode(KeyboardDictationSession.self, from: data)
    }

    func save(_ session: KeyboardDictationSession?) {
        guard let sessionURL else { return }
        guard let session else {
            try? FileManager.default.removeItem(at: sessionURL)
            return
        }
        guard let data = try? JSONEncoder().encode(session) else { return }
        // CFPreferences can maintain separate per-process caches for an app and its keyboard.
        // An atomic file in the physical App Group container provides deterministic handoff.
        try? data.write(to: sessionURL, options: .atomic)
    }

    func begin() -> KeyboardDictationSession {
        let session = KeyboardDictationSession()
        save(session)
        return session
    }

    func update(
        id: UUID,
        phase: KeyboardDictationSession.Phase,
        text: String? = nil,
        error: String? = nil,
        startedAt: Date? = nil,
        transcript: String? = nil,
        selectedModeID: String? = nil,
        audioLevel: Float? = nil
    ) {
        guard var session = load(), session.id == id else { return }
        session.phase = phase
        session.completedText = text ?? session.completedText
        session.errorMessage = error
        session.startedAt = startedAt ?? session.startedAt
        session.transcriptPreview = transcript ?? session.transcriptPreview
        session.selectedModeID = selectedModeID ?? session.selectedModeID
        session.audioLevel = audioLevel ?? session.audioLevel
        session.updatedAt = .now
        save(session)
    }
}
