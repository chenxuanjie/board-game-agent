# Synology SSO Server → Supabase Auth deployment

Status: tooling and offline tests only. The live Supabase instance, NAS issuer,
Well-known URL, OIDC client ID/secret and Supabase admin key have not been supplied.
No NAS metadata was probed, provider created, login tested, server deployed, app
built or commit made for this tooling. Production Web BFF deployment is
**unverified**; this tooling does not deploy one.

Network observations supplied by the coordinating owner on 2026-10-04 (not
re-probed by this tooling):

| Request | Supplied result | What it establishes |
| --- | --- | --- |
| `HEAD https://cznas.dpdns.org:5001/` | Strict TLS succeeds; HTTP 200 | The DSM HTTPS origin is reachable with valid TLS from that observer's environment. |
| `https://cznas.dpdns.org:5001/.well-known/openid-configuration` | HTTP 403 | This guessed discovery URL did not provide usable OIDC metadata. |
| `https://cznas.dpdns.org:5001/webman/sso/.well-known/openid-configuration` | HTTP 403 | This second guessed discovery URL did not provide usable OIDC metadata. |
| `https://cznas.dpdns.org:5001/webman/sso/` | HTTP 404 | This path did not establish a live OIDC issuer or discovery endpoint. |
| DSM `SYNO.API.Info` | `SYNO.API.Auth` versions 1–7 | DSM API availability only; not SSO Server OIDC support or an authentication fallback. |

These observations do not identify the actual Well-known URL, issuer, JWKS or
OIDC client configuration. They do not prove OIDC is absent: SSO Server package,
enablement, application permissions and reverse-proxy routing remain unknown.
The exact configuration question is already pending with the user. Do not
substitute a guessed DSM URL into the private configuration or switch to direct
DSM password authentication. **Actual end-to-end login is not verified.**

The existing public `../shared_packages/app_identity` adapter pins
`supabase_flutter` **2.17.2** and requests `custom:synology`. Supabase Auth owns
OIDC discovery, authorization, token exchange and ID-token verification. The
Python script only inspects metadata and optionally registers that provider.
Never implement DSM password authentication, collect NAS passwords, mint app
identity tokens, or replace the official SDK's authentication protocol here.

## Official compatibility baseline

References checked on 2026-10-04:

| Reference | Behavior used |
| --- | --- |
| [Self-hosted custom OAuth/OIDC providers](https://supabase.com/docs/guides/self-hosting/self-hosted-custom-oauth-providers) | Self-hosted release **0.8.1+**, Auth **v2.196.0+**; project gateway admin API and HTTPS callback configuration. |
| [Custom OAuth/OIDC providers](https://supabase.com/docs/guides/auth/custom-oauth-providers) | `custom:` identifiers, OIDC discovery override, scopes, provider PKCE and email policy. |
| [Auth v2.196.0 admin implementation](https://github.com/supabase/auth/blob/v2.196.0/internal/api/custom_oauth_admin.go) | Create fields, `{ "providers": [...] }` list envelope, create conflict and discovery validation. |
| [Auth v2.196.0 custom provider](https://github.com/supabase/auth/blob/v2.196.0/internal/api/provider/custom_oauth.go) | Official Go OIDC/OAuth implementation owns code exchange and audience validation; token authentication is SDK-selected. |
| [OIDC Discovery 1.0](https://openid.net/specs/openid-connect-discovery-1_0.html) | Exact issuer equality, advertised capabilities and distinction between omitted metadata and explicit values. |
| [Synology SSO Server service](https://kb.synology.com/en-global/DSM/help/SSOServer/sso_server_service?version=7) | NAS Well-known URL, issuer and username-based subject semantics. |
| [Synology SSO applications](https://kb.synology.com/en-us/DSM/help/SSOServer/sso_server_application_list?version=7) | Operator creates the NAS OIDC application and registers its callback. |

The Flutter SDK version does not establish the Auth server version. Record the
actual NAS DSM/SSO Server package versions, Supabase image version/digest and
gateway configuration before acceptance. A successful admin-list request proves
that this endpoint is accessible to that key, not that login works. Hosted
Supabase can use its custom-provider dashboard; this tool targets the documented
project gateway API, not the Supabase Management API or Supabase's OAuth **server**.

No external Python dependency or upstream source code is copied. The CLI uses
the standard library because it needs no auth implementation: Auth's maintained
server and the existing pinned Flutter SDK perform authentication. Pin and review
upstream upgrades separately; re-run these contract tests and real login tests
when Auth, DSM/SSO Server or the Flutter SDK changes. This is not a vulnerability
audit of those deployed services.

## Private configuration

Copy [the private example](../scripts/identity/private-config.example.json) to an
operator-only directory **outside the repository**, and fill exactly these six
keys. The example has reserved `.invalid` URLs and empty credentials and cannot
be used accidentally for network work.

| Key | Required value |
| --- | --- |
| `issuer` | Exact HTTPS issuer advertised by this NAS. Preserve its case, path and trailing slash. |
| `discoveryUrl` | Exact HTTPS Well-known URL copied from SSO Server. Do not guess its path. |
| `supabaseUrl` | Project HTTPS gateway base URL, possibly including a gateway prefix; exclude `/auth/v1`. |
| `clientId` | NAS application ID for **Supabase Auth as a confidential client**. |
| `clientSecret` | NAS application secret, stored only by the operator and Supabase Auth. |
| `adminKey` | Project secret key or legacy service-role key accepted by the documented gateway admin API. |

Empty credential strings are permitted for metadata inspection only; all keys
must still exist. `--apply` requires all three credentials. Extra keys, duplicate
JSON keys, non-string values and files over 16 KiB are rejected. No environment
credentials or private configuration are discovered automatically. Do not paste
the private file into chat, a report, Flutter assets or `--dart-define`.

On POSIX restrict the file to the operator (`chmod 600`); the tool rejects group
or other access. On Windows restrict its ACL using your normal secure file
workflow; the Python standard library does not verify Windows ACLs. The local
`scripts/identity/.gitignore` excludes `*.private.json`, but does not make a file
private or protect files placed elsewhere. Protect Supabase backups and enable
its documented database secret-encryption configuration where supported.

## Run the read-only probe

From the main repository, with Python 3.10+:

```powershell
python -B scripts/identity/probe.py --config C:/private/identity.private.json
```

Only explicit configured URLs are used. The probe fetches discovery and its
`jwks_uri` using unauthenticated GETs. If `adminKey` is present, it also lists
providers with `GET {supabaseUrl}/auth/v1/admin/custom-providers`, passing the key
only in `apikey` to Supabase. It does not call NAS authorization, token, userinfo,
logout, password, DSM administration or session endpoints.

TLS verifies certificates and hostnames, requires TLS 1.2+, and follows **no HTTP
redirects**, including same-origin ones. URLs may not contain userinfo, queries
or fragments. Use the final Well-known URL if a proxy redirects. An explicitly
configured HTTPS discovery override may have another origin; its returned issuer
must still exactly equal `issuer`. Metadata endpoint URLs must also be HTTPS.
JWKS may have another HTTPS origin; the configured discovery document therefore
defines the trust boundary for that unauthenticated GET.

Connections are direct: environment proxy settings and ambient credentials are
not used. If a NAS uses a private CA, provide an operator-approved PEM trust
bundle with `--ca-file C:/private/nas-trust.pem`. This preserves verification;
there is no insecure-TLS switch. Supabase Auth's runtime needs its own appropriate
trust configuration and outbound access; a laptop probe cannot prove those.

Each socket operation has an 8-second timeout and responses are limited to
512 KiB. A worker process has a 45-second wall deadline covering DNS lookup and
slow-drip reads; forced termination/cleanup may add up to approximately 2 seconds.
There are at most five requests, no automatic retries, and Ctrl+C stops the
worker. Content encoding is restricted to identity; compressed responses are
refused rather than decompressed without a bound.

The probe conservatively requires advertised `code`, requested scopes, PKCE
`S256`, a public/pairwise subject type and a supported asymmetric signing
algorithm, plus a structurally plausible matching public JWKS key. Confidential
token authentication must advertise `client_secret_basic` or `client_secret_post`.
It does not register unsupported `token_endpoint_auth_method` fields: the official
Auth OAuth client selects authentication when actually exchanging a code.
RSA keys must be 2048–8192 bits; common EC curves and Ed25519 are structurally
checked. This does not verify signatures, curve points, key possession or tokens.

Default scopes are `openid profile email`, and the provider requires an email.
If this NAS lacks email support, choose an explicit application policy and use
`--scopes openid profile --email-optional` consistently on inspection and creation.
An advertised email scope does not prove any particular account has an email or
that its email is verified. Never auto-link accounts on unverified email alone.

Missing capability metadata is reported as `null`/`unknown`, not as operational
support or failure. Missing token-auth metadata has a standards default, but this
conservative probe still blocks creation until compatibility is established.
Missing `grant_types_supported` remains unknown; its omission alone does not
block because OIDC defines defaults. An explicit list excluding
`authorization_code` does block. Missing `S256` advertisement also blocks this
tool's creation path; absence does not prove that the NAS cannot use PKCE. There
is no automatic downgrade to implicit flow, disabled PKCE or skipped nonce checks.

`refreshTokenGrant`, `offlineAccessScope` and `publicClientTokenAuthNone` report
advertisements only. They do **not** prove issuance, refresh, public-client
registration, offline consent or per-account permissions. The browser/native app
is a public client of **Supabase**; it does not need a secretless NAS registration.
NAS provider tokens and Supabase session refresh tokens are separate systems.

### Redacted JSON and exit codes

Reports contain local check names/codes, booleans, counts and selected supported
capabilities. Configuration URLs, client ID, secrets, raw discovery/JWKS, JWK
values/IDs, admin responses, exception messages and HTTP bodies/headers are not
printed. Error responses contain at most a numeric HTTP status. Do not enable
external HTTP request/body tracing when using private configuration.

Example report excerpt, not a result from a deployed service:

```json
{
  "schemaVersion": 1,
  "provider": "custom:synology",
  "status": "metadata_compatible",
  "configuration": {
    "clientId": "[REDACTED]",
    "clientSecret": "[REDACTED]",
    "adminKey": "[ABSENT]",
    "emailOptional": false
  },
  "apply": { "requested": false, "state": "not_attempted" },
  "supabaseAdmin": { "checked": false, "providerExists": null }
}
```

Exit `0`: compatible inspected metadata, or newly registered configuration;
neither means authenticated sessions are accepted. Exit `2`: invalid config,
unknown required compatibility, failed check, network/admin error, existing
provider on apply, cancellation or an uncertain creation outcome. Inspect the
complete JSON; `metadata_compatible` can coexist with an untested admin API when
no key was supplied. `registered_login_unverified` means create/list verification
only. Every successful metadata report includes explicit assurance flags that
keep login, token verification, refresh, revocation and BFF deployment unverified.

## Optional create-only registration

The following is an operator action after reviewing the private configuration,
metadata report and NAS/Supabase callback settings; it was **not run** here:

```powershell
python -B scripts/identity/probe.py --config C:/private/identity.private.json --apply
```

The command repeats the read-only checks and admin listing. If `custom:synology`
already exists it stops, even if its visible settings match; it cannot verify the
stored secret. If prerequisites pass and it is absent, it makes exactly one
`POST {supabaseUrl}/auth/v1/admin/custom-providers`, with JSON containing:
`provider_type=oidc`, `identifier=custom:synology`, client ID/secret, exact issuer,
`discovery_url`, requested scopes, `pkce_enabled=true`, `skip_nonce_check=false`,
explicit email policy and `enabled=true`. These are official API fields.

It then lists again and checks saved non-secret fields. No PUT/PATCH/DELETE,
destructive overwrite, token exchange, automatic deployment or automatic rollback
exists. A timeout, lost response or server 5xx after POST may mean creation
succeeded: `outcome_unknown` requires a **read-only** inspection before another
operator action. `created_verification_pending` means the create response was
received but the subsequent verification failed. A rerun refuses an existing
identifier instead of replacing it. Reverse-proxy denial, old Auth versions and
disabled custom providers must be resolved by the deployment owner.

## Two distinct redirect registrations

| Hop | Register where | Exact example |
| --- | --- | --- |
| **NAS → Supabase Auth** | NAS SSO Server OIDC application's redirect URI | `https://supabase.example.invalid/auth/v1/callback` |
| **Supabase → Web app/BFF** | Supabase Auth redirect allowlist and SDK `redirectTo` | `https://app.example.invalid/auth/callback` |
| **Supabase → native app** | Supabase Auth allowlist and Android/Windows OS URI handler | `com.example.boardgameagent://login-callback/` |

The native URI and app Web URL belong to the **second** hop. They are not NAS
callbacks. Supabase first consumes the NAS authorization code, then redirects to
the app's allowlisted destination. Copy a hosted project's actual provider
callback from its dashboard. For self-hosting configure `API_EXTERNAL_URL` as the
externally reachable Auth base ending in `/auth/v1`; review any
`GOTRUE_CUSTOM_OAUTH_EXTERNAL_URL` override and gateway prefix. The NAS callback
is that external Auth base plus `/callback`.
[Official callback setup](https://supabase.com/docs/guides/self-hosting/self-hosted-custom-oauth-providers)
and [app redirect allowlists](https://supabase.com/docs/guides/auth/redirect-urls)
describe these separate registrations.

Configure the Web site URL and exact additional redirects in hosted URL
Configuration or the self-hosted `SITE_URL`/`ADDITIONAL_REDIRECT_URLS` settings.
Avoid production wildcards. Native return requires real Android intent filters
and Windows URI registration/activation handling; an allowlist entry alone does
not install an OS handler. None of those settings are changed by this script.

There are also two independent PKCE legs: the SDK/BFF → Supabase leg must use
the official SDK PKCE flow, and the Supabase → NAS leg uses provider
`pkce_enabled=true`. The probe's NAS `S256` check covers only the latter.

## Public/developer client configuration

[The public example](../scripts/identity/public-client-config.example.json) is an
illustrative host configuration, not an automatically imported Flutter config.
It contains a project URL, public publishable/legacy anon key, provider ID and
callback URIs. Map these to existing `app_identity` configuration without adding
NAS secrets or admin keys. For SDK development/native integration:

```dart
await Supabase.initialize(
  url: publicConfig.supabaseUrl,
  anonKey: publicConfig.supabasePublishableKey,
  authOptions: const FlutterAuthClientOptions(
    authFlowType: AuthFlowType.pkce,
  ),
);
final configuration = IdentityConfiguration(
  synologyProviderId: 'custom:synology',
  webCallback: Uri.parse(publicConfig.webRedirectTo),
  androidCallback: Uri.parse(publicConfig.nativeRedirectTo),
  windowsCallback: Uri.parse(publicConfig.nativeRedirectTo),
);
// Use SupabaseIdentityGateway and wait for its signed-in event.
```

`publicConfig` above is a host-owned value object, not a new API supplied by this
tool. Retain the package's `OAuthProvider('custom:synology')` SDK path. Launching
a browser does not establish a session. Native secure storage and callback
handlers must be connected and tested by the host app owner.

### Production Web: HttpOnly BFF requirement

For this project's production Web requirement, session credentials must remain
behind an actual BFF (backend for frontend), with an opaque browser session cookie
marked `HttpOnly`, `Secure` and an appropriate `SameSite` policy. The BFF uses
the official Supabase SDK for PKCE exchange, token validation, refresh and logout;
it stores Supabase tokens server-side and proxies authenticated app operations.
It needs CSRF/origin protection, isolated per-user sessions, bounded requests,
refresh coordination, session deletion and non-cacheable authenticated responses.
Its second-hop callback is a real BFF HTTPS route, not a static placeholder.

A browser SDK using local storage, IndexedDB or JavaScript-readable cookies
cannot satisfy HttpOnly token isolation. PKCE and the Web version of a secure
storage wrapper do not change that distinction. Supabase's normal SSR/browser
cookie setup also allows client SDK access to maintain sessions; it must not be
presented as an HttpOnly-only BFF. This is a project architecture requirement,
not a claim that Supabase requires every app to use a BFF.
[Supabase's SSR/storage explanation](https://supabase.com/docs/guides/auth/server-side/advanced-guide)
explains the browser/session tradeoff.

No BFF implementation, route, cookie or deployed service is supplied here.
`productionWebBffUrl: null` explicitly preserves that blocker; a development
browser-storage example must not be advertised as production-compliant Web auth.
Another owner may implement the server separately and supply its real endpoint
and acceptance evidence before production Web login is enabled.

## Identity lifecycle and access control

- **NAS rename/reuse:** Synology documents `sub` as the username, potentially
  suffixed with the directory domain. Rename or directory migration can change
  the provider subject, so do not assume an immutable NAS subject. Reusing an old
  username can also reuse an identity identifier. Define controlled migration
  and no-reuse policy, test on non-production accounts, and retain audit evidence;
  never silently merge on display name or unverified email. App data ownership
  uses the stable Supabase Auth user UUID and server-enforced RLS.
  [Synology claim definitions](https://kb.synology.com/en-global/DSM/help/SSOServer/sso_server_service?version=7)
- **Disable/revoke:** disabling a NAS account or removing OIDC app access is not
  proven to revoke an already issued Supabase session. Disabling a provider can
  stop new sign-ins without revoking existing sessions. NAS logout, local app
  logout, Supabase global logout and administrative access removal are different
  actions. Define coordinated app/Supabase deprovisioning and test propagation;
  immediate denial needs server-side authorization/session checks, not a cached
  client boolean. The probe does none of these actions.
- **Expired sessions:** a Supabase access token can expire while its refresh token
  can still rotate it. Failed/revoked refresh must converge to reauthentication
  and confirmed local-session cleanup. An offline cached profile remains
  unverified; it may expose only account-scoped local data, not prove server access.
  Test clock skew, expired codes, invalid refresh, cold starts and network loss.
- **Revocation latency:** session revocation does not invalidate every already
  issued JWT immediately. Signature/expiry validation alone can accept it until
  expiry; sensitive server operations need suitable live session/user/permission
  checks. Session timebox/inactivity checks and JWT expiry are separate. Establish
  a documented maximum access-removal delay with the deployment owner.
  [Supabase session semantics](https://supabase.com/docs/guides/auth/sessions)
- **Logout scope:** the existing adapter chooses local-session logout. Global
  logout is a separate deliberate action and may affect other devices. Deleting
  local storage offline is not confirmed server revocation. Do not promise NAS
  single logout or refresh-token revocation from discovery flags.
  [Supabase sign-out semantics](https://supabase.com/docs/reference/javascript/auth-signout)

## Validation, blockers and recovery

Offline verification command (no external service calls):

```powershell
python -B -m unittest discover -s scripts/identity -p test_probe.py -v
```

Tests cover exact issuer/discovery handling, strict config/URL validation,
redaction and malicious response content, capability absence versus explicit
failure, structural JWKS checks, TLS verification, redirect refusal, response and
request budgets, network failures, process termination, read-only credentials,
create conflicts, saved-field verification and ambiguous POST results.

Deployment acceptance still requires the following **operator/host-owner** work:

| Case | Required evidence | Current result |
| --- | --- | --- |
| NAS metadata and Auth configuration | Real version record, TLS trust, read-only JSON report, exact redirect settings, Auth-runtime reachability | Blocked: private config unavailable |
| Login and token checks | Valid user, bad client secret, bad audience/issuer, code replay, PKCE/nonce failure, missing email; official Auth rejects invalid tokens | Not run |
| Identity migration and access removal | Controlled NAS rename/reuse policy; NAS disable, Supabase revocation and measured access-removal delay | Not run |
| Web | Real HttpOnly BFF, CSRF/no-cache checks, no tokens in browser storage, expired session, cancellation, network loss | Blocked: BFF deployment and acceptance unverified |
| Android | Real device browser return, installed intent filter, restart, expiry, logout and protected-data ownership | Not run |
| Windows | Installed URI handler, browser return, cold activation, expiry, logout and protected-data ownership | Not run |

Unknown live config has already been requested from the user; do not discover it
from passwords, logs, private account stores or unrelated resource credentials.
Keep private inputs in an explicitly supplied operator-only file. Until these
cases pass, this is deployment tooling, not a completed authentication deployment.

Recovery is manual and scoped: a failed read-only probe changes nothing. After
uncertain creation, inspect with the read-only probe and the deployment console.
If a newly created provider must be withdrawn, the owner can disable that exact
provider using the official admin/dashboard controls and separately handle its
issued sessions; preserve its identifier and identity records. Existing provider
changes/secret rotations require an operator-held backup and separate reviewed
procedure. This tool never overwrites providers or deletes users/identities/data.
