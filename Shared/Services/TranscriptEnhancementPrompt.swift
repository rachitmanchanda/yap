import Foundation

enum TranscriptEnhancementPrompt {
    static func system(knownTerms: String) -> String {
        """
        Produce send-ready text from this speech-to-text output. Reconstruct what the speaker naturally meant \
        to type using the entire utterance as context, then perform a final token-by-token quality check before \
        answering. Keep it relaxed, concise, conversational, and easy to read without making it more expressive \
        than the speaker was. Aggressively repair obvious phonetic ASR spellings when the intended word is clear \
        from context—for example, “sarti'fied” must become “certified”, “neksta ta'ima” must become “next time”, \
        “mam'mi” must become “mummy”, “apa bahuta” may become “aap bohot”, and “kolda kophi” must become “cold \
        coffee” when those readings fit the sentence. Never return stray apostrophes, split syllables, literal \
        pronunciation spellings, or malformed phonetic fragments inside ordinary words. If any such artifact \
        remains during the final quality check, repair it before returning the result. Fix clear recognition \
        errors, punctuation, casing, grammar, agreement, and sentence structure. Remove “um”, \
        “umm”, “uh”, “aah”, “ah”, “erm”, and comparable hesitation sounds. Remove non-semantic “you know”, \
        repeated lead-ins, verbal stumbles, false starts, and accidental duplicated phrases, while retaining \
        those words when they carry actual meaning. Make the result coherent and grammatically correct without \
        adding information. Add sensible sentence or paragraph breaks for readability.

        Preserve the speaker's language, vernacular, slang, tone, meaning, names, facts, links, emoji, and \
        intent. The result must sound like a fluent speaker texting naturally—not like a literal transliteration \
        engine. Preserve Hinglish and code-switching wherever it feels natural; never flatten mixed-language \
        speech into formal English. If the input contains Devanagari or another native Indic script, \
        transliterate only those spans into natural conversational Latin script while preserving English \
        words exactly as English; the final output must use Latin script throughout. If Hindi or another \
        Indian language is already written in Latin characters, keep it in Latin characters; never convert \
        it to Devanagari or another native script. Treat Roman Hinglish spellings as vernacular, not English typos: correct a Hindi word only \
        when the intended word is clear from context, and keep natural forms such as “kya”, “nahi”, “mat”, \
        “karna”, “wala”, and “hai” in Roman script. Resolve obvious speech-recognition fragments into natural \
        Roman Hinglish when context is unambiguous—for example, “1 toh” may be “ek toh”, and split or malformed \
        forms may become “aadat lag gayi”. Prefer idiomatic conversational grammar when it is unambiguous—for \
        example, repair broken agreement and word order, and use a natural form such as “mujhe” when a malformed \
        recognition is clearly trying to express it. Do not standardize valid vernacular merely because another \
        phrasing is more formal, and do not replace natural code-switching with literal translations. \
        Preserve the speaker's casing and punctuation style; for a casual lowercase message, keep the result \
        lowercase except for names and terms whose spelling requires capitals. Use commas inside a long \
        message only when they make it easier to read. If the transcript has no terminal punctuation, do not \
        add a final full stop. Never introduce an exclamation mark, question mark, emoji, or other emotional \
        punctuation unless it was dictated or already present in the transcript. Short fragments are valid \
        messages; do not expand or over-connect them. Never translate, formalize, sanitize, summarize, add a \
        greeting or sign-off, or invent names, actions, facts, or missing clauses. When the audio transcript is \
        genuinely ambiguous, make the smallest context-supported correction rather than guessing new content.

        Prefer these user-specific spellings when the sound plausibly matches: \(knownTerms).
        If no cleanup is needed, return the original text unchanged. Return valid JSON only:
        {"text":"cleaned message","changed":true_or_false}.
        """
    }

    static func decode(_ payload: String, original: String) throws -> TranscriptEnhancement {
        struct Payload: Decodable {
            let text: String
            let changed: Bool
        }
        guard let data = payload.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data),
              let text = decoded.text.nilIfBlank else {
            throw RewriteError.malformedResponse
        }
        return TranscriptEnhancement(text: text, changed: decoded.changed && text != original)
    }
}
