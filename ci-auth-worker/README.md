# CI Auth Worker — "Sign in with GitHub" for the Code Build dispatcher

A tiny Cloudflare Worker that lets the `/actions` dispatcher log users in with their
own GitHub account instead of a pasted token. **One Worker serves every consumer
repo.** It exists only because a static page can't run an OAuth `code → token`
exchange (that needs the client secret, and GitHub's token endpoint has no CORS).

## Access model (important)

Signing in grants **no new access**. The page acts **as the signed-in user**, and
GitHub enforces that user's real role on every call:

| Person (on this repo) | View runs | Run a build |
|---|---|---|
| No access | ❌ 404 (repo invisible) | ❌ |
| Read-only | ✅ | ❌ 403 |
| Write / Maintain / Admin | ✅ | ✅ |

Identical to the native Actions tab, per repo. It does **not** work for everyone.

> **OAuth App tradeoff:** a classic OAuth App has only coarse scopes, so the issued
> token carries `repo` (or `public_repo`) across **all** of the user's repos — the
> page only ever calls the one repo, but the token itself is broad. A GitHub App
> would be narrower; this uses an OAuth App by request.

## 1. Create the OAuth App (org owner)

**GitHub → Settings → Developer settings → OAuth Apps → New OAuth App**

| Field | Value |
|---|---|
| Application name | e.g. `DIGIT Code Build` |
| Homepage URL | `https://egovernments.github.io/DIGIT-Studio/` |
| Authorization callback URL | `https://<WORKER-HOST>/auth/callback` |

Generate a **client secret**. Note the **Client ID** (public) and the secret (keep it off chat).
If the org has OAuth App access restrictions, an owner must **approve** the app for the org.

## 2. Deploy the Worker

**Dashboard (no CLI needed):** Workers & Pages → Create → Worker → paste `worker.js` →
Deploy. Then **Settings → Variables & Secrets** add:

| Name | Kind | Value |
|---|---|---|
| `GITHUB_CLIENT_ID` | var | the OAuth App Client ID |
| `GITHUB_CLIENT_SECRET` | secret | the OAuth App client secret |
| `STATE_SECRET` | secret | `openssl rand -hex 32` |
| `ALLOWED_ORIGINS` | var | `https://egovernments.github.io` |
| `SCOPE` | var | `repo` (private repos) or `public_repo` (public only) |

**Or with wrangler** (needs `wrangler login`):

```sh
cd ci-auth-worker
npx wrangler deploy
npx wrangler secret put GITHUB_CLIENT_SECRET
npx wrangler secret put STATE_SECRET          # paste `openssl rand -hex 32`
# GITHUB_CLIENT_ID / ALLOWED_ORIGINS / SCOPE are in wrangler.toml [vars]
```

The Worker's URL is `https://digit-ci-auth.<account>.workers.dev` — that host is the
`<WORKER-HOST>` used in the callback URL above. Check it with
`curl https://<WORKER-HOST>/health` → `ci-auth-worker ok`.

## 3. Point the dispatcher at the Worker

The page redirects to the Worker for login, so it needs the Worker host baked in as
`AUTH_BASE` in `templates/consumer/pages/actions/index.html`. That page change is the
follow-up to this PR — send the deployed **Worker host** and the **Client ID** and it
gets wired (and validated against the live Worker) before the PAT box is removed.

## Flow & security notes

- `/auth/login?redirect=<page>&n=<nonce>` → 302 to GitHub authorize. `state` is
  HMAC-signed (`STATE_SECRET`) and carries the redirect + nonce + timestamp.
- `/auth/callback` verifies the signature + 10-min freshness, checks the redirect
  origin against `ALLOWED_ORIGINS`, exchanges the code, and 302s back to the page with
  the token in the URL **fragment** (`#token=…`), which never reaches any server.
- The page verifies `state` matches the nonce it stored, then keeps the token in
  `sessionStorage` (per-tab; cleared on tab close / 15-min idle / Disconnect).
- The token appears briefly in the page URL fragment (and history); the page strips it
  immediately. Acceptable for this tool; rotate `GITHUB_CLIENT_SECRET` if ever exposed.
