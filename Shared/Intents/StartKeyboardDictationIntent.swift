import AppIntents
import Foundation

/// A system-mediated intent is more reliable than asking an arbitrary keyboard host to open a URL.
struct StartKeyboardDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Yap Dictation"
    static let description = IntentDescription("Open Yap and immediately start recording.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent {
        _ = KeyboardDictationBridge().begin()
        // Returning an explicit OpenIntent is required from keyboard extensions; their host may
        // ignore `openAppWhenRun` on the originating intent even after `perform()` succeeds.
        return .result(opensIntent: OpenVoiceCardsIntent())
    }
}

private enum VoiceCardsDestination: String, AppEnum {
    case capture

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Yap screen")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .capture: "Capture"
    ]
}

private struct OpenVoiceCardsIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Yap Capture"

    @Parameter(title: "Screen")
    var target: VoiceCardsDestination

    init() {
        target = .capture
    }
}
