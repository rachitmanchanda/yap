import AppIntents

struct VoiceCardsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureThoughtIntent(),
            phrases: [
                "Capture a thought in \(.applicationName)",
                "Speak to \(.applicationName)"
            ],
            shortTitle: "Capture Thought",
            systemImageName: "waveform.circle.fill"
        )
        AppShortcut(
            intent: PasteLastCardIntent(),
            phrases: ["Get my last \(.applicationName) card"],
            shortTitle: "Last Card",
            systemImageName: "doc.on.clipboard"
        )
    }
}
