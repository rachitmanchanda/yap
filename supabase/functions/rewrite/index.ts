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
    const result = await fastestAvailable(system, userPrompt(body), body.preferredProvider);
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
    "Correct obvious speech-recognition mistakes, grammar, and punctuation without inventing facts.",
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
      return [
        languageRules,
        "Be conservative: if no correction is clearly needed, preserve the text exactly.",
        "Return JSON only: {\"text\":\"corrected transcript\",\"changed\":true_or_false}.",
      ].join("\n\n");
  }
}

function userPrompt(body: RewriteBody): string {
  return `USER TEXT:\n${body.text.trim()}`;
}

async function fastestAvailable(
  system: string,
  user: string,
  preferred?: Provider,
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
        ? await callDeepSeek(system, user)
        : await callClaude(system, user);
      const latencyMs = Math.round(performance.now() - started);
      scores[provider] = (scores[provider] * 0.75) + (latencyMs * 0.25);
      return { content, provider, latencyMs };
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError instanceof Error ? lastError : new Error("Every rewrite provider failed.");
}

async function callDeepSeek(system: string, user: string): Promise<string> {
  const response = await fetch("https://api.deepseek.com/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${Deno.env.get("DEEPSEEK")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "deepseek-v4-flash",
      thinking: { type: "disabled" },
      temperature: 0.4,
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

async function callClaude(system: string, user: string): Promise<string> {
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
      temperature: 0.4,
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
