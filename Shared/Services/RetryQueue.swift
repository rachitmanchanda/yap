import Foundation
import SwiftData

@MainActor
final class RetryQueue {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func enqueueTranscription(audioURL: URL, error: Error) throws {
        context.insert(PendingOperation(
            kind: .transcription,
            audioFilename: audioURL.lastPathComponent,
            lastError: error.localizedDescription
        ))
        try context.save()
    }

    func enqueueRewrite(cardID: UUID, modeID: String, error: Error) throws {
        context.insert(PendingOperation(
            kind: .rewrite,
            cardID: cardID,
            modeID: modeID,
            lastError: error.localizedDescription
        ))
        try context.save()
    }

    func pending() throws -> [PendingOperation] {
        try context.fetch(FetchDescriptor<PendingOperation>())
            .sorted { $0.createdAt < $1.createdAt }
    }
}
