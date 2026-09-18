# mimoto-issuers-config.json — digit-lts

Documentation for `mimoto-issuers-config.json`. It lives here rather than as
`_comment` keys **inside** the JSON, on purpose — see "Why no comments in the
file" below.

## Why this file replaces the upstream one

Upstream shipped 7 demo issuers (`MosipOtp`, `Mosip`, `StayProtected`, `Mock`,
`MosipTAN`, `Land`, `MockMdl`). None is usable here:

- Every one points at MOSIP's own sandbox hosts.
- They reference 12 placeholders that nothing in this config directory defines
  (`mimoto.oidc.*.partner.clientid`, `sunbirdrc.insurance.esignet.host`,
  `mosip.injicertify.mosipid.host`, …). Mimoto would have served a wallet
  listing seven issuers it cannot reach.
- All 7 use `redirect_uri: io.mosip.residentapp.inji://oauthredirect` — an
  Android/iOS deep link for the **mobile** wallet. The web wallet needs an
  https redirect back to injiweb, so none of them would complete an
  authorization round trip in a browser.

The upstream file is preserved at `mimoto-issuers-config.json.upstream` for
diffing on an Inji version bump.

## Why no comments in the file

`mimoto-issuers-config.json` is deserialized into `IssuersDTO` by Jackson and
then bean-validated at startup by `IssuersValidationConfig` — a failure there
aborts the whole Spring context (`Application run failed`), it is not a warning.

None of `IssuersDTO`, `IssuerDTO`, `DisplayDTO` or `LogoDTO` carries
`@JsonIgnoreProperties(ignoreUnknown = true)` (verified against the field
annotations in `mosipid/mimoto:0.20.0`). Unknown keys therefore survive only
because Spring Boot's auto-configured `ObjectMapper` happens to disable
`FAIL_ON_UNKNOWN_PROPERTIES`. That is a default, not a guarantee: any future
`spring.jackson.deserialization.fail-on-unknown-properties=true`, or an Inji
version that declares its own `ObjectMapper` bean, turns every `_comment` key
into a startup crash.

Keeping the JSON strictly DTO-shaped costs nothing and removes that failure
mode entirely.

## Required fields

`IssuerDTO` marks 13 fields `@NotBlank`/`@NotEmpty` — all must be present and
non-blank or the context fails to start:

| Field | Notes |
|---|---|
| `issuer_id` | |
| `credential_issuer` | |
| `credential_issuer_host` | also `@URL` |
| `display` | `@NotEmpty` list, each entry `@Valid` |
| `protocol` | |
| `client_id` | |
| `client_alias` | |
| `wellknown_endpoint` | also `@URL` |
| `redirect_uri` | |
| `token_endpoint` | also `@URL` |
| `authorization_audience` | |
| `proxy_token_endpoint` | also `@URL` |
| `enabled` | **String, not boolean** — `@NotBlank` on a `String` field, so `"true"` validates and `true` does not |

`qr_code_type` is the only optional field. In `DisplayDTO`, `name`, `title`,
`description` and `language` are required and `logo` is optional; when `logo`
is present both `url` and `alt_text` are required.

## Field-by-field rationale

**`client_id`** — must match a client registered with eSignet. Supplied as the
placeholder `${mimoto.oidc.digitlts.partner.clientid}`, which config-server
resolves when it serves the file (confirmed: the served response contains
`"client_id": "digitlts-mimoto"`). Registration is performed by the
`inji-esignet-client` chart against eSignet's client-management API and has
already run — without it the authorization request is rejected with
`invalid_client`. The public key registered there must be the one in
`oidckeystore.p12` under `client_alias`.

**`wellknown_endpoint`** — Certify serves issuer metadata under its servlet
path, so this keeps the upstream shape
(`/v1/certify/issuance/.well-known/openid-credential-issuer`) rather than the
host root. The host-root form is what a *wallet* discovers via the credential
offer; this field is the explicit endpoint *Mimoto* fetches. The host-root
paths are served too, via the `wellKnownRewrite` rule in the `inji-ingress`
chart, because `did:web:injicertify.test-lts.digit.org` resolves there.

**`redirect_uri`** — https back to the web wallet, not the mobile deep link
every upstream issuer used. This is the change that makes the browser flow
work.

**`token_endpoint`** — Mimoto's own proxy, reached same-origin through
injiweb's nginx (`/v1/mimoto` → `mimoto-service`). Deliberately not on a Mimoto
hostname: Mimoto has no Ingress in the web-wallet scope.

## How Mimoto loads this file

It is **fetched back over HTTP from config-server**, not read from disk:

```
IssuersValidationConfig (startup)
  -> IssuersServiceImpl.getAllIssuers()
    -> Utilities.getIssuersConfigJsonValue()
      -> restApiClient.getApi(config.server.file.storage.uri + mosip.openid.issuers)
```

which resolves to

```
http://config-server.inji/config/mimoto/{profiles}/{label}/mimoto-issuers-config.json
```

That fetch requires `mosip.iam.adapter.disable-self-token-rest-template=true`
(set in `mimoto-digit-lts.properties`) so it uses `plainRestTemplate` instead
of `selfTokenRestTemplate`; otherwise Mimoto demands a token from MOSIP's
collab Keycloak and startup fails. The rationale is documented at length in
`mimoto-digit-lts.properties`.

Note the consequence for edits: changing this file requires config-server to
serve the new revision **and** a Mimoto restart, since the result is also
`@Cacheable("issuersConfig")`.
