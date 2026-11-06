# Notchi Get a link service

A TypeScript/Hono Cloudflare Worker with private R2 objects and Supabase Postgres/Auth. The macOS app, project and scheme are **Notchi**, with bundle ID `com.notchi.Notchi`. This pass prepares **local setup first** and does not create or deploy cloud resources.

## Local setup

Requirements: Node 22+, Docker Desktop running for the local Supabase stack, the pinned Supabase CLI v3 (installed by `npm ci`), and Postgres command-line tools only for the isolated SQL tests.

From this directory:

```sh
npm ci
npm run setup:local
npx supabase start
npx supabase migration up
npm run connect:local
```

`setup:local` creates a mode-0600, ignored `.dev.vars`, generates independent random application secrets, and never prints them. It preserves an existing file. `migration up` targets the local database by default in the pinned CLI and applies pending migrations without resetting local data. `connect:local` reads the running local project status and writes its keys into `.dev.vars` without displaying them. It refuses non-loopback origins. Restart an already-running Worker after connecting credentials. Do not commit or paste these credentials into logs. The schema migration is in `supabase/migrations/202611050001_links.sql`.

Then:

```sh
npm run dev:local
```

The Worker runs at `http://127.0.0.1:8787`, using Wrangler's persistent local R2 emulation and Supabase at port 54321. The local mail inbox is at `http://127.0.0.1:54324`. Only Debug builds of the Mac app allow a loopback HTTP service URL; set it in **Settings → Links**. Sign in with an email address, open its message in the local inbox, and click the link to return to the app. Local auth uses 15-minute JWTs and rotating refresh tokens. Apple sign-in needs the provider configuration described below; no real Apple authorization is faked by local mode.

Local object PUT URLs are HMAC-signed capabilities handled by the loopback Worker. Production uses actual AWS Signature V4 R2 presigned URLs. `LOCAL_DEVELOPMENT=true` fails closed on a non-loopback public origin and is absent from production configuration. Never deploy `wrangler.local.jsonc`.

Docker is not needed for `npm test`, TypeScript checks, the Worker dry run, or `npm run test:db`. The SQL test starts its own temporary, Unix-socket-only Postgres cluster containing synthetic identities, tests the migration and concurrency, then stops and removes that cluster. It does not connect to or reset any existing database.

## Environment variables and bindings

| Name | Purpose |
| --- | --- |
| `PUBLIC_BASE_URL` | Public Worker origin, e.g. `https://links.your-domain.test`; no path/query/trailing slash. |
| `FILES` | Private R2 bucket binding. Keep public bucket access/r2.dev disabled. |
| `SUPABASE_URL` | Supabase project origin; local setup uses port 54321. |
| `SUPABASE_ANON_KEY` | Public anon/publishable key used for Supabase Auth requests. |
| `SUPABASE_SERVICE_ROLE_KEY` | Server-only **service_role JWT** used by PostgREST RPCs. Never ship it in the app. |
| `R2_ACCOUNT_ID` | Cloudflare account ID. |
| `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` | Bucket-scoped R2 S3 credentials, read/write for this bucket only. |
| `R2_BUCKET_NAME` | Bucket name matching the binding. |
| `PASSWORD_PEPPER` | Independent random 32+ byte secret for password hashes. Keep stable or existing passwords stop working. |
| `DOWNLOAD_SIGNING_KEY` | Independent random 32+ byte secret for one-use download redirect tickets. |
| `ABUSE_HASH_KEY` | Independent random 32+ byte key for daily IP/email rate-limit hashes; raw IPs/emails are not stored in reports. |
| `PAID_MAX_BYTES`, `PAID_MAX_LINKS` | Larger paid limits; defaults roughly 1 GB and 50 links. Server-owned tier records enforce them. |
| `API_LIMITER`, `AUTH_LIMITER`, `PUBLIC_LIMITER` | Workers rate-limit bindings in Wrangler config. Choose namespace IDs unique to this app in your account. |
| `LOCAL_DEVELOPMENT`, `LOCAL_SIGNING_KEY` | Loopback-only R2 emulation; never enable on a deployed public service. |

For production, set nonsecret origins/limits and the bucket name in `wrangler.jsonc`; add keys with `npx wrangler secret put NAME`. Generate secrets with `openssl rand -hex 32`. The checked-in example contains placeholders only. The macOS app needs only the service origin; access tokens stay in memory and rotated refresh credentials are stored in Keychain, scoped to that origin.

## Production configuration (when ready)

1. Create a private R2 bucket and bucket-scoped S3 credentials. Set its name/binding and Cloudflare account in Wrangler. No public bucket custom domain is needed. Native URLSession uploads and top-level downloads do not require browser upload CORS; do not enable wildcard write access.
2. Create a Supabase project and apply the migration. All metadata tables have RLS enabled and no anon/authenticated grants. RPC EXECUTE is explicitly service_role-only. Do not expose the service_role JWT to a browser or app.
3. Enable email auth and production SMTP. Set Supabase's Site URL to the Worker origin and allow `https://YOUR_ORIGIN/auth/callback**` as a redirect. Set access-token lifetime to **900 seconds** and enable refresh-token rotation.
4. Enable Apple's provider in Supabase for web OAuth. Create an Apple Services ID associated with your app's primary App ID, verify the Supabase auth domain, and register `https://YOUR_PROJECT.supabase.co/auth/v1/callback` as Apple's return URL. Configure the Services ID and generated Apple client secret/private key in **Supabase's provider settings**, not in the app or repository. Rotate Apple's expiring client secret as required. The Mac uses `ASWebAuthenticationSession`, PKCE and a fixed `notchi://auth/callback` return scheme; this web OAuth flow does not require adding the native Sign in with Apple entitlement.
5. Set all Worker secrets, deploy using `npm run deploy`, and configure the HTTPS origin in the Mac's Links settings. Keep one signed build/copy registered for the URL scheme. A consistent Xcode Team/signing identity is recommended for Keychain access across updates.
6. The configured Cron runs every 10 minutes. Add R2 lifecycle rules as defense in depth: `staging/` expires after 1 day and `files/` after 8 days. The Worker also sweeps staging older than 45 minutes and final objects older than 8 days, including orphaned objects after account deletion.

No billing checkout/webhook is included. Paid entitlement is a server/admin-controlled record, ready to be driven by a billing webhook. To grant it manually with a trusted SQL/admin connection:

```sql
insert into public.link_accounts(id,tier) values ('AUTH_USER_UUID','paid')
on conflict(id) do update set tier='paid';
```

A client cannot set this tier through user metadata or public RPCs.

## API

All `/v1` file/metadata routes require a Supabase bearer access token. Auth exchanges and refreshes are rate limited and use Supabase's token endpoint. Every response is noncacheable. Errors contain stable codes only.

- `POST /v1/auth/apple` — `{ state, challenge }`, returns `authorizationURL`.
- `POST /v1/auth/email` — `{ email, state, challenge }`, sends the magic link.
- `GET /auth/callback` — forwards the one-use code/state to the fixed app URL scheme.
- `POST /v1/auth/exchange` — `{ code, verifier }`, returns short-lived access token, rotated refresh token, expiry and user UUID.
- `POST /v1/auth/refresh` — `{ refreshToken }`, rotates session credentials.
- `POST /v1/auth/logout` — bearer token; revokes the current Supabase session.
- `GET /v1/me` — user UUID, file/active-link limits and current reservation count.
- `POST /v1/uploads/init` — `{ filename, size, mime }`; reserves a slot transactionally and returns `fileId`, `uploadURL`, required PUT headers and deadline. PUT uses `application/octet-stream` and the signed exact Content-Length.
- `GET /v1/uploads/:id` — reissues a PUT capability for an owned, still-pending upload.
- `DELETE /v1/uploads/:id` — cancels an owned reservation; also revokes a concurrently completed share.
- `POST /v1/uploads/complete` — `{ fileId, expiry: "1h"|"24h"|"7d", password?, downloadLimit? }`; validates object size/magic, copies it to an immutable private key, and publishes once. Repeating completion returns the original active share, without extending it or creating another one.
- `GET /v1/links`, `DELETE /v1/links/:id` — list/revoke owned links.
- `GET /s/:slug` — public mobile download page. Filename is HTML-escaped; no third-party scripts/assets.
- `POST /s/:slug/download` — optional password form; redirects to a short-lived signed, one-use `/d/:ticket` URL. GET of that ticket atomically consumes a download allowance and streams private R2 bytes without buffering them in Worker memory. Replays and not-yet-started revoked/expired downloads are denied.
- `GET|POST /s/:slug/report` — reason-only abuse report, daily hashed reporter identity; retained for 30 days for operator review. Reports do not automatically disable a link, preventing report-based denial of service. An operator can set `revoked_at` on a reported share to take it down.

Limits are 100,000,000 bytes and 5 active links for free users. In-flight reservations count toward the limit, preventing concurrent-init bypass; they expire after 30 minutes. Upload capabilities last 15 minutes. Passwords are salted PBKDF2-SHA256 (100,000 iterations, Workers' supported maximum) plus an independent server-only pepper. Executable/script extensions, risky nested suffixes, MIME types and common executable magic are blocked. This is **basic abuse filtering**, not antivirus scanning or archive inspection.

Download limits count accepted one-use download requests, including transfers later interrupted by the network. A file already downloaded or a stream already started cannot be recalled. Expiry/revocation immediately blocks new authorizations; storage deletion follows Cron. Cleanup deletes both R2 keys before deleting metadata, so a storage failure leaves a record to retry. Exhausted links get a two-minute deletion grace period for the last stream.

## Logging

There is no application logger/HTTP logging middleware. No file bytes, passwords, tokens, filenames, share URLs or signed URLs are logged. Worker observability is disabled in configuration. Dev scripts use error-level Wrangler logging. If adding a proxy, analytics, tracing or log drain, explicitly disable request URL/query/body logging; signed URLs and auth callback URLs are bearer secrets. Supabase/provider/OS diagnostic logging is separately controlled by those services. Do not run verbose HTTP capture against real uploads.

## Tests

```sh
npm test
npm run check
npm run build
npm run test:db
# With local Supabase and the local Worker running:
npm run test:local
```

Tests cover exact expiry boundaries and prototype-key rejection, bounded signatures, password salts/pepper, filename/size restrictions, immutable R2 publication, HTTP ownership/auth, completion idempotency, one-use ticket replay, concurrency, revocation, empty PostgREST mutation responses and private same-origin browser forms. SQL tests use real Postgres to verify free/paid limits, RLS/RPC grants, ownership, exact expiry and an eight-way last-download race. `test:local` creates its own disposable local identity, uploads harmless bytes, checks password rejection, byte equality, immutable publication, one-use tickets and revocation, then revokes its links and deletes its test identity. Orphaned local R2 bytes follow the normal sweep. It refuses non-loopback Supabase configuration and never prints credentials, contents or addresses.

Verified on this Mac: native email/PKCE sign-in through the local inbox, a real background URLSession upload, automatic clipboard navigation to its public page and a browser download matching the original byte for byte. Browser testing found and fixed the `Origin: null` produced by `no-referrer` forms; it is accepted only with browser-attested `Sec-Fetch-Site: same-origin`. Foreign and unverified null origins remain blocked. Local HTTP emulates R2 signing; production R2 credentials and Apple OAuth still need their separate configuration and live verification.

For a live local check: start Supabase and the Worker, sign in by local email, add a small PDF to the shelf, choose **Get link**, upload, open the copied address in a browser, and download. Set a password and one-download limit; wrong passwords must fail and a second use of the ticket/link must fail. Revoke a link from My links and retry its public page. Quit/reopen during an upload/finalization to exercise the journal and URLSession reattachment. Test Apple sign-in after configuring real provider credentials.

References: [Cloudflare R2 presigned uploads](https://developers.cloudflare.com/r2/api/s3/presigned-urls/), [aws4fetch signing](https://developers.cloudflare.com/r2/examples/aws/aws4fetch/), [rate limiting](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/), [Supabase Apple auth](https://supabase.com/docs/guides/auth/social-sign-in/auth-apple), [PKCE flow](https://supabase.com/docs/guides/auth/sessions/pkce-flow).

The current CLI uses `[local_smtp]`; the configuration is pinned and tested with Supabase 3.0.0. `/local/preview` renders a layout-only sample page without a database file; its sample Download button is not a real share.
