import AppIntents
import Foundation

/// iOS 26 can foreground the containing app before the intent performs. This avoids relying on
/// URL opening from a custom keyboard, which iOS does not guarantee for custom URL schemes.
@available(iOS 26.0, *)
struct StartKeyboardDictationForegroundIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Yap and Start Dictation"
    static let description = IntentDescription("Open Yap and immediately start recording.")
    static let supportedModes: IntentModes = [.foreground(.immediate)]
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        _ = KeyboardDictationBridge().begin()
        return .result()
    }
}

enum KeyboardDictationLink {
    static func captureURL(sessionID: UUID) -> URL {
        var components = URLComponents(string: "https://gottayap.com/capture")!
        components.queryItems = [
            URLQueryItem(name: "keyboardSession", value: sessionID.uuidString)
        ]
        // The static base URL and UUID query value make failure impossible in practice.
        return components.url!
    }
}

/// iOS 18–25 use Apple's universal-link intent. iOS 17 performs the same HTTPS handoff through
/// the extension context because `OpenURLIntent` itself was introduced one release later.
@available(iOS 18.0, *)
struct StartKeyboardDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Yap Dictation"
    static let description = IntentDescription("Open Yap and immediately start recording.")
    func perform() async throws -> some IntentResult & OpensIntent {
        let session = KeyboardDictationBridge().begin()
        return .result(opensIntent: OpenURLIntent(KeyboardDictationLink.captureURL(sessionID: session.id)))
    }
}
