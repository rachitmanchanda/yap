import Foundation

enum RomanScriptNormalizer {
    static func normalize(_ text: String, for style: TranscriptionOutputStyle) -> String {
        guard style == .romanHinglish,
              text.unicodeScalars.contains(where: { !$0.isASCII && $0.properties.isAlphabetic }) else {
            return text
        }
        return text
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripCombiningMarks, reverse: false)
            ?? text
    }
}
