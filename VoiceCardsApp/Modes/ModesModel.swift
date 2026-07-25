import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ModesModel {
    private(set) var modes: [RewriteMode] = []
    var errorMessage: String?

    private let repository: ModeRepository

    init(context: ModelContext) {
        repository = ModeRepository(context: context)
        reload()
    }

    func reload() {
        do {
            try repository.seedBuiltInsIfNeeded()
            modes = try repository.all()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(id: String?, name: String, emoji: String, prompt: String) throws {
        try repository.saveCustom(id: id, name: name, emoji: emoji, prompt: prompt)
        reload()
    }

    func delete(_ mode: RewriteMode) {
        do {
            try repository.delete(mode)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
