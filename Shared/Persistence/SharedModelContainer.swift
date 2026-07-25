import Foundation
import SwiftData

enum SharedModelContainer {
    static let schema = Schema([
        Card.self,
        ClipboardItem.self,
        RewriteMode.self,
        PendingOperation.self,
        PersonalTerm.self
    ])

    /// A fixed App Group URL makes the same WAL-backed SwiftData store visible to each process.
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let storeURL = try AppGroup.requireContainerURL().appending(path: AppGroup.storeFilename)
            configuration = ModelConfiguration(
                "VoiceCardsShared",
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
