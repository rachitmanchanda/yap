const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })
  if (request.method !== "POST") return json({ error: "Method not allowed." }, 405)

  try {
    const incoming = await request.formData()
    const audio = incoming.get("file")
    if (!(audio instanceof File) || audio.size === 0) {
      return json({ error: "A non-empty audio file is required." }, 400)
    }

    const languageCode = String(incoming.get("language_code") ?? "unknown")
    const requestedProvider = String(incoming.get("provider") ?? "sarvam")
    if (requestedProvider !== "sarvam" && requestedProvider !== "whisper") {
      return json({ error: "provider must be sarvam or whisper." }, 400)
    }
    const requestedMode = String(incoming.get("mode") ?? "translit")
    const supportedModes = new Set(["translit", "codemix", "transcribe", "verbatim", "translate"])
    const mode = supportedModes.has(requestedMode) ? requestedMode : "translit"
    const vocabulary = String(incoming.get("vocabulary") ?? "").trim()
    const providerBody = new FormData()
    providerBody.append("file", audio, audio.name || "speech.m4a")

    let providerResponse: Response
    if (requestedProvider === "sarvam") {
      const sarvamKey = Deno.env.get("SARVAM")
      if (!sarvamKey) return json({ error: "SARVAM secret is not configured." }, 503)
      providerBody.append("model", "saaras:v3")
      providerBody.append("mode", mode)
      providerBody.append("language_code", languageCode)
      providerResponse = await fetch("https://api.sarvam.ai/speech-to-text", {
        method: "POST",
        headers: { "api-subscription-key": sarvamKey },
        body: providerBody,
      })
    } else {
      const openAIKey = Deno.env.get("OPENAI") ?? Deno.env.get("OPENAI_API_KEY")
      if (!openAIKey) return json({ error: "OPENAI secret is not configured." }, 503)
      providerBody.append("model", "whisper-1")
      providerBody.append("response_format", "json")
      if (languageCode !== "unknown") providerBody.append("language", languageCode)
      if (vocabulary) providerBody.append("prompt", `Names and phrases: ${vocabulary}`)
      providerResponse = await fetch("https://api.openai.com/v1/audio/transcriptions", {
        method: "POST",
        headers: { "Authorization": `Bearer ${openAIKey}` },
        body: providerBody,
      })
    }
    const payload = await providerResponse.json()
    if (!providerResponse.ok) {
      const message = payload?.error?.message ??
        payload?.message ??
        `${requestedProvider} transcription failed.`
      return json({ error: message }, providerResponse.status)
    }

    const providerTranscript = requestedProvider === "sarvam" ? payload?.transcript : payload?.text
    const transcript = typeof providerTranscript === "string"
      ? providerTranscript.trim()
      : ""
    if (!transcript) return json({ error: "No speech was detected." }, 422)

    return json({
      transcript,
      languageCode: payload.language_code ?? null,
      provider: requestedProvider,
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unexpected transcription error."
    return json({ error: message }, 500)
  }
})
