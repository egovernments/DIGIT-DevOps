# OAuth sign-in for Code Build (the broker Worker)

The `/actions` dispatcher can sign users in with their **own GitHub account** instead of
a pasted token, when Setup is run with `auth_mode: oauth` (see [setup.md](setup.md)).
A static page can't run the OAuth `code → token` exchange itself (it needs the client
secret, and GitHub's token endpoint sends no CORS headers), so a tiny **Cloudflare
Worker** does it. **One Worker serves every consumer repo.**

- Live instance: `https://digit-ci-auth.egovernments.workers.dev` — baked into the page
  as `AUTH_BASE` in `pages/actions/index.html`.
- The source lives in this doc (below) so it stays versioned and reviewable; redeploy by
  copying it into the Cloudflare editor or `wrangler deploy`.

## Access model

Signing in grants **no new access** — the page acts **as the signed-in user**, and
GitHub enforces that user's real role on every call, per repository:

| Person (on the repo) | View runs | Run a build |
|---|---|---|
| No access | 404 (repo invisible) | — |
| Read-only | yes | 403 |
| Write / Maintain / Admin | yes | yes |

Identical to the native Actions tab. It does **not** work for everyone.

> **OAuth App tradeoff:** a classic OAuth App has only coarse scopes, so the issued
> token carries `repo` (or `public_repo`) across all of the user's repos — the page only
> ever calls the one repo, but the token itself is broad. A GitHub App would be narrower;
> an OAuth App is used here by choice.

## 1. Create the OAuth App (org owner)

**GitHub → Settings → Developer settings → OAuth Apps → New OAuth App**

| Field | Value |
|---|---|
| Application name | e.g. `DIGIT Code Build` |
| Homepage URL | `https://egovernments.github.io/DIGIT-Studio/` |
| Authorization callback URL | `https://digit-ci-auth.egovernments.workers.dev/auth/callback` |

Generate a **client secret**; note the **Client ID** (public). If the org restricts
OAuth Apps, an owner must **approve** it once.

## 2. Deploy the Worker

**Dashboard (no CLI):** Workers & Pages → Create → Worker → paste `worker.js` → Deploy,
then **Settings → Variables & Secrets**. **wrangler:** `wrangler deploy` from a dir
holding the two files below, then `wrangler secret put …`.

| Name | Kind | Value |
|---|---|---|
| `GITHUB_CLIENT_ID` | var | the OAuth App Client ID |
| `GITHUB_CLIENT_SECRET` | secret | the OAuth App client secret |
| `STATE_SECRET` | secret | `openssl rand -hex 32` |
| `ALLOWED_ORIGINS` | var | `https://egovernments.github.io` |
| `SCOPE` | var | `repo` (private repos) or `public_repo` |

Confirm with `curl https://digit-ci-auth.egovernments.workers.dev/health` → `ci-auth-worker ok`.

> The `workers.dev` subdomain (`egovernments`) is an **account-level**, set-once name;
> change it only via the Cloudflare dashboard (or delete + re-create via the API).

## Worker source

`worker.js`:

```js
// GitHub OAuth broker for the Code Build dispatcher (the /actions page).
//
// One Worker serves EVERY consumer repo. The static dispatcher page cannot run an
// OAuth code->token exchange itself (it needs the client secret, and GitHub's token
// endpoint sends no CORS headers), so this Worker does it:
//
//   page  --/auth/login?redirect=<page>&n=<nonce>-->  Worker  --302-->  github.com/login/oauth/authorize
//   github --code,state--> Worker /auth/callback --exchange--> <page>#token=<t>&state=<nonce>
//
// The page then uses that user token to talk to api.github.com AS THE SIGNED-IN USER,
// so access stays exactly native: GitHub enforces each person's real repo role on
// every call (dispatch needs write, viewing needs read; no access -> 404).
//
// Environment (Cloudflare dashboard -> the Worker -> Settings -> Variables & Secrets):
//   GITHUB_CLIENT_ID      var     - OAuth App Client ID
//   GITHUB_CLIENT_SECRET  secret  - OAuth App Client Secret
//   STATE_SECRET          secret  - any long random string (e.g. `openssl rand -hex 32`)
//   ALLOWED_ORIGINS       var     - comma-separated page origins allowed to log in,
//                                   e.g. "https://egovernments.github.io"
//   SCOPE                 var     - "repo" (private repos) or "public_repo" (public only)
//
// The OAuth App's "Authorization callback URL" must be exactly  https://<worker-host>/auth/callback

const enc = new TextEncoder();
const STATE_TTL_MS = 10 * 60 * 1000;   // a login attempt is valid for 10 minutes

function b64url(bytes) {
  let s = btoa(String.fromCharCode.apply(null, new Uint8Array(bytes)));
  return s.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function b64urlToStr(s) {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4) s += "=";
  return atob(s);
}
async function hmac(secret, msg) {
  const key = await crypto.subtle.importKey(
    "raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return b64url(await crypto.subtle.sign("HMAC", key, enc.encode(msg)));
}
async function signState(secret, obj) {
  const body = b64url(enc.encode(JSON.stringify(obj)));
  return body + "." + (await hmac(secret, body));
}
async function verifyState(secret, state) {
  const dot = (state || "").indexOf(".");
  if (dot < 1) return null;
  const body = state.slice(0, dot), sig = state.slice(dot + 1);
  const expect = await hmac(secret, body);
  if (sig.length !== expect.length) return null;
  let diff = 0;
  for (let i = 0; i < sig.length; i++) diff |= sig.charCodeAt(i) ^ expect.charCodeAt(i);
  if (diff !== 0) return null;
  try { return JSON.parse(b64urlToStr(body)); } catch (e) { return null; }
}
function originOf(u) { try { return new URL(u).origin; } catch (e) { return ""; } }
function allowed(env, redirect) {
  return (env.ALLOWED_ORIGINS || "").split(",").map(s => s.trim()).filter(Boolean)
    .includes(originOf(redirect));
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/auth/login")    return login(url, env);
    if (url.pathname === "/auth/callback") return callback(url, env);
    if (url.pathname === "/auth/refresh")  return refresh(request, env);
    if (url.pathname === "/" || url.pathname === "/health")
      return new Response("ci-auth-worker ok", { status: 200, headers: { "content-type": "text/plain" } });
    return new Response("Not found", { status: 404 });
  }
};

async function login(url, env) {
  const redirect = url.searchParams.get("redirect") || "";
  const nonce = url.searchParams.get("n") || "";
  if (!allowed(env, redirect)) return new Response("redirect origin not allowed", { status: 400 });
  const state = await signState(env.STATE_SECRET, { r: redirect, n: nonce, t: Date.now() });
  const gh = new URL("https://github.com/login/oauth/authorize");
  gh.searchParams.set("client_id", env.GITHUB_CLIENT_ID);
  gh.searchParams.set("redirect_uri", url.origin + "/auth/callback");
  gh.searchParams.set("scope", env.SCOPE || "repo");
  gh.searchParams.set("state", state);
  gh.searchParams.set("allow_signup", "false");
  return Response.redirect(gh.toString(), 302);
}

async function callback(url, env) {
  const code = url.searchParams.get("code") || "";
  const st = await verifyState(env.STATE_SECRET, url.searchParams.get("state") || "");
  if (!code || !st) return new Response("bad or missing state", { status: 400 });
  if (Date.now() - (st.t || 0) > STATE_TTL_MS) return new Response("login expired, try again", { status: 400 });
  if (!allowed(env, st.r)) return new Response("redirect origin not allowed", { status: 400 });

  let data = {};
  try {
    const res = await fetch("https://github.com/login/oauth/access_token", {
      method: "POST",
      headers: { "Accept": "application/json", "Content-Type": "application/json" },
      body: JSON.stringify({
        client_id: env.GITHUB_CLIENT_ID,
        client_secret: env.GITHUB_CLIENT_SECRET,
        code,
        redirect_uri: url.origin + "/auth/callback"
      })
    });
    data = await res.json();
  } catch (e) { data = { error: "network_error" }; }

  const back = new URL(st.r);
  if (data && data.access_token) {
    const p = new URLSearchParams();
    p.set("token", data.access_token);
    p.set("state", st.n || "");
    if (data.expires_in) p.set("expires_in", String(data.expires_in));
    // refresh_token is present only when the OAuth App has "Expire user access
    // tokens" on; the page stores it and calls /auth/refresh to renew silently.
    if (data.refresh_token) p.set("refresh_token", data.refresh_token);
    back.hash = p.toString();
  } else {
    back.hash = "auth_error=" + encodeURIComponent((data && data.error) || "exchange_failed");
  }
  return Response.redirect(back.toString(), 302);
}

// CORS: echo the request Origin when it is on the allowlist (the page fetches
// /auth/refresh cross-origin from github.io).
function corsHeaders(request, env) {
  const origin = request.headers.get("Origin") || "";
  const ok = (env.ALLOWED_ORIGINS || "").split(",").map(s => s.trim()).filter(Boolean).includes(origin);
  const h = { "Vary": "Origin" };
  if (ok) {
    h["Access-Control-Allow-Origin"] = origin;
    h["Access-Control-Allow-Methods"] = "POST, OPTIONS";
    h["Access-Control-Allow-Headers"] = "content-type";
    h["Access-Control-Max-Age"] = "86400";
  }
  return h;
}

function json(obj, status, extra) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: Object.assign({ "content-type": "application/json" }, extra || {})
  });
}

// Exchange a refresh_token for a fresh access token (the client secret stays
// server-side). The page calls this when its access token 401s; GitHub returns a
// new access_token AND a rotated refresh_token.
async function refresh(request, env) {
  const cors = corsHeaders(request, env);
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (request.method !== "POST") return new Response("method not allowed", { status: 405, headers: cors });
  if (!cors["Access-Control-Allow-Origin"]) return new Response("origin not allowed", { status: 403 });

  let body = {};
  try { body = await request.json(); } catch (e) {}
  const rt = body && body.refresh_token;
  if (!rt) return json({ error: "missing refresh_token" }, 400, cors);

  let data = {};
  try {
    const res = await fetch("https://github.com/login/oauth/access_token", {
      method: "POST",
      headers: { "Accept": "application/json", "Content-Type": "application/json" },
      body: JSON.stringify({
        client_id: env.GITHUB_CLIENT_ID,
        client_secret: env.GITHUB_CLIENT_SECRET,
        grant_type: "refresh_token",
        refresh_token: rt
      })
    });
    data = await res.json();
  } catch (e) { data = { error: "network_error" }; }

  if (!data || !data.access_token) return json({ error: (data && data.error) || "refresh_failed" }, 400, cors);
  return json({
    access_token: data.access_token,
    expires_in: data.expires_in,
    refresh_token: data.refresh_token,
    refresh_token_expires_in: data.refresh_token_expires_in
  }, 200, cors);
}
```

`wrangler.toml`:

```toml
name = "digit-ci-auth"
main = "worker.js"
compatibility_date = "2024-11-01"

# Non-secret vars can live here (or set them in the dashboard). Secrets must be set
# with `wrangler secret put <NAME>` or in the dashboard — never commit them.
#
#   GITHUB_CLIENT_ID      -> var    (dashboard or `[vars]` below)
#   GITHUB_CLIENT_SECRET  -> secret (`wrangler secret put GITHUB_CLIENT_SECRET`)
#   STATE_SECRET          -> secret (`openssl rand -hex 32` then `wrangler secret put STATE_SECRET`)
#
[vars]
ALLOWED_ORIGINS = "https://egovernments.github.io"
SCOPE = "repo"
# GITHUB_CLIENT_ID = "Iv1..."   # safe to set here (it is not secret), or set in the dashboard
```

## Flow & security notes

- `/auth/login?redirect=<page>&n=<nonce>` → 302 to GitHub authorize. `state` is
  HMAC-signed (`STATE_SECRET`) and carries the redirect + nonce + timestamp.
- `/auth/callback` verifies the signature + 10-min freshness, checks the redirect origin
  against `ALLOWED_ORIGINS`, exchanges the code, and 302s back to the page with the token
  in the URL **fragment** (`#token=…`), which never reaches any server.
- The page verifies `state` matches the nonce it stored, then holds the access token in
  `sessionStorage` (per-tab; cleared on tab close / 15-min idle / Disconnect) — the same
  path as the PAT, so refresh-persistence and per-repo access apply identically.
- The token appears briefly in the page URL fragment (and history); the page strips it
  immediately. Rotate `GITHUB_CLIENT_SECRET` if it is ever exposed.

### Token refresh

The OAuth App has **"Expire user access tokens"** on, so the access token lasts ~8h and
the callback also returns a `refresh_token`. The Worker exposes **`POST /auth/refresh`**:

- The page stores the `refresh_token` alongside the access token (per-tab `sessionStorage`).
- When an `api.github.com` call returns **401**, the page posts the refresh token to
  `/auth/refresh`; the Worker exchanges it (`grant_type=refresh_token`, client secret
  server-side) for a new access token (GitHub also rotates the refresh token), returns
  them as JSON, and the page retries the call — so an ~8h-old session renews silently
  instead of forcing a re-login.
- `/auth/refresh` only answers requests whose `Origin` is in `ALLOWED_ORIGINS` (echoed
  back as the CORS header; others get 403), and it handles the CORS pre-flight. The
  consumer page's CSP therefore allows `connect-src` to this Worker in addition to
  `api.github.com`.
- The `refresh_token` is longer-lived than the access token; like the access token it
  lives only in the tab's `sessionStorage` and is cleared on tab close / idle / Disconnect.
  (GitHub can't mint a refresh token into a server-side cookie that a cross-site page in
  Brave/Safari would reliably read, so the page holds it.)
