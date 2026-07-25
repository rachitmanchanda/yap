import Foundation
import SwiftData

enum ClipboardItemKind: String, Codable, CaseIterable, Sendable {
    case text
    case url
    case image

    var title: String {
        switch self {
        case .text: "Text"
        case .url: "Links"
        case .image: "Images"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .url: "link"
        case .image: "photo"
        }
    }
}

@Model
final class ClipboardItem {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var lastUsedAt: Date?
    private var kindValue: String
    var text: String?
    @Attribute(.unique) var contentHash: String
    var originalUTType: String?
    var imageFileName: String?
    var thumbnailFileName: String?
    var byteCount: Int
    var pinned: Bool
    var remoteID: String?
    var syncedAt: Date?

    var kind: ClipboardItemKind {
        get { ClipboardItemKind(rawValue: kindValue) ?? .text }
        set { kindValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        lastUsedAt: Date? = nil,
        kind: ClipboardItemKind,
        text: String? = nil,
        contentHash: String,
        originalUTType: String? = nil,
        imageFileName: String? = nil,
        thumbnailFileName: String? = nil,
        byteCount: Int = 0,
        pinned: Bool = false,
        remoteID: String? = nil,
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        kindValue = kind.rawValue
        self.text = text
        self.contentHash = contentHash
        self.originalUTType = originalUTType
        self.imageFileName = imageFileName
        self.thumbnailFileName = thumbnailFileName
        self.byteCount = byteCount
        self.pinned = pinned
        self.remoteID = remoteID
        self.syncedAt = syncedAt
    }

    var displayText: String {
        switch kind {
        case .text, .url: text ?? ""
        case .image: "Image"
        }
    }
}
