import Foundation
import SwiftData

@MainActor
final class ModeRepository {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func seedBuiltInsIfNeeded() throws {
        let existing = try context.fetch(FetchDescriptor<RewriteMode>())
        let ids = Set(existing.map(\.id))
        for item in BuiltInModes.definitions where !ids.contains(item.id) {
            context.insert(RewriteMode(
                id: item.id,
                name: item.name,
                systemPrompt: item.prompt,
                isBuiltIn: true,
                emoji: item.emoji
            ))
        }
        try context.save()
    }

    func all() throws -> [RewriteMode] {
        try context.fetch(FetchDescriptor<RewriteMode>())
            .sorted { lhs, rhs in
                if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    func saveCustom(id: String? = nil, name: String, emoji: String, prompt: String) throws {
        if let id, let existing = try mode(id: id), !existing.isBuiltIn {
            existing.name = name
            existing.emoji = emoji
            existing.systemPrompt = prompt
        } else {
            context.insert(RewriteMode(
                id: "custom-\(UUID().uuidString.lowercased())",
                name: name,
                systemPrompt: prompt,
                isBuiltIn: false,
                emoji: emoji
            ))
        }
        try context.save()
    }

    func delete(_ mode: RewriteMode) throws {
        guard !mode.isBuiltIn else { return }
        context.delete(mode)
        try context.save()
    }

    func mode(id: String) throws -> RewriteMode? {
        try context.fetch(FetchDescriptor<RewriteMode>()).first { $0.id == id }
    }
}
