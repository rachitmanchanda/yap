import Foundation
import SwiftData

@MainActor
struct HistoryRetentionService {
    let context: ModelContext

    /// Pinned cards are intentional long-term memory and are never removed by automatic retention.
    func apply(days: Int) throws {
        guard days > 0, let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) else {
            return
        }
        for card in try context.fetch(FetchDescriptor<Card>()) where !card.pinned && card.createdAt < cutoff {
            context.delete(card)
        }
        let assets = ClipboardAssetStore()
        for item in try context.fetch(FetchDescriptor<ClipboardItem>())
        where !item.pinned && item.createdAt < cutoff {
            assets.removeAssets(for: item)
            context.delete(item)
        }
        try context.save()
    }
}
