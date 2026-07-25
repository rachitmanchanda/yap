import Foundation
import SwiftData

@MainActor
final class CardRepository {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func insert(_ card: Card) throws {
        context.insert(card)
        try context.save()
    }

    func delete(_ card: Card) throws {
        context.delete(card)
        try context.save()
    }

    func togglePinned(_ card: Card) throws {
        card.pinned.toggle()
        try context.save()
    }

    func recent(limit: Int? = nil) throws -> [Card] {
        let sorted = try context.fetch(FetchDescriptor<Card>())
            .sorted { $0.createdAt > $1.createdAt }
        return limit.map { Array(sorted.prefix($0)) } ?? sorted
    }

    func card(id: UUID) throws -> Card? {
        try context.fetch(FetchDescriptor<Card>()).first { $0.id == id }
    }

    /// Filtering in memory avoids SwiftData predicate limitations for optional text and remains fast for v1.
    func search(_ query: String) throws -> [Card] {
        let needle = query.searchNormalized
        guard !needle.isEmpty else { return try recent() }
        return try recent().filter { card in
            [card.title, card.rawText, card.enhancedText ?? "", card.processedText ?? ""]
                .contains { $0.searchNormalized.localizedStandardContains(needle) }
        }
    }
}
