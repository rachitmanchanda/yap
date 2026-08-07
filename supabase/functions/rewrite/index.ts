const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
};

type Provider = "deepseek" | "claude";
type Operation = "rewrite" | "title" | "enhance";

interface RewriteBody {
  operation: Operation;
  text: string;
  mode?: { id: string; name: string; prompt: string };
  knownTerms?: string[];
  preferredProvider?: Provider;
}

interface ProviderResult {
  content: string;
  provider: Provider;
  latencyMs: number;
}

const scores: Record<Provider, number> = {
  deepseek: 900,
  claude: 1_100,
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  try {
    const body = await request.json() as RewriteBody;
    const text = body.text?.trim();
    if (!text) return json({ error: "Text is required." }, 400);
    if (text.length > 12_000) return json({ error: "Text is too long." }, 413);
    if (!["rewrite", "title", "enhance"].includes(body.operation)) {
      return json({ error: "Unknown operation." }, 400);
    }
    if (body.operation === "rewrite" && !body.mode?.prompt?.trim()) {
      return json({ error: "A rewrite mode is required." }, 400);
    }

    const system = systemPrompt(body);
    const result = await fastestAvailable(
      system,
      userPrompt(body),
      body.preferredProvider,
      body.operation === "enhance" ? 0.1 : 0.4,
    );
    const parsed = parseResult(body.operation, result.content, text);

    return json({
      ...parsed,
      provider: result.provider,
      latencyMs: result.latencyMs,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Rewrite failed.";
    return json({ error: message }, 502);
  }
});

function systemPrompt(body: RewriteBody): string {
  const terms = (body.knownTerms ?? [])
    .map((term) => term.trim())
    .filter(Boolean)
    .slice(0, 100)
    .join(", ");
  const languageRules = [
    "Preserve the speaker's language, vernacular, Hinglish, code-switching, emoji, names, and intent.",
    "If Hindi or another Indian language is written in Latin characters, keep it in Latin characters. Never convert it to Devanagari or another native script. Keep English as English.",
    "Treat Roman Hinglish as vernacular, not misspelled English. Correct a Hindi word only when its intended form is clear from context, and keep natural forms such as kya, nahi, mat, karna, wala, and hai in Roman script.",
    "Correct obvious speech-recognition mistakes, grammar, punctuation, duplicated fragments, and false starts without inventing facts.",
    "Use the complete sentence as context to repair phonetic spellings into the intended word. Never leave stray apostrophes, split syllables, or phonetic fragments inside ordinary words.",
    terms ? `Use these exact preferred spellings when contextually relevant: ${terms}.` : "",
  ].filter(Boolean).join(" ");

  switch (body.operation) {
    case "rewrite":
      return [
        body.mode!.prompt.trim(),
        languageRules,
        "Return JSON only: {\"text\":\"final rewritten message\",\"title\":\"factual 4–6 word title\"}.",
      ].join("\n\n");
    case "title":
      return "Create a factual 4–6 word title. Return JSON only: {\"title\":\"title\"}.";
    case "enhance":
      return enhancementPrompt(terms);
  }
}

function enhancementPrompt(terms: string): string {
  return [
    "You clean up voice-dictated transcripts for a messaging keyboard. Return the message the speaker meant to type—not a better, more polished, or more expressive version of it.",
    "RULE PRIORITY. When rules conflict, the lower-numbered rule wins: 1. Never invent or alter meaning. 2. Preserve the speaker's language and code-switching. 3. Preserve the speaker's voice, register, and typing style. 4. Repair clear transcription errors. 5. Format only when the intended structure is clear. Correction and formatting never justify adding content or changing meaning.",
    "GROUNDING. Every meaning-bearing detail must be grounded in the transcript. Never invent facts, names, numbers, dates, places, brands, links, email addresses, actions, promises, list items, greetings, sign-offs, explanations, or missing clauses. Preserve names, quantities, amounts, dates, times, durations, links, email addresses, emoji, and factual claims. Repair one only for an obvious transcription artifact or when a learned term is a high-confidence phonetic match supported by the complete sentence. Never change a factual value merely to make the sentence more plausible. If a word may be a name and the correction is uncertain, preserve it.",
    "NEGATION AND MODALITY. Never add, remove, or change the meaning of not, n't, no, never, nahi, nahin, mat, na, or bilkul nahi. Grammar repair may reposition a negation only when its meaning and scope remain identical. Preserve maybe, probably, I think, might, should, shayad, lagta hai, ho sakta hai, and equivalent hedges.",
    "LANGUAGE AND SCRIPT. Preserve the language used. Never translate Hindi into English, English into Hindi, or Hinglish into one language. Output Latin script only. Romanize native-script Hindi into natural conversational Roman Hindi; in mixed input, romanize only native-script spans and preserve English as English. English loanwords written phonetically or in native script return to normal English spelling, such as doctor, cancel, plan, sorry, last minute, office, and meeting. Never return phonetically mangled English when the intended word is clear.",
    "ROMAN HINGLISH. Treat Roman Hinglish as vernacular, not misspelled English. Preserve natural code-switching and valid forms such as kya, nahi, mat, karna, wala, hai, toh, yaar, bas, mujhe, and haan. Never replace an intelligible Roman-Hindi word with an English synonym: for example, preserve grantiyan rather than changing it to gland. Preserve already-valid conversational variants such as mai/mein, me/main when context makes the intended Hindi word clear, bohot/bahut, acha/accha, and gai/gayi; normalization is not cleanup. Correct a Hindi word only when clear from the complete utterance. For uncertain ASR repair prefer conversational forms such as hai, hain, hoon, nahi, kya, kyun, kaise, kahan, main, mujhe, tum, aap, woh, aur, toh, bhi, abhi, kal, aaj, haan, accha, theek, bahut, thoda, karna, jaana, aana, hoga, yaar, matlab, wala, liye, paas, baat, kaam, ghar, and log. These are repair defaults, not mandatory rewrites: preserve other valid forms unless clearly wrong or overridden by a learned spelling. Use no academic transliteration marks.",
    "VOICE AND REGISTER. Preserve tone, formality, slang, vernacular, uncertainty, and emotional intensity. Never make the message more formal, polite, warm, funny, enthusiastic, apologetic, persuasive, or sanitized. Never summarize, elaborate, soften, censor, or improve the speaker's ideas. Short fragments are valid. Preserve a consistently lowercase message, including lowercase i; capitalize only unambiguous proper nouns and established brand casing such as WhatsApp, YouTube, or iPhone.",
    "PUNCTUATION. Never add an exclamation mark or emoji. Never add terminal punctuation when the transcript ends without it. Preserve existing terminal punctuation. Add commas, apostrophes, hyphens, colons, and internal sentence boundaries only when they materially improve readability. In a multi-sentence message, periods may separate complete thoughts while the final sentence remains without terminal punctuation. Do not add decorative punctuation.",
    "REPAIR. Use the complete utterance, not isolated tokens, to repair clear phonetic spellings, stray apostrophes, split syllables, merged words, broken agreement, malformed structure, ASR fragments, accidental repetitions, and false starts. Examples: sarti'fied to certified; kolda kophi to cold coffee; 1 toh to ek toh; aadat lag gai to aadat lag gayi; mam'mi to mummy. Never leave malformed phonetic fragments inside ordinary words. Apply the smallest correction required. If fluency would require dropping a clause, fact, name, number, hedge, or negation, leave it less fluent.",
    "FILLER. Remove um, umm, uh, aah, ah, erm, equivalent hesitation sounds, abandoned false starts, verbal stumbles, repeated lead-ins, and accidental duplicates. Remove you know, like, I mean, or matlab only when non-semantic; keep them when intentional, idiomatic, emphatic, or part of the speaker's voice.",
    "FORMAT AS PLAIN TEXT. Allowed structure is prose, paragraph breaks, and hyphen-space bullets. Never add rich-text emphasis, headings, labels, tables, numbering, or invented section titles.",
    "PARAGRAPHS. Break only when the speaker clearly moves to a distinct topic, argument, question, instruction, example, or conclusion. Keep related sentences together. A pause, slow speech, restart, breath, silence, recording-chunk boundary, or long ASR segment is not a paragraph break. When uncertain, use continuous prose.",
    "LISTS. Use hyphen-space bullets only when the speaker clearly intends an enumeration. English signals include first/second/finally, one/two/three, the following, a few things, my list is, and next point. Hinglish signals include do cheezein, teen cheezein, pehla/pehli, doosra/doosri, teesra/teesri, agla point, and last mein. Several clearly parallel tasks, steps, requirements, ingredients, recommendations, or items may also establish list intent. A list needs at least two genuine items. Keep introductory and concluding prose outside it. Never bullet incidental examples, alternatives in one sentence, repeated phrases, loosely related thoughts, or speech separated only by pauses. Phir, uske baad, ek toh, and aur ek baat are not sufficient alone; use them as list signals only with clearly parallel items or steps. When uncertain, use prose.",
    "SPOKEN FORMAT CONTROLS. When clearly used as commands, apply and remove new paragraph, next paragraph, bullet point, next point, number one/two, naya paragraph, agli line, agla point, pehla point, and doosra point. Preserve them when they are actual message content. Remove enumeration scaffolding only when clearly acting as formatting control. Preserve appropriate structure already present.",
    terms
      ? `LEARNED TERMS. User-specific names, places, brands, phrases, and preferred spellings: ${terms}. Apply one only when the transcript is a strong phonetic match and the complete sentence supports it. Never insert a merely similar term. A supported learned term overrides repair defaults.`
      : "LEARNED TERMS. None provided; do not infer any.",
    "OUTPUT. Return JSON only, with no fences, commentary, prefix, suffix, or explanation: {\"text\":\"<cleaned transcript>\",\"changed\":<true|false>}. Encode paragraph and list breaks as \\n. Preserve emoji. changed is true whenever text differs beyond surrounding whitespace; Romanization counts as changed. If no cleanup is needed, return the input exactly with changed false. For empty, silent, or unintelligible input, return it verbatim with changed false. Never place an apology, question, or error explanation in text. The result should normally be no longer than the input and must never exceed twice its length.",
    "FINAL CHECK. Every detail is grounded; nothing meaningful is missing; every negation, hedge, name, number, date, and time keeps its meaning; language and code-switching remain; native script is natural Latin script; English loanwords use English spelling; uncertain words were not guessed; tone and casing remain; no emotional or terminal punctuation was invented; bullets reflect clear list intent rather than pauses or chunk boundaries; learned terms are context-supported; output is valid JSON only.",
  ].join("\n\n");
}

function userPrompt(body: RewriteBody): string {
  return `USER TEXT:\n${body.text.trim()}`;
}

async function fastestAvailable(
  system: string,
  user: string,
  preferred?: Provider,
  temperature = 0.4,
): Promise<ProviderResult> {
  const available = ([
    Deno.env.get("DEEPSEEK") ? "deepseek" : null,
    Deno.env.get("CLAUDE") ? "claude" : null,
  ].filter(Boolean) as Provider[]);
  if (available.length === 0) throw new Error("No rewrite provider is configured.");

  const order = available.sort((left, right) => {
    if (preferred === left) return -1;
    if (preferred === right) return 1;
    return scores[left] - scores[right];
  });
  let lastError: unknown;
  for (const provider of order) {
    const started = performance.now();
    try {
      const content = provider === "deepseek"
        ? await callDeepSeek(system, user, temperature)
        : await callClaude(system, user, temperature);
      const latencyMs = Math.round(performance.now() - started);
      scores[provider] = (scores[provider] * 0.75) + (latencyMs * 0.25);
      return { content, provider, latencyMs };
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError instanceof Error ? lastError : new Error("Every rewrite provider failed.");
}

async function callDeepSeek(system: string, user: string, temperature: number): Promise<string> {
  const response = await fetch("https://api.deepseek.com/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${Deno.env.get("DEEPSEEK")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "deepseek-v4-flash",
      thinking: { type: "disabled" },
      temperature,
      max_tokens: 1_000,
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
    }),
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload?.error?.message ?? `DeepSeek returned HTTP ${response.status}.`);
  }
  const content = payload?.choices?.[0]?.message?.content?.trim();
  if (!content) throw new Error("DeepSeek returned an empty response.");
  return content;
}

async function callClaude(system: string, user: string, temperature: number): Promise<string> {
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": Deno.env.get("CLAUDE") ?? "",
      "anthropic-version": "2023-06-01",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "claude-sonnet-4-6",
      max_tokens: 1_000,
      temperature,
      system,
      messages: [{ role: "user", content: user }],
    }),
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload?.error?.message ?? `Claude returned HTTP ${response.status}.`);
  }
  const content = payload?.content?.find((part: { type: string }) => part.type === "text")?.text?.trim();
  if (!content) throw new Error("Claude returned an empty response.");
  return content;
}

function parseResult(operation: Operation, raw: string, original: string) {
  const cleaned = raw.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
  let value: Record<string, unknown>;
  try {
    value = JSON.parse(cleaned);
  } catch {
    if (operation === "title") return { text: raw.trim(), title: raw.trim() };
    return {
      text: raw.trim(),
      title: operation === "rewrite" ? firstWords(raw) : undefined,
      changed: operation === "enhance" ? raw.trim() !== original.trim() : undefined,
    };
  }

  const text = typeof value.text === "string"
    ? value.text.trim()
    : (typeof value.title === "string" ? value.title.trim() : "");
  if (!text) throw new Error("The provider returned malformed text.");
  return {
    text,
    title: typeof value.title === "string" ? value.title.trim() : undefined,
    changed: operation === "enhance"
      ? (typeof value.changed === "boolean" ? value.changed : text !== original.trim())
      : undefined,
  };
}

function firstWords(text: string): string {
  return text.trim().split(/\s+/).slice(0, 6).join(" ");
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
