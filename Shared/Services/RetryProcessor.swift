import Foundation
import SwiftData

@MainActor
final class RetryProcessor {
    private let context: ModelContext
    private let transcription: any TranscriptionService
    private let rewrite: any RewriteService
    private let cards: CardRepository
    private let modes: ModeRepository
    private let lexicon: PersonalLexiconRepository

    init(context: ModelContext) {
        self.context = context
        transcription = FallbackTranscriptionService(
            online: SupabaseTranscriptionService(),
            offline: OnDeviceSpeechService()
        )
        rewrite = SupabaseRewriteService()
        cards = CardRepository(context: context)
        modes = ModeRepository(context: context)
        lexicon = PersonalLexiconRepository(context: context)
    }

    func processPending() async {
        let operations = (try? context.fetch(FetchDescriptor<PendingOperation>())) ?? []
        for operation in operations {
            do {
                switch operation.kind {
                case .transcription:
                    try await processTranscription(operation)
                case .rewrite:
                    try await processRewrite(operation)
                }
                context.delete(operation)
                try context.save()
            } catch {
                operation.attemptCount += 1
                operation.lastError = error.localizedDescription
                try? context.save()
            }
        }
    }

    private func processTranscription(_ operation: PendingOperation) async throws {
        guard let filename = operation.audioFilename else { return }
        let url = try AppGroup.audioDirectory().appending(path: filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let hints = (try? lexicon.hints()) ?? []
        let result = try await transcription.transcribe(
            audioURL: url,
            language: .automatic,
            outputStyle: .romanHinglish,
            vocabularyHints: hints
        )
        let enhancement = try? await rewrite.enhance(transcript: result.text, knownTerms: hints)
        let accepted = enhancement?.changed == true ? enhancement?.text : nil
        let title = (try? await rewrite.title(for: accepted ?? result.text))
            ?? (accepted ?? result.text).firstWordsTitle()
        let card = Card(
            sourceType: .voice,
            rawText: result.text,
            enhancedText: accepted,
            title: title
        )
        try cards.insert(card)
        try? lexicon.learn(from: card.preferredText)
        try? FileManager.default.removeItem(at: url)
    }

    private func processRewrite(_ operation: PendingOperation) async throws {
        guard let cardID = operation.cardID,
              let modeID = operation.modeID,
              let card = try cards.card(id: cardID),
              let mode = try modes.mode(id: modeID) else { return }
        let result = try await rewrite.rewrite(
            text: card.enhancedText ?? card.rawText,
            mode: ModeDefinition(id: mode.id, name: mode.name, emoji: mode.emoji, prompt: mode.systemPrompt)
        )
        card.processedText = result.rewrittenText
        card.modeApplied = mode.id
        card.title = result.title
        try context.save()
    }
}
