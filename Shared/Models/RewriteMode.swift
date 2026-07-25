import Foundation
import SwiftData

@Model
final class RewriteMode {
    @Attribute(.unique) var id: String
    var name: String
    var systemPrompt: String
    var isBuiltIn: Bool
    var emoji: String

    init(id: String, name: String, systemPrompt: String, isBuiltIn: Bool, emoji: String) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.isBuiltIn = isBuiltIn
        self.emoji = emoji
    }
}
