import CryptoKit
import Foundation
import SwiftData
import UIKit
import UniformTypeIdentifiers

enum ClipboardFingerprint {
    static func make(kind: ClipboardItemKind, data: Data) -> String {
        let digest = SHA256.hash(data: Data(kind.rawValue.utf8) + data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum ClipboardWriteMarker {
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    static func mark(hash: String, changeCount: Int) {
        defaults.set(hash, forKey: "internalClipboardHash")
        defaults.set(changeCount, forKey: "internalClipboardChangeCount")
    }

    static func matches(hash: String, changeCount: Int) -> Bool {
        defaults.string(forKey: "internalClipboardHash") == hash
            && defaults.integer(forKey: "internalClipboardChangeCount") == changeCount
    }
}

/// Captures only while an app-owned process is active; iOS does not permit background clipboard monitoring.
@MainActor
final class ClipboardCaptureService {
    private let repository: ClipboardRepository
    private let assets: ClipboardAssetStore
    private let pasteboard: UIPasteboard
    private var lastObservedChangeCount: Int
    private let assetLimit = 500 * 1_024 * 1_024

    init(
        context: ModelContext,
        assets: ClipboardAssetStore = ClipboardAssetStore(),
        pasteboard: UIPasteboard = .general
    ) {
        repository = ClipboardRepository(context: context)
        self.assets = assets
        self.pasteboard = pasteboard
        lastObservedChangeCount = -1
    }

    @discardableResult
    func captureIfChanged(force: Bool = false) throws -> Int {
        guard AppPreferences.automaticClipboardCapture else { return 0 }
        let changeCount = pasteboard.changeCount
        guard force || changeCount != lastObservedChangeCount else { return 0 }
        lastObservedChangeCount = changeCount

        var captured = 0
        for item in pasteboard.items {
            if let candidate = imageCandidate(from: item) {
                captured += try captureImage(candidate.data, type: candidate.type, changeCount: changeCount)
            } else if let value = urlString(from: item)?.nilIfBlank {
                captured += try captureText(value, kind: .url, changeCount: changeCount)
            } else if let value = plainText(from: item)?.nilIfBlank {
                captured += try captureText(value, kind: .text, changeCount: changeCount)
            }
        }
        try repository.enforceAssetLimit(bytes: assetLimit, assets: assets)
        return captured
    }

    private func captureText(
        _ text: String,
        kind: ClipboardItemKind,
        changeCount: Int
    ) throws -> Int {
        let hash = ClipboardFingerprint.make(kind: kind, data: Data(text.utf8))
        guard !ClipboardWriteMarker.matches(hash: hash, changeCount: changeCount) else { return 0 }
        if let existing = try repository.item(contentHash: hash) {
            try repository.touch(existing)
            return 1
        }
        try repository.insert(
            ClipboardItem(kind: kind, text: text, contentHash: hash, byteCount: text.utf8.count)
        )
        return 1
    }

    private func captureImage(_ data: Data, type: UTType, changeCount: Int) throws -> Int {
        let hash = ClipboardFingerprint.make(kind: .image, data: data)
        guard !ClipboardWriteMarker.matches(hash: hash, changeCount: changeCount) else { return 0 }
        if let existing = try repository.item(contentHash: hash) {
            try repository.touch(existing)
            return 1
        }
        let stored = try assets.storeImage(data: data, type: type)
        do {
            try repository.insert(
                ClipboardItem(
                    kind: .image,
                    contentHash: hash,
                    originalUTType: stored.originalUTType,
                    imageFileName: stored.imageFileName,
                    thumbnailFileName: stored.thumbnailFileName,
                    byteCount: stored.byteCount
                )
            )
        } catch {
            let orphan = ClipboardItem(
                kind: .image,
                contentHash: hash,
                imageFileName: stored.imageFileName,
                thumbnailFileName: stored.thumbnailFileName
            )
            assets.removeAssets(for: orphan)
            throw error
        }
        return 1
    }

    private func urlString(from item: [String: Any]) -> String? {
        for (identifier, value) in item {
            guard UTType(identifier)?.conforms(to: .url) == true else { continue }
            if let url = value as? URL { return url.absoluteString }
            if let string = value as? String { return string }
            if let data = value as? Data { return String(data: data, encoding: .utf8) }
        }
        return nil
    }

    private func plainText(from item: [String: Any]) -> String? {
        for (identifier, value) in item {
            guard UTType(identifier)?.conforms(to: .text) == true else { continue }
            if let string = value as? String { return string }
            if let data = value as? Data { return String(data: data, encoding: .utf8) }
        }
        return nil
    }

    private func imageCandidate(from item: [String: Any]) -> (data: Data, type: UTType)? {
        for (identifier, value) in item {
            guard let type = UTType(identifier), type.conforms(to: .image) else { continue }
            if let data = value as? Data { return (data, type) }
            if let image = value as? UIImage, let data = image.pngData() { return (data, .png) }
            if let url = value as? URL, let data = try? Data(contentsOf: url) { return (data, type) }
        }
        return nil
    }
}
