import Foundation
import SwiftData

enum PendingOperationKind: String, Codable, Sendable {
    case transcription
    case rewrite
}

@Model
final class PendingOperation {
    @Attribute(.unique) var id: UUID
    var kind: PendingOperationKind
    var audioFilename: String?
    var cardID: UUID?
    var modeID: String?
    var createdAt: Date
    var attemptCount: Int
    var lastError: String?

    init(
        id: UUID = UUID(),
        kind: PendingOperationKind,
        audioFilename: String? = nil,
        cardID: UUID? = nil,
        modeID: String? = nil,
        createdAt: Date = .now,
        attemptCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.audioFilename = audioFilename
        self.cardID = cardID
        self.modeID = modeID
        self.createdAt = createdAt
        self.attemptCount = attemptCount
        self.lastError = lastError
    }
}
