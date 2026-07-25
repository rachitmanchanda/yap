import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

struct StoredClipboardImage: Sendable {
    let imageFileName: String
    let thumbnailFileName: String
    let originalUTType: String
    let byteCount: Int
}

struct ClipboardAssetStore: Sendable {
    private let directoryURL: URL?
    private let maximumOriginalBytes = 25 * 1_024 * 1_024

    init(directoryURL: URL? = AppGroup.containerURL?.appending(path: "ClipboardAssets", directoryHint: .isDirectory)) {
        self.directoryURL = directoryURL
    }

    func storeImage(data originalData: Data, type: UTType) throws -> StoredClipboardImage {
        guard let directoryURL else { throw ClipboardAssetError.containerUnavailable }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let stored: (data: Data, type: UTType)
        if originalData.count <= maximumOriginalBytes {
            stored = (originalData, type)
        } else {
            guard let image = downsample(data: originalData, maximumPixelSize: 2_048),
                  let jpeg = image.jpegData(compressionQuality: 0.85) else {
                throw ClipboardAssetError.invalidImage
            }
            stored = (jpeg, .jpeg)
        }

        guard let thumbnail = downsample(data: stored.data, maximumPixelSize: 320),
              let thumbnailData = thumbnail.jpegData(compressionQuality: 0.78) else {
            throw ClipboardAssetError.invalidImage
        }

        let stem = UUID().uuidString
        let imageFileName = "\(stem).\(stored.type.preferredFilenameExtension ?? "img")"
        let thumbnailFileName = "\(stem)-thumb.jpg"
        try stored.data.write(to: directoryURL.appending(path: imageFileName), options: .atomic)
        do {
            try thumbnailData.write(to: directoryURL.appending(path: thumbnailFileName), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: directoryURL.appending(path: imageFileName))
            throw error
        }
        return StoredClipboardImage(
            imageFileName: imageFileName,
            thumbnailFileName: thumbnailFileName,
            originalUTType: stored.type.identifier,
            byteCount: stored.data.count
        )
    }

    func imageData(fileName: String?) -> Data? {
        guard let directoryURL, let fileName else { return nil }
        return try? Data(contentsOf: directoryURL.appending(path: fileName))
    }

    func thumbnail(fileName: String?) -> UIImage? {
        imageData(fileName: fileName).flatMap(UIImage.init(data:))
    }

    func removeAssets(for item: ClipboardItem) {
        guard let directoryURL else { return }
        for fileName in [item.imageFileName, item.thumbnailFileName].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: directoryURL.appending(path: fileName))
        }
    }

    private func downsample(data: Data, maximumPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ] as CFDictionary
              ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

enum ClipboardAssetError: LocalizedError {
    case containerUnavailable
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .containerUnavailable: "The shared clipboard folder is unavailable."
        case .invalidImage: "This clipboard image could not be decoded."
        }
    }
}
