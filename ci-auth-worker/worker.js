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
  back.hash = data && data.access_token
    ? "token=" + encodeURIComponent(data.access_token) + "&state=" + encodeURIComponent(st.n || "")
    : "auth_error=" + encodeURIComponent((data && data.error) || "exchange_failed");
  return Response.redirect(back.toString(), 302);
}
