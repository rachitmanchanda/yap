import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SearchModel {
    var query = "" {
        didSet { scheduleSearch() }
    }
    private(set) var results: [Card] = []
    private(set) var isSearching = false
    var errorMessage: String?

    private let repository: CardRepository
    private var searchTask: Task<Void, Never>?

    init(context: ModelContext) {
        repository = CardRepository(context: context)
    }

    func searchNow() {
        do {
            results = try repository.search(query)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            searchNow()
            isSearching = false
        }
    }
}
