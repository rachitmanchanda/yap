import AppIntents

struct VoiceCardsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PasteLastCardIntent(),
            phrases: ["Get my last \(.applicationName) card"],
            shortTitle: "Last Card",
            systemImageName: "doc.on.clipboard"
        )
    }
}
