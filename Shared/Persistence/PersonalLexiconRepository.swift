import Foundation
import NaturalLanguage
import SwiftData

@MainActor
final class PersonalLexiconRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Names are useful after one acceptance; ordinary phrases become hints only after recurring.
    func hints(limit: Int = 40) throws -> [String] {
        let terms = try context.fetch(FetchDescriptor<PersonalTerm>())
            .sorted {
                $0.useCount == $1.useCount
                    ? $0.lastUsedAt > $1.lastUsedAt
                    : $0.useCount > $1.useCount
            }
        return terms
            .filter { $0.kind == .name || $0.useCount >= 3 }
            .prefix(limit)
            .map(\.value)
    }

    func learn(from acceptedText: String) throws {
        let candidates = namedEntities(in: acceptedText).map { ($0, PersonalTermKind.name) }
            + recurringPhraseCandidates(in: acceptedText).map { ($0, PersonalTermKind.phrase) }
        for (value, kind) in candidates {
            let normalized = value.searchNormalized
            if let existing = try context.fetch(FetchDescriptor<PersonalTerm>())
                .first(where: { $0.normalized == normalized }) {
                existing.value = value
                existing.kind = existing.kind == .name ? .name : kind
                existing.useCount += 1
                existing.lastUsedAt = .now
            } else {
                context.insert(PersonalTerm(value: value, kind: kind))
            }
        }
        try context.save()
    }

    private func namedEntities(in text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var names: [String] = []
        let range = text.startIndex..<text.endIndex
        tagger.enumerateTags(in: range, unit: .word, scheme: .nameType, options: [.joinNames]) {
            tag, tokenRange in
            if tag != nil {
                let value = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if value.count >= 2 { names.append(value) }
            }
            return true
        }
        return Array(Set(names))
    }

    private func recurringPhraseCandidates(in text: String) -> [String] {
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard words.count >= 2 else { return [] }
        return (0..<(words.count - 1)).compactMap { index in
            let pair = "\(words[index]) \(words[index + 1])"
            guard pair.count >= 7, pair.count <= 48 else { return nil }
            return pair
        }
    }
}
