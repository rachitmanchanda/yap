import Foundation

enum BuiltInModes {
    static let definitions: [ModeDefinition] = [
        .init(
            id: "formal",
            name: "Formal",
            emoji: "💼",
            prompt: """
            Rewrite the user's text for a professional email or workplace chat. Be concise, direct, \
            courteous, and specific. Preserve every material fact, request, name, date, link, and \
            commitment. Remove filler and repetition. Do not add a greeting, sign-off, subject line, \
            explanation, or invented context unless the source contains one. Return only the rewrite.
            """
        ),
        .init(
            id: "casual",
            name: "Casual",
            emoji: "💬",
            prompt: """
            Rewrite the user's text like a natural WhatsApp message: warm, relaxed, concise, and \
            conversational. Preserve Hinglish and code-switching exactly where it feels natural; never \
            flatten mixed-language speech into formal English. Keep names, facts, links, and intent. \
            Do not add commentary or quotation marks. Return only the rewrite.
            """
        ),
        .init(
            id: "roast",
            name: "Roast",
            emoji: "🔥",
            prompt: """
            Turn the user's meaning into a playful, exaggerated roast suitable for sharing with friends. \
            Make it witty rather than cruel. Preserve the underlying topic and important facts. Never \
            target protected traits, threaten, encourage harassment, or invent accusations. If the text \
            concerns a vulnerable person or serious harm, keep the humor gentle. Return only the rewrite.
            """
        ),
        .init(
            id: "rizz",
            name: "Rizz",
            emoji: "✨",
            prompt: """
            Rewrite the user's text to sound smooth, confident, lightly flirty, and emotionally aware. \
            Keep it natural and brief—never cheesy, manipulative, sexually explicit, possessive, or \
            pressuring. Preserve the user's actual meaning and facts. Return only the message, without \
            analysis, labels, or quotation marks.
            """
        ),
        .init(
            id: "hindi-household",
            name: "Hindi (household)",
            emoji: "🇮🇳",
            prompt: """
            Translate the user's English instructions into natural, polite spoken Hindi suitable for \
            texting household staff. Use respectful “aap” forms, clear everyday vocabulary, and a warm \
            tone—never textbook-stiff, condescending, or overly formal. Preserve names, quantities, times, \
            and practical details. Output Devanagari first. On a new line, optionally add a concise Roman \
            Hindi transliteration when it helps pronunciation. Return only the translation.
            """
        )
    ]
}

struct ModeDefinition: Sendable {
    let id: String
    let name: String
    let emoji: String
    let prompt: String
}
