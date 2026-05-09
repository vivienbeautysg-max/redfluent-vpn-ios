// Cloudflare Worker — RedFluent VPN bandwidth quota proxy.
//
// Proxies the Vultr bandwidth API for a single instance, sums monthly usage,
// and returns a normalised JSON snapshot the iOS app can render directly.
//
// Required env:
//   VULTR_API_KEY      — secret, Vultr personal access token
//   VULTR_INSTANCE_ID  — plain text, Vultr instance UUID
//                        (defaults to RedFluent prod instance if unset)

const DEFAULT_INSTANCE_ID = "8ec935f7-32b4-4b0c-83da-b56ecbc082af";
const MONTHLY_QUOTA_BYTES = 2_199_023_255_552; // 2 TB (binary, 2 * 1024^4)
const BYTES_PER_GB = 1_073_741_824;            // 1 GiB
const CACHE_SECONDS = 120;                      // edge cache window

// Flip to true ONLY for ad-hoc debugging. When true, upstream Vultr error
// bodies are echoed back to clients, which can leak request IDs, partial
// token echoes, IPs, etc. MUST stay false in committed code.
const PUBLIC_DEBUG = false;

function corsHeaders(env) {
  // Default `*` keeps backward compat. For production deployments set
  // env.ALLOWED_ORIGIN to either a specific origin or the literal string
  // "null" — iOS NSURLSession does not send Origin so the value never
  // affects the app, but locking it down prevents browsers on third-party
  // sites from reading the response.
  const allowed = (env && env.ALLOWED_ORIGIN) || "*";
  return {
    "Access-Control-Allow-Origin": allowed,
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Max-Age": "86400",
  };
}

// Constant-time string compare to deny a timing oracle on the bearer
// token. JS's `===` short-circuits at the first byte difference; an
// attacker with a low-jitter network path could (in principle) recover
// the secret one byte at a time. safeEq always walks the full string.
function safeEq(a, b) {
  if (typeof a !== "string" || typeof b !== "string") return false;
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) {
    r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return r === 0;
}

function isAuthorized(request, env) {
  // If CLIENT_SECRET is unset we allow unauthenticated requests for
  // backward compat with already-deployed workers. Setting it locks the
  // endpoint behind a shared bearer token so attackers cannot DoS the
  // upstream Vultr API call.
  const expected = env && env.CLIENT_SECRET;
  if (!expected) return true;
  const header = request.headers.get("Authorization") || "";
  return safeEq(header, `Bearer ${expected}`);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const headers = corsHeaders(env);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers });
    }

    if (!isAuthorized(request, env)) {
      return jsonResponse({ error: "unauthorized", fetchedAt: nowIso() }, 401, {}, env);
    }

    if (url.pathname === "/quota" && request.method === "GET") {
      return handleQuota(env);
    }

    return jsonResponse({ error: "not_found", path: url.pathname }, 404, {}, env);
  },
};

async function handleQuota(env) {
  const instanceId = env.VULTR_INSTANCE_ID || DEFAULT_INSTANCE_ID;
  const token = env.VULTR_API_KEY;

  if (!token) {
    return jsonResponse(
      { error: "VULTR_API_KEY not configured", fetchedAt: nowIso() },
      502,
      {},
      env
    );
  }

  let upstream;
  try {
    upstream = await fetch(
      `https://api.vultr.com/v2/instances/${instanceId}/bandwidth`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: "application/json",
        },
        cf: { cacheTtl: CACHE_SECONDS, cacheEverything: false },
      }
    );
  } catch (err) {
    // Do NOT echo err.message — fetch errors can include hostnames or
    // network metadata. Status alone is enough for the client.
    return jsonResponse(
      { error: "upstream_unavailable", fetchedAt: nowIso() },
      502,
      {},
      env
    );
  }

  if (!upstream.ok) {
    // Drop the upstream body. It can contain Vultr request IDs, partial
    // token echoes, rate-limit info, or the caller IP — and CORS is
    // public, so anything we return is world-readable.
    const errorBody = {
      error: "upstream_unavailable",
      status: upstream.status,
      fetchedAt: nowIso(),
    };
    if (PUBLIC_DEBUG) {
      const body = await upstream.text();
      errorBody.detail = body.slice(0, 500);
    }
    return jsonResponse(errorBody, 502, {}, env);
  }

  let payload;
  try {
    payload = await upstream.json();
  } catch (_err) {
    return jsonResponse(
      { error: "upstream_parse_failed", fetchedAt: nowIso() },
      502,
      {},
      env
    );
  }

  const days = (payload && payload.bandwidth) || {};
  let incomingBytes = 0;
  let outgoingBytes = 0;
  for (const key of Object.keys(days)) {
    const entry = days[key] || {};
    incomingBytes += Number(entry.incoming_bytes) || 0;
    outgoingBytes += Number(entry.outgoing_bytes) || 0;
  }
  const usedBytes = incomingBytes + outgoingBytes;
  const remainingBytes = Math.max(0, MONTHLY_QUOTA_BYTES - usedBytes);

  const now = new Date();
  const periodStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  const periodEnd   = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 0));
  const nextMonth   = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
  const msPerDay    = 86_400_000;
  const daysUntilReset = Math.max(
    0,
    Math.ceil((nextMonth.getTime() - now.getTime()) / msPerDay)
  );

  const body = {
    monthlyQuotaGB: round2(MONTHLY_QUOTA_BYTES / BYTES_PER_GB),
    usedGB:         round2(usedBytes / BYTES_PER_GB),
    usedBytes:      usedBytes,
    remainingGB:    round2(remainingBytes / BYTES_PER_GB),
    percentUsed:    round4(usedBytes / MONTHLY_QUOTA_BYTES),
    daysUntilReset: daysUntilReset,
    billingPeriodStart: isoDate(periodStart),
    billingPeriodEnd:   isoDate(periodEnd),
    incomingBytes:  incomingBytes,
    outgoingBytes:  outgoingBytes,
    fetchedAt:      nowIso(),
  };

  return jsonResponse(body, 200, {
    "Cache-Control": `public, max-age=${CACHE_SECONDS}`,
  }, env);
}

function jsonResponse(body, status = 200, extraHeaders = {}, env = undefined) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...corsHeaders(env),
      ...extraHeaders,
    },
  });
}

function round2(n) { return Math.round(n * 100) / 100; }
function round4(n) { return Math.round(n * 10000) / 10000; }
function nowIso() { return new Date().toISOString().replace(/\.\d{3}Z$/, "Z"); }
function isoDate(d) {
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const day = String(d.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}
