import Foundation
import SwiftData

@MainActor
final class ClipboardRepository {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func insert(_ item: ClipboardItem) throws {
        context.insert(item)
        try context.save()
    }

    func item(contentHash: String) throws -> ClipboardItem? {
        try context.fetch(FetchDescriptor<ClipboardItem>())
            .first { $0.contentHash == contentHash }
    }

    func touch(_ item: ClipboardItem, at date: Date = .now) throws {
        item.createdAt = date
        try context.save()
    }

    func recent(limit: Int? = nil) throws -> [ClipboardItem] {
        let items = try context.fetch(FetchDescriptor<ClipboardItem>())
            .sorted { $0.createdAt > $1.createdAt }
        return limit.map { Array(items.prefix($0)) } ?? items
    }

    func search(_ query: String) throws -> [ClipboardItem] {
        let needle = query.searchNormalized
        guard !needle.isEmpty else { return try recent() }
        return try recent().filter {
            $0.displayText.searchNormalized.localizedStandardContains(needle)
        }
    }

    func togglePinned(_ item: ClipboardItem) throws {
        item.pinned.toggle()
        try context.save()
    }

    func markUsed(_ item: ClipboardItem) throws {
        item.lastUsedAt = .now
        try context.save()
    }

    func delete(_ item: ClipboardItem, assets: ClipboardAssetStore) throws {
        assets.removeAssets(for: item)
        context.delete(item)
        try context.save()
    }

    func enforceAssetLimit(
        bytes limit: Int,
        assets: ClipboardAssetStore
    ) throws {
        var images = try context.fetch(FetchDescriptor<ClipboardItem>())
            .filter { $0.kind == .image && !$0.pinned }
            .sorted { $0.createdAt < $1.createdAt }
        var total = try context.fetch(FetchDescriptor<ClipboardItem>())
            .filter { $0.kind == .image }
            .reduce(0) { $0 + $1.byteCount }
        while total > limit, let oldest = images.first {
            images.removeFirst()
            total -= oldest.byteCount
            assets.removeAssets(for: oldest)
            context.delete(oldest)
        }
        try context.save()
    }
}
