import SwiftData
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import VoiceCards

@MainActor
final class ClipboardHistoryTests: XCTestCase {
    func testCaptureClassifiesTextAndURLAndDeduplicates() throws {
        let container = try SharedModelContainer.make(inMemory: true)
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let pasteboardName = UIPasteboard.Name("VoiceCardsTests.\(UUID().uuidString)")
        let pasteboard = try XCTUnwrap(UIPasteboard(name: pasteboardName, create: true))
        defer {
            UIPasteboard.remove(withName: pasteboardName)
            try? FileManager.default.removeItem(at: directory)
        }
        let previousSetting = AppPreferences.automaticClipboardCapture
        AppPreferences.automaticClipboardCapture = true
        defer { AppPreferences.automaticClipboardCapture = previousSetting }

        let service = ClipboardCaptureService(
            context: container.mainContext,
            assets: ClipboardAssetStore(directoryURL: directory),
            pasteboard: pasteboard
        )
        pasteboard.string = "hello 👋"
        XCTAssertEqual(try service.captureIfChanged(), 1)

        pasteboard.url = URL(string: "https://example.com/path")
        XCTAssertEqual(try service.captureIfChanged(), 1)
        pasteboard.url = URL(string: "https://example.com/path")
        XCTAssertEqual(try service.captureIfChanged(), 1)

        let items = try ClipboardRepository(context: container.mainContext).recent()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.kind, .url)
        XCTAssertEqual(items.last?.kind, .text)
    }

    func testImageCaptureCreatesOriginalAndThumbnail() throws {
        let container = try SharedModelContainer.make(inMemory: true)
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let pasteboardName = UIPasteboard.Name("VoiceCardsTests.\(UUID().uuidString)")
        let pasteboard = try XCTUnwrap(UIPasteboard(name: pasteboardName, create: true))
        defer {
            UIPasteboard.remove(withName: pasteboardName)
            try? FileManager.default.removeItem(at: directory)
        }
        let previousSetting = AppPreferences.automaticClipboardCapture
        AppPreferences.automaticClipboardCapture = true
        defer { AppPreferences.automaticClipboardCapture = previousSetting }

        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 60)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        }
        pasteboard.setData(try XCTUnwrap(image.pngData()), forPasteboardType: UTType.png.identifier)
        let assets = ClipboardAssetStore(directoryURL: directory)
        let service = ClipboardCaptureService(
            context: container.mainContext,
            assets: assets,
            pasteboard: pasteboard
        )

        XCTAssertEqual(try service.captureIfChanged(), 1)
        let item = try XCTUnwrap(ClipboardRepository(context: container.mainContext).recent().first)
        XCTAssertEqual(item.kind, .image)
        XCTAssertNotNil(assets.imageData(fileName: item.imageFileName))
        XCTAssertNotNil(assets.thumbnail(fileName: item.thumbnailFileName))
    }

    func testRomanHinglishNormalizerPreservesNamesAndEmoji() {
        let result = RomanScriptNormalizer.normalize(
            "मुझे Rachit को message करना है 👋",
            for: .romanHinglish
        )

        XCTAssertFalse(result.unicodeScalars.contains { (0x0900...0x097F).contains(Int($0.value)) })
        XCTAssertTrue(result.contains("Rachit"))
        XCTAssertTrue(result.contains("message"))
        XCTAssertTrue(result.contains("👋"))
    }
}
