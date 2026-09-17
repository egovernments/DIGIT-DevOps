# amr-acr-mapping.json

Vendored verbatim from `mosip/mosip-config@v1.2.0.1-B3`.

eSignet fetches this at runtime, not from its own jar:

```properties
mosip.esignet.amr-acr-mapping-file-url=\
  ${spring_config_url_env}/*/${active_profile_env}/${spring_config_label_env}/amr-acr-mapping.json
```

which resolves against config-server to
`/config/*/default,inji-default,standalone,digit-lts,digit-landregistry/digit-lts/amr-acr-mapping.json`.

It was missing, and that URL returned **404** — verified directly against the
running config-server. The file maps the ACR values eSignet advertises in its
discovery document onto concrete authentication factors, so without it an
authorize request naming an ACR cannot be resolved to an auth method.

Left unmodified: the mappings are protocol-level, not environment-specific. The
ACR values it defines match what our eSignet already advertises as
`acr_values_supported`:

- `mosip:idp:acr:static-code` → PIN
- `mosip:idp:acr:generated-code` → OTP
- `mosip:idp:acr:linked-wallet` → WLA
- `mosip:idp:acr:biometrics` → BIO

The OIDC client registered by `inji-esignet-client` requests
`mosip:idp:acr:generated-code` (OTP), which the mock identity system supports
via its `send-otp` endpoint.
