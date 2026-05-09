# RedFluent Quota Worker

A tiny Cloudflare Worker that proxies the Vultr bandwidth API for one VPS
instance, sums monthly usage, and returns a JSON snapshot the iOS app can
render. Single file, no build step, no `wrangler` required — deployable from
the Cloudflare dashboard in about three minutes.

## Endpoints

| Method | Path     | Description                                                      |
|--------|----------|------------------------------------------------------------------|
| `GET`  | `/quota` | Current month's usage + days-until-reset. Cached 120 s at edge.  |
| `OPTIONS` | any   | CORS preflight.                                                   |
| any    | other    | 404 JSON.                                                         |

Sample response:

```json
{
  "monthlyQuotaGB": 2048,
  "usedGB": 1.36,
  "usedBytes": 1462077886,
  "remainingGB": 2046.64,
  "percentUsed": 0.0007,
  "daysUntilReset": 22,
  "billingPeriodStart": "2026-05-01",
  "billingPeriodEnd": "2026-05-31",
  "incomingBytes": 758997099,
  "outgoingBytes": 603080787,
  "fetchedAt": "2026-05-09T15:30:00Z"
}
```

## Deploy via dashboard (no CLI)

1. **Open Workers**
   <https://dash.cloudflare.com/?to=/:account/workers>
   Click **Create application → Create Worker**.

2. **Name it**
   `redfluent-quota` → **Deploy** (you'll get the default "Hello World"
   worker, which we'll overwrite next).

3. **Paste the code**
   Click **Edit code**, delete everything in `worker.js`, then paste the
   entire contents of [`quota.js`](./quota.js). Click **Save and deploy**.

4. **Add the secret + variable**
   Go to **Settings → Variables and Secrets** for this Worker.

   - **Add → Secret**
     - Type: **Secret**
     - Name: `VULTR_API_KEY`
     - Value: *paste your Vultr personal access token* (see below)
   - **Add → Variable**
     - Type: **Plaintext**
     - Name: `VULTR_INSTANCE_ID`
     - Value: `8ec935f7-32b4-4b0c-83da-b56ecbc082af`

   Click **Deploy** again so the new env is picked up.

5. **Note the URL**
   You'll see something like
   `https://redfluent-quota.YOURNAME.workers.dev`.
   Smoke-test it:

   ```bash
   curl https://redfluent-quota.YOURNAME.workers.dev/quota
   ```

   You should get the JSON shape shown above. If you get
   `{"error": "vultr_http_401", ...}` your API key is wrong; if you get
   `{"error": "vultr_http_404", ...}` the instance ID is wrong.

6. **Wire it into the iOS app**
   In `App/QuotaStore.swift`, replace `PLACEHOLDER` in the default endpoint
   URL with `YOURNAME` from step 5.

## Optional: custom route

If you want `https://vpn-api.redfluent.com/v1/quota` instead of the
`workers.dev` URL:

1. Cloudflare DNS → add `vpn-api` → CNAME → `redfluent.com` (proxied,
   orange cloud).
2. Workers → `redfluent-quota` → **Settings → Triggers → Add Custom
   Domain** → `vpn-api.redfluent.com`. Cloudflare will auto-issue a TLS
   cert.
3. Or, for a path-based route: **Add Route** →
   `vpn-api.redfluent.com/v1/quota*` → Worker `redfluent-quota`.
4. Update `App/QuotaStore.swift` with the new URL.

## Vultr API key

Create one here: <https://my.vultr.com/settings/#settingsapi>.

- Click **Enable API** if it's disabled.
- Add your egress IP to the **Access Control** allow-list. **Cloudflare
  Workers run from many IPs** — the cleanest fix is to leave the allow-list
  empty (any IP) since the token is the real auth, or add `0.0.0.0/0` if
  the UI demands a value. Treat the token like a password.
- Scope: a "personal access token" with read access is enough for the
  bandwidth endpoint.

## Limits & cost

- **Workers free tier:** 100,000 requests / day. The iOS app polls at
  most once every couple of minutes per active session, so a single user
  will use < 1,000 / day. Plenty of headroom.
- **Edge cache:** responses carry `Cache-Control: public, max-age=120`,
  and the upstream `fetch()` uses Cloudflare's `cf.cacheTtl: 120`.
  Effective rate to Vultr is ≤ 1 req / 2 min globally — well under
  Vultr's per-key rate limit.
- **CPU:** trivial (a few hundred microseconds). Free tier is fine.

## Security notes

- `VULTR_API_KEY` is stored as a Worker **secret** (encrypted at rest,
  never visible after creation). Never commit it.
- The Worker only exposes aggregate bandwidth numbers — no instance
  metadata, no IPs, no admin actions. CORS is `*` so the dashboard can
  hit it from any origin; if you want to lock it down, restrict to the
  iOS app's origin (or use a shared bearer token).
- If the token leaks, rotate it from the Vultr dashboard and redeploy
  the secret. No app rebuild needed.
