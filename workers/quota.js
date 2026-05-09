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

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Max-Age": "86400",
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    if (url.pathname === "/quota" && request.method === "GET") {
      return handleQuota(env);
    }

    return jsonResponse({ error: "not_found", path: url.pathname }, 404);
  },
};

async function handleQuota(env) {
  const instanceId = env.VULTR_INSTANCE_ID || DEFAULT_INSTANCE_ID;
  const token = env.VULTR_API_KEY;

  if (!token) {
    return jsonResponse(
      { error: "VULTR_API_KEY not configured", fetchedAt: nowIso() },
      502
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
    return jsonResponse(
      { error: `vultr_fetch_failed: ${err.message}`, fetchedAt: nowIso() },
      502
    );
  }

  if (!upstream.ok) {
    const body = await upstream.text();
    return jsonResponse(
      {
        error: `vultr_http_${upstream.status}`,
        detail: body.slice(0, 500),
        fetchedAt: nowIso(),
      },
      502
    );
  }

  let payload;
  try {
    payload = await upstream.json();
  } catch (err) {
    return jsonResponse(
      { error: `vultr_json_parse_failed: ${err.message}`, fetchedAt: nowIso() },
      502
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
  });
}

function jsonResponse(body, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...CORS_HEADERS,
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
