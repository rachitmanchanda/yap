import Foundation
import UniformTypeIdentifiers

enum SharedPayload: Sendable, Equatable {
    case text(String)
    case url(URL)
    case imageDescription(String)

    var rawText: String {
        switch self {
        case .text(let text): text
        case .url(let url): url.absoluteString
        case .imageDescription(let description): description
        }
    }
}

enum SharedItemExtractorError: LocalizedError {
    case noSupportedContent

    var errorDescription: String? { "No supported text, URL, or image was found." }
}

@MainActor
struct SharedItemExtractor {
    func extract(from items: [NSExtensionItem]) async throws -> SharedPayload {
        let providers = items.flatMap { $0.attachments ?? [] }
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let item = try? await provider.loadItem(
                   forTypeIdentifier: UTType.url.identifier,
                   options: nil
               ),
               let url = item as? URL {
                return .url(url)
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let item = try? await provider.loadItem(
                   forTypeIdentifier: UTType.plainText.identifier,
                   options: nil
               ) {
                if let text = item as? String, text.nilIfBlank != nil { return .text(text) }
                if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                    return .text(text)
                }
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                // v1 intentionally does not OCR or retain image blobs; it records a searchable provenance card.
                return .imageDescription("Shared image")
            }
        }
        throw SharedItemExtractorError.noSupportedContent
    }
}
