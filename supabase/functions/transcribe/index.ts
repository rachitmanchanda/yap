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

  const sarvamKey = Deno.env.get("SARVAM")
  if (!sarvamKey) return json({ error: "SARVAM secret is not configured." }, 500)

  try {
    const incoming = await request.formData()
    const audio = incoming.get("file")
    if (!(audio instanceof File) || audio.size === 0) {
      return json({ error: "A non-empty audio file is required." }, 400)
    }

    const languageCode = String(incoming.get("language_code") ?? "unknown")
    const requestedMode = String(incoming.get("mode") ?? "translit")
    const supportedModes = new Set(["translit", "codemix", "transcribe", "verbatim", "translate"])
    const mode = supportedModes.has(requestedMode) ? requestedMode : "translit"
    const providerBody = new FormData()
    providerBody.append("file", audio, audio.name || "speech.m4a")
    providerBody.append("model", "saaras:v3")
    providerBody.append("mode", mode)
    providerBody.append("language_code", languageCode)

    const providerResponse = await fetch("https://api.sarvam.ai/speech-to-text", {
      method: "POST",
      headers: { "api-subscription-key": sarvamKey },
      body: providerBody,
    })
    const payload = await providerResponse.json()
    if (!providerResponse.ok) {
      const message = payload?.error?.message ?? payload?.message ?? "Sarvam transcription failed."
      return json({ error: message }, providerResponse.status)
    }

    const transcript = typeof payload?.transcript === "string"
      ? payload.transcript.trim()
      : ""
    if (!transcript) return json({ error: "No speech was detected." }, 422)

    return json({
      transcript,
      languageCode: payload.language_code ?? null,
      provider: "sarvam",
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unexpected transcription error."
    return json({ error: message }, 500)
  }
})
