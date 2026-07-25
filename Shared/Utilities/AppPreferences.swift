import Foundation

enum AppPreferences {
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    static var defaultModeID: String? {
        get { defaults.string(forKey: "defaultModeID") }
        set { defaults.set(newValue, forKey: "defaultModeID") }
    }

    static var retentionDays: Int {
        get {
            let value = defaults.integer(forKey: "retentionDays")
            return value == 0 ? 0 : value
        }
        set { defaults.set(newValue, forKey: "retentionDays") }
    }

    static var automaticClipboardCapture: Bool {
        get {
            guard defaults.object(forKey: "automaticClipboardCapture") != nil else { return true }
            return defaults.bool(forKey: "automaticClipboardCapture")
        }
        set { defaults.set(newValue, forKey: "automaticClipboardCapture") }
    }

    static var shouldStartCapture: Bool {
        get { defaults.bool(forKey: "shouldStartCapture") }
        set { defaults.set(newValue, forKey: "shouldStartCapture") }
    }

    static var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: "hasCompletedOnboarding") }
        set { defaults.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    static var pendingKeyboardSessionID: UUID? {
        get {
            defaults.string(forKey: "pendingKeyboardSessionID")
                .flatMap(UUID.init(uuidString:))
        }
        set {
            defaults.set(newValue?.uuidString, forKey: "pendingKeyboardSessionID")
        }
    }

    static var rewriteProvider: RewriteProviderChoice {
        get { RewriteProviderChoice(rawValue: defaults.string(forKey: "rewriteProvider") ?? "") ?? .anthropic }
        set { defaults.set(newValue.rawValue, forKey: "rewriteProvider") }
    }

    static var transcriptionProvider: TranscriptionProviderChoice {
        get {
            TranscriptionProviderChoice(rawValue: defaults.string(forKey: "transcriptionProvider") ?? "") ?? .automatic
        }
        set { defaults.set(newValue.rawValue, forKey: "transcriptionProvider") }
    }
}

enum RewriteProviderChoice: String, CaseIterable, Sendable {
    case anthropic
    case deepSeek

    var displayName: String { self == .anthropic ? "Claude" : "DeepSeek" }
}

enum TranscriptionProviderChoice: String, CaseIterable, Sendable {
    case automatic
    case sarvam
    case openAI

    var displayName: String {
        switch self {
        case .automatic: "Automatic (vernacular-first)"
        case .sarvam: "Sarvam"
        case .openAI: "OpenAI Whisper"
        }
    }
}
