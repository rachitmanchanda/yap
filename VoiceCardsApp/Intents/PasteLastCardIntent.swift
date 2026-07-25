import AppIntents
import SwiftData

struct PasteLastCardIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Last Yap"
    static let description = IntentDescription("Returns the newest card for use in another Shortcut.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let container = try SharedModelContainer.make()
        let text = try CardRepository(context: container.mainContext).recent(limit: 1).first?.preferredText ?? ""
        return .result(value: text)
    }
}
