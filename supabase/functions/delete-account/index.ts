const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ message: "Method not allowed." }, 405);
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return jsonResponse({ message: "A signed-in session is required." }, 401);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const anonymousKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !anonymousKey || !serviceRoleKey) {
    console.error("Required Supabase environment variables are unavailable.");
    return jsonResponse({ message: "Account deletion is temporarily unavailable." }, 503);
  }

  // Resolve the caller from their JWT. Never accept a user ID from the client.
  const userResponse = await fetch(`${supabaseURL}/auth/v1/user`, {
    headers: {
      apikey: anonymousKey,
      Authorization: authorization,
    },
  });
  if (!userResponse.ok) {
    return jsonResponse({ message: "Your session expired. Sign in again and retry." }, 401);
  }

  const user = await userResponse.json() as { id?: string };
  if (!user.id) {
    return jsonResponse({ message: "Yap could not identify this account." }, 401);
  }

  // Provider secrets and the service role remain server-only.
  const deletionResponse = await fetch(
    `${supabaseURL}/auth/v1/admin/users/${encodeURIComponent(user.id)}`,
    {
      method: "DELETE",
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
      },
    },
  );
  if (!deletionResponse.ok) {
    const providerMessage = await deletionResponse.text();
    console.error(`Supabase user deletion failed: ${providerMessage}`);
    return jsonResponse({ message: "Yap could not delete the account. Please try again." }, 502);
  }

  // Apple token revocation can be added here once Yap retains an Apple authorization
  // code and exchanges it for a refresh token during native Sign in with Apple.
  return jsonResponse({ deleted: true });
});
