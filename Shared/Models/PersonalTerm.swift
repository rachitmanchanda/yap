import Foundation
import SwiftData

enum PersonalTermKind: String, Codable, Sendable {
    case name
    case phrase
}

@Model
final class PersonalTerm {
    @Attribute(.unique) var normalized: String
    var value: String
    var kind: PersonalTermKind
    var useCount: Int
    var lastUsedAt: Date

    init(value: String, kind: PersonalTermKind, useCount: Int = 1, lastUsedAt: Date = .now) {
        self.value = value
        normalized = value.searchNormalized
        self.kind = kind
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
    }
}
