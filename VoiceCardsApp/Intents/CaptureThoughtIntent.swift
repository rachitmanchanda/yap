import AppIntents
import Foundation

struct CaptureThoughtIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture a Thought"
    static let description = IntentDescription("Open Yap directly in its recording state.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        // App Intents cannot directly mutate SwiftUI navigation, so this shared one-shot flag bridges launch.
        AppPreferences.shouldStartCapture = true
        return .result()
    }
}
