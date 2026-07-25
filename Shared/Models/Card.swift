import Foundation
import SwiftData

@Model
final class Card {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var sourceType: CardSourceType
    var rawText: String
    var enhancedText: String?
    var processedText: String?
    var modeApplied: String?
    var title: String
    var pinned: Bool
    var embedding: [Float]?

    /// These fields are present from day one so adding sync does not require reshaping core data.
    var remoteID: String?
    var syncedAt: Date?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        sourceType: CardSourceType,
        rawText: String,
        enhancedText: String? = nil,
        processedText: String? = nil,
        modeApplied: String? = nil,
        title: String,
        pinned: Bool = false,
        embedding: [Float]? = nil,
        remoteID: String? = nil,
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceType = sourceType
        self.rawText = rawText
        self.enhancedText = enhancedText
        self.processedText = processedText
        self.modeApplied = modeApplied
        self.title = title
        self.pinned = pinned
        self.embedding = embedding
        self.remoteID = remoteID
        self.syncedAt = syncedAt
    }

    var preferredText: String {
        processedText?.nilIfBlank ?? enhancedText?.nilIfBlank ?? rawText
    }
}
