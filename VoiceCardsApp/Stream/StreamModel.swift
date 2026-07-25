import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class StreamModel {
    private(set) var cards: [Card] = []
    var searchText = ""
    var errorMessage: String?

    private let repository: CardRepository

    init(context: ModelContext) {
        repository = CardRepository(context: context)
        reload()
    }

    var visibleCards: [Card] {
        guard searchText.nilIfBlank != nil else { return cards }
        let needle = searchText.searchNormalized
        return cards.filter {
            [$0.title, $0.rawText, $0.enhancedText ?? "", $0.processedText ?? ""]
                .contains { $0.searchNormalized.localizedStandardContains(needle) }
        }
    }

    func reload() {
        do {
            cards = try repository.recent()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePin(_ card: Card) {
        perform { try repository.togglePinned(card) }
    }

    func delete(_ card: Card) {
        perform { try repository.delete(card) }
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
