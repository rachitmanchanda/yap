import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class StreamModel {
    private(set) var cards: [Card] = []
    private(set) var learnedTermCount = 0
    var searchText = ""
    var errorMessage: String?

    private let repository: CardRepository
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
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

    var totalWordCount: Int {
        cards.reduce(into: 0) { count, card in
            count += card.preferredText.split(whereSeparator: \.isWhitespace).count
        }
    }

    var yapsThisWeek: Int {
        guard let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start else {
            return 0
        }
        return cards.lazy.filter { $0.createdAt >= weekStart }.count
    }

    func reload() {
        do {
            cards = try repository.recent()
            learnedTermCount = try context.fetch(FetchDescriptor<PersonalTerm>())
                .lazy
                .filter { $0.kind == .name || $0.useCount >= 3 }
                .count
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
