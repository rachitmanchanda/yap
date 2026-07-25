import Foundation
import Observation
import SwiftData
import UIKit

@MainActor
@Observable
final class ClipboardModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case text = "Text"
        case links = "Links"
        case images = "Images"

        var id: Self { self }
    }

    private(set) var items: [ClipboardItem] = []
    var query = ""
    var filter: Filter = .all
    var errorMessage: String?
    var automaticCapture = AppPreferences.automaticClipboardCapture
    private let repository: ClipboardRepository
    private let assets = ClipboardAssetStore()

    init(context: ModelContext) {
        repository = ClipboardRepository(context: context)
        reload()
    }

    var visibleItems: [ClipboardItem] {
        items.filter { item in
            let matchesFilter = switch filter {
            case .all: true
            case .text: item.kind == .text
            case .links: item.kind == .url
            case .images: item.kind == .image
            }
            let matchesQuery = query.nilIfBlank == nil
                || item.displayText.searchNormalized.localizedStandardContains(query.searchNormalized)
            return matchesFilter && matchesQuery
        }
    }

    func reload() {
        do {
            items = try repository.recent()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePin(_ item: ClipboardItem) {
        do {
            try repository.togglePinned(item)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ item: ClipboardItem) {
        do {
            try repository.delete(item, assets: assets)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setAutomaticCapture(_ enabled: Bool) {
        automaticCapture = enabled
        AppPreferences.automaticClipboardCapture = enabled
    }

    func thumbnail(for item: ClipboardItem) -> UIImage? {
        assets.thumbnail(fileName: item.thumbnailFileName)
    }
}
