import WebSocket from "npm:ws@8.18.0";

declare const EdgeRuntime: {
  waitUntil(promise: Promise<unknown>): void;
};

Deno.serve((request) => {
  if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
    return Response.json({ error: "WebSocket upgrade required." }, { status: 426 });
  }

  const sarvamKey = Deno.env.get("SARVAM");
  if (!sarvamKey) {
    return Response.json({ error: "Sarvam is not configured." }, { status: 503 });
  }

  const incomingURL = new URL(request.url);
  const languageCode = incomingURL.searchParams.get("language") || "unknown";
  const requestedMode = incomingURL.searchParams.get("mode") || "translit";
  const supportedModes = new Set(["translit", "codemix", "transcribe", "verbatim", "translate"]);
  const mode = supportedModes.has(requestedMode) ? requestedMode : "translit";
  const upstreamURL = new URL("wss://api.sarvam.ai/speech-to-text/ws");
  upstreamURL.searchParams.set("language-code", languageCode);
  upstreamURL.searchParams.set("model", "saaras:v3");
  upstreamURL.searchParams.set("mode", mode);
  upstreamURL.searchParams.set("sample_rate", "16000");
  upstreamURL.searchParams.set("input_audio_codec", "pcm_s16le");
  upstreamURL.searchParams.set("high_vad_sensitivity", "true");
  upstreamURL.searchParams.set("vad_signals", "true");
  upstreamURL.searchParams.set("flush_signal", "true");

  const { socket, response } = Deno.upgradeWebSocket(request, { idleTimeout: 0 });
  const upstream = new WebSocket(upstreamURL, {
    headers: { "Api-Subscription-Key": sarvamKey },
  });
  const pending: Array<string | ArrayBuffer> = [];

  const closed = new Promise<void>((resolve) => {
    socket.onopen = () => {
      socket.send(JSON.stringify({ type: "relay_ready" }));
    };

    socket.onmessage = (event) => {
      const data = typeof event.data === "string" ? event.data : event.data as ArrayBuffer;
      if (upstream.readyState === WebSocket.OPEN) {
        upstream.send(data);
      } else if (pending.length < 100) {
        pending.push(data);
      }
    };

    socket.onerror = () => {
      if (upstream.readyState === WebSocket.OPEN) upstream.close(1011, "Client error");
    };

    socket.onclose = () => {
      if (upstream.readyState === WebSocket.OPEN) upstream.close(1000, "Client closed");
      resolve();
    };

    upstream.on("open", () => {
      for (const message of pending.splice(0)) upstream.send(message);
      if (socket.readyState === WebSocket.OPEN) {
        socket.send(JSON.stringify({ type: "provider_ready" }));
      }
    });

    upstream.on("message", (data) => {
      if (socket.readyState === WebSocket.OPEN) socket.send(data.toString());
    });

    upstream.on("error", (error) => {
      if (socket.readyState === WebSocket.OPEN) {
        socket.send(JSON.stringify({ type: "error", message: error.message }));
        socket.close(1011, "Provider connection failed");
      }
    });

    upstream.on("close", (code, reason) => {
      if (socket.readyState === WebSocket.OPEN) {
        socket.close(code === 1000 ? 1000 : 1011, reason.toString().slice(0, 120));
      }
      resolve();
    });
  });

  // An upgraded request otherwise looks idle to the Edge supervisor and may be retired early.
  EdgeRuntime.waitUntil(closed);
  return response;
});
