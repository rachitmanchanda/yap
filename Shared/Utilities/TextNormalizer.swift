import Foundation

extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }

    var searchNormalized: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func firstWordsTitle(maxWords: Int = 6) -> String {
        let firstLine = split(whereSeparator: \.isNewline).first.map(String.init) ?? self
        let words = firstLine.split(whereSeparator: \.isWhitespace).prefix(maxWords)
        let result = words.joined(separator: " ")
        return result.isEmpty ? "Untitled thought" : result
    }
}
