---
title: "feat: App-side account login (magic-link sign-in)"
type: feat
date: 2026-07-11
origin: docs/brainstorms/2026-07-11-ambient-surrealism-app-improvements-requirements.md
---

# App-side account login (magic-link sign-in)

## Summary

Let a buyer unlock the Surrealism Mac app by signing in with their email — no pasted license key. The app runs a PKCE-protected magic-link flow: enter email → click the emailed link on the same Mac → the app exchanges a one-time code for the account's license key → the existing validate + device-activation flow runs unchanged. Pasting a key stays as a fallback. Work spans two repos: the app (`surrealism-application`) and the commerce backend (`surrealism-app-website`), which gains new app-facing auth endpoints.

**Target repos:** `surrealism-application` (this repo, the Mac app) and `surrealism-app-website` (the live Cloudflare Pages commerce backend). Backend units use paths relative to `surrealism-app-website/`; app units use paths relative to this repo.

---

## Problem Frame

Unlocking the app today means finding and pasting a `SURR-XXXX-XXXX-XXXX` key — the highest-friction step before we promote the product widely. Real accounts (magic-link email login) shipped on the web on 2026-07-10, but the app can't use them yet. This plan closes that gap: sign-in delivers the key the app already knows how to use, so the entire key/validate/device-cap/offline-grace machinery (just shipped and notarized) stays untouched.

Two findings from research shape the design and are settled below as decisions:

- **The account's key can't be read back.** The backend stores only a SHA-256 hash of each key; the plaintext is never persisted (`migrations/0001_init.sql`, `src/lib/commerce/keys.ts`). "Fetch the account's key" therefore requires a new mechanism, not a lookup.
- **A custom-scheme return only works on the same Mac.** `surrealism://` can only bounce back into the app if the magic link is opened on the machine running it.

---

## Requirements

### Sign-in and unlock

- R1. From the app, a user signs in with their email via magic link — no pasted key. (origin R1, F1)
- R2. After sign-in, the app obtains the account's license key and runs the existing validate + device-activation flow. `/v1/license/validate`'s request/response contract is unchanged. (origin R2)
- R3. Pasting a key remains supported as a fallback; the existing path is not removed. (origin R3)
- R4. Signed-in state survives relaunch (the key persists in the Keychain as today) and sign-out is offered. (origin R4)

### Security (from external research — RFC 8252 / PKCE)

- R5. The flow is PKCE-protected: the app generates and holds a `code_verifier`, sends only its SHA-256 `code_challenge` to start login, so a squatting app that intercepts the callback cannot complete the exchange.
- R6. The `surrealism://` callback URL carries only a single-use, short-lived authorization code plus a `state` value — never the license key, a bearer token, or any long-lived secret.
- R7. The license key is returned only in the TLS response body of the code→key exchange, over HTTPS.
- R8. License keys are stored recoverably-encrypted at rest going forward so the real key can be returned to the app; `/v1/license/validate`'s hash-based lookup is unchanged.

### No regression

- R9. No regression to what shipped, on the surfaces this plan touches: notarized build, un-sandboxed host app, `surrealism://` registration, `invalidKey`-vs-`network` error distinction, ≤3-device cap, 14-day offline grace. (the auth-relevant slice of origin R18; R18's branding/settings items — glossy orb, "Surrealism" naming, macOS-26 settings deep-link, iris fallback — are untouched by this plan and carry forward unchanged.)

---

## Key Technical Decisions

- KTD1. **Accounts deliver the key; they don't replace it.** Sign-in resolves to "obtain the key, then run the existing `LicenseStore.enter(key:)` path." Device activation, offline grace, and revocation stay unchanged. Lowest-risk integration. (origin decision)

- KTD2. **One-shot code→key exchange, no durable app session.** After the magic link returns, the app does a single PKCE exchange for the key and stops — it does not hold a refreshable session token. The existing license + device-activation layer already carries revocation/refunds (the periodic `revalidateIfNeeded` touchpoint returns revoked status), so a second session-token surface would add theft blast-radius and offline fragility without improving revocation. Resolves the origin's "durable session vs. one-shot" open question. (See Sources: RFC 8252, one-shot recommendation.)

- KTD3. **Recoverable-encrypted key storage; legacy hash-only licenses mint+rotate once.** On mint (Stripe webhook + rotate helper), store an AES-GCM-encrypted copy of the key alongside the existing hash, tagged with the `key_version` of the `KEY_ENCRYPTION_KEY` that encrypted it (so the KEK can be rotated — see U2). The exchange endpoint decrypts and returns the real key, so multi-device buyers keep one working key everywhere. `/v1/license/validate` still looks up by hash and is byte-for-byte unchanged. Pre-migration licenses have no ciphertext; on their first app sign-in the endpoint mints a fresh key and rotates the license to it (one-time). Rotation replaces `key_hash` + `key_ciphertext` on the same license row; device activations are scoped to the license (`activations.license_id`, confirmed in `db.ts`), not the key string, so a legacy rotation preserves the existing ≤3 activations rather than resetting the cap. Trade-off: keys become recoverable (encryption-protected) rather than mathematically irretrievable — a normal posture for a license credential, distinct from a password.

- KTD4. **Custom-scheme return + PKCE; same-Mac for v1.** The email link opens the browser, the backend redirects to `surrealism://auth/callback?code=…&state=…`, and the app's `.onOpenURL` handler picks it up. PKCE (KTD2/R5) is what makes the non-exclusive scheme safe. `ASWebAuthenticationSession` and loopback redirects were considered (see Alternatives) but the email hop breaks the same-session model and loopback adds a local-server dependency. Cross-device return (link opened on a phone) is out of v1.

- KTD5. **Host app stays un-sandboxed; no new entitlements.** The `surrealism://` scheme is already declared in the sealed `Info.plist` (added 2026-07-10) — this is handler code only, no manifest change, no re-notarization concern. Do not add App-Sandbox entitlements to the host: it is deliberately un-sandboxed, and adding them would break Keychain access and scheme handling. (origin R18; learnings finding #6)

- KTD6. **Reuse the existing Keychain license slot; persist only a short-TTL pending-auth record.** The fetched key is saved into the existing slot (service `app.surrealism.license`, account `licenseKey`, `kSecAttrAccessibleAfterFirstUnlock`) via `KeychainLicenseStore.save`. Because the flow is one-shot, no durable session token is stored. One durable item is required, though: the pending `{code_verifier, state, createdAt}` for the in-flight sign-in must survive an app quit/relaunch, because the magic link may be clicked after the app has closed — an in-memory-only verifier would strand the callback. Store it in a short-TTL sibling Keychain item (`account: pendingAuth`), cleared on completion or expiry. The signed-in email — non-secret, for display and sign-out — goes in UserDefaults, mirroring the existing secret-in-Keychain / metadata-in-UserDefaults split.

---

## High-Level Technical Design

The flow is a home-grown OAuth authorization-code flow for a native public client (RFC 8252). The app initiates and holds the PKCE secret; the browser only ever carries a single-use code.

```mermaid
sequenceDiagram
    participant App as Mac app
    participant API as surrealism.app (Cloudflare)
    participant Mail as Email
    participant Web as Browser (same Mac)

    App->>App: generate code_verifier + state<br/>code_challenge = SHA256(verifier)
    App->>API: POST /v1/auth/start { email, code_challenge, state }
    API->>API: mint app-purpose login token<br/>bound to code_challenge + state
    API->>Mail: email magic link (HTTPS /auth/verify?token=…)
    Note over App: app waits for surrealism:// callback
    Mail->>Web: user clicks link (on this Mac)
    Web->>API: GET /auth/verify?token=…
    API->>API: consume token (single-use);<br/>mint one-time code bound to challenge+state
    API->>Web: 302 → surrealism://auth/callback?code=…&state=…
    Web->>App: onOpenURL(surrealism://auth/callback…)
    App->>App: verify state matches
    App->>API: POST /v1/auth/exchange { code, code_verifier, state }
    API->>API: recompute SHA256(code_verifier) == code_challenge?<br/>code single-use + unexpired?
    API->>API: decrypt stored key (or mint+rotate if legacy)
    API-->>App: 200 { key }  (TLS body only)
    App->>App: KeychainLicenseStore.save(key)
    App->>API: existing POST /v1/license/validate { key, deviceId }
    API-->>App: { valid, activation, tier, packs, … }  (unchanged)
    App->>App: LicenseStore → .unlocked / .deviceLimit
```

Directional guidance, not implementation specification. The exact token/code storage shape (whether the PKCE challenge lives on `login_tokens` or a new `app_auth_codes` table) is a U1 decision.

---

## Implementation Units

Phase A lands in `surrealism-app-website`; Phase B in `surrealism-application`. Phase B's exchange service (U7) depends on the backend exchange endpoint (U5) existing, but the app UI/plumbing (U6, U8, U9) can proceed against a stubbed endpoint.

### Phase A — Backend (`surrealism-app-website`)

### U1. Migration: app-auth codes + PKCE binding + encrypted-key column

- Goal: Add the D1 schema the app-auth flow needs: PKCE-bound app login tokens / one-time codes, and a recoverable-encrypted key column on `licenses`.
- Requirements: R5, R6, R8
- Dependencies: none
- Files: `migrations/0004_app_auth.sql` (new); reference `migrations/0001_init.sql`, `migrations/0003_accounts.sql`
- Approach: Add `licenses.key_ciphertext TEXT` (nullable — null means legacy hash-only) and `licenses.key_version INTEGER` (which `KEY_ENCRYPTION_KEY` version encrypted the row, for rotation — see U2). Add PKCE + one-time-code support via a dedicated `app_auth_codes` table (`code_hash`, `account_id`, `code_challenge`, `state`, `expires_at`, `consumed_at`) rather than extending `login_tokens`: the one-time authorization code (minted at verify, consumed at exchange) is a distinct single-use artifact from the login token (minted at start, consumed at verify), and — decisively — `login_tokens` carries `CHECK (purpose IN ('login','email_change'))`, which SQLite/D1 cannot ALTER in place, so reusing it would force a full table rebuild. The app-login *token* itself still needs its PKCE challenge+state bound to it; add `code_challenge`/`state` columns to `login_tokens` (nullable, no CHECK change) or a sibling `app_login_tokens` table. Follow the existing hash-only, single-use, TTL conventions from `login_tokens` in `0003_accounts.sql`.
- Patterns to follow: `migrations/0003_accounts.sql` (token table shape, indexes, `consumed_at` single-use guard).
- Test scenarios: Test expectation: none — schema migration; behavior is covered by U2–U5. Verify the migration applies cleanly against a copy of the current schema.
- Verification: `wrangler d1 migrations apply` succeeds locally; new columns/tables present; existing rows unaffected (`key_ciphertext` null for existing licenses).

### U2. Recoverable-encrypted key storage

- Goal: Encrypt and store the plaintext key at mint time so it can be returned later; provide a decrypt helper. `/v1/license/validate` stays untouched.
- Requirements: R8, R2
- Dependencies: U1
- Files: `src/lib/commerce/keys.ts` (add encrypt/decrypt), `src/lib/commerce/keycrypto.ts` (new — AES-GCM encrypt/decrypt), `src/lib/commerce/db.ts` (extend the write path — see below), `src/pages/api/stripe-webhook.ts` (store ciphertext on mint + on `rotateKeyIfUnsent`), `src/lib/commerce/env.ts` (surface the new encryption-key secret), `test/keycrypto.test.ts` (new)
- Approach: AES-GCM encryption with a **versioned** Workers secret (`KEY_ENCRYPTION_KEY` + `KEY_ENCRYPTION_KEY_VERSION`), using the Workers `SubtleCrypto` already in use for Stripe. Each row stores `key_ciphertext` + `key_version`; `decryptKey` looks up the KEK for the row's version, so a rotated KEK can decrypt old rows while new/rotated writes use the current version (re-encrypting lazily on next write). This makes the rotation mitigation in Risks actually mechanized rather than requiring an ad-hoc bulk re-encrypt. The write path lives in `db.ts`, not the webhook: extend `CreateLicenseParams` with `keyCiphertext`/`keyVersion` and add those columns to the `createLicense` INSERT, and add ciphertext/version params to `rotateKeyIfUnsent`'s UPDATE — the webhook passes the encrypted values through. On mint, write both `key_hash` (existing) and `key_ciphertext`; the plaintext still leaves the system only via the existing one-time purchase email. Do not alter `hashKey`/`getLicenseByKeyHash` — the validate lookup path is unchanged.
- Patterns to follow: `Stripe.createSubtleCryptoProvider()` usage in `stripe-webhook.ts`; `createLicense`/`rotateKeyIfUnsent` in `db.ts`; secret access via `readEnv(locals)` in `env.ts`.
- Test scenarios:
  - Happy path: encrypt then decrypt round-trips to the original key string.
  - Edge: decrypt of a value encrypted with a different key fails cleanly (no plaintext leak, typed error).
  - Edge: unique IV/nonce per encryption — two encryptions of the same key produce different ciphertext.
  - Rotation: a row written under version N still decrypts after the current version advances to N+1; a subsequent write stores version N+1.
  - Integration: webhook mint path writes `key_hash`, `key_ciphertext`, and `key_version` via `createLicense`; `rotateKeyIfUnsent` updates all three.
  - Failure: missing `KEY_ENCRYPTION_KEY` secret surfaces a typed error at mint, not a silent null ciphertext.
- Verification: A newly minted license has non-null `key_ciphertext` that decrypts to the emailed key; validate still succeeds against that key unchanged.

### U3. App login-start endpoint

- Goal: Accept an app-initiated, PKCE-challenged login request and email the magic link.
- Requirements: R1, R5
- Dependencies: U1
- Files: `src/pages/v1/auth/start.ts` (new), `src/lib/commerce/auth.ts` (extend token mint with challenge binding), `test/app-auth-start.test.ts` (new)
- Approach: `POST /v1/auth/start` accepts `{ email, code_challenge, code_challenge_method: "S256", state }`. Mint a login token bound to `code_challenge` + `state` (per U1's storage choice — the presence of a bound challenge marks it an app login, so no new `purpose` enum value is needed and the `CHECK` constraint is untouched), then email `${PUBLIC_SITE_URL}/auth/verify?token=<raw>`. Reuse the enumeration-safe, rate-limited, neutral-response pattern from `src/pages/auth/login.ts`. Reject a missing/short/malformed `code_challenge` (require S256).
- Patterns to follow: `src/pages/auth/login.ts` (enumeration resistance, `rateLimit`, `renderLoginEmail`), pure `handleX` + thin wrapper, `{error:'snake_case'}` shape from `src/lib/commerce/http.ts`.
- Test scenarios:
  - Happy path: valid `{email, code_challenge, state}` for a known account mints a token bound to the challenge and sends the login email.
  - Edge: unknown email returns the same neutral response (no account enumeration) and sends no email.
  - Edge/error: missing or non-S256 `code_challenge` → `400 {error:'invalid_challenge'}`.
  - Error: per-email and per-IP rate limits return `429` with `Retry-After`.
  - Covers F1. The link points at HTTPS `/auth/verify`, never at `surrealism://` directly.
- Verification: Calling start emails a working magic link; the minted token carries the challenge+state.

### U4. Verify branch: mint one-time code, redirect to `surrealism://`

- Goal: When the magic link belongs to an app login, mint a one-time authorization code and redirect into the app instead of setting a browser session cookie.
- Requirements: R6
- Dependencies: U1, U3
- Files: `src/pages/auth/verify.ts` (add app-purpose branch), `src/lib/commerce/auth.ts` (mint one-time code), `test/app-auth-verify.test.ts` (new)
- Approach: In `/auth/verify`, after `consumeToken`, branch on whether the token is an app login (it carries a bound `code_challenge`, per U1). For app logins: mint a one-time, short-lived (30–60s) authorization code in `app_auth_codes` bound to the token's `code_challenge` + `state`, then `302` to `surrealism://auth/callback?code=<raw>&state=<state>`. The code is single-use and carries no secret. The existing browser cookie/`/account` redirect path for normal web logins is unchanged.
- Patterns to follow: existing `consumeToken` + branch handling in `verify.ts` (it already handles `email_change`); single-use/TTL token mechanics in `auth.ts`.
- Test scenarios:
  - Happy path: consuming an `app_login` token mints a code bound to the same challenge+state and redirects to `surrealism://auth/callback?code=…&state=…`.
  - Edge: normal web-login tokens still set the session cookie and redirect to `/account` (no regression).
  - Edge: expired or already-consumed token → the existing invalid-link response, no code minted.
  - Security: the redirect URL contains only `code` + `state`, never a key or session token.
- Verification: Clicking an app-login link redirects to the custom scheme with a single-use code; clicking twice fails the second time.

### U5. Exchange endpoint: code + verifier → key

- Goal: Validate the PKCE exchange and return the account's license key over TLS.
- Requirements: R2, R5, R7, R8
- Dependencies: U1, U2, U4
- Files: `src/pages/v1/auth/exchange.ts` (new), `src/lib/commerce/auth.ts` (consume code + PKCE verify), `src/lib/commerce/db.ts` (select the account's license; new unconditional rotate helper — see below), `test/app-auth-exchange.test.ts` (new)
- Approach: `POST /v1/auth/exchange` accepts `{ code, code_verifier, state }`. Consume the code atomically (single-use, unexpired), recompute `SHA256(code_verifier)` and compare to the stored `code_challenge`, verify `state`. On success, select the account's license via a defined rule: **the most-recently-created license whose status is active** (not refunded/revoked/disabled); zero → `{error:'no_license'}`. Then:
  - **Recoverable:** if `key_ciphertext` is present, `decryptKey` and return it.
  - **Legacy (null ciphertext):** mint a fresh key and rotate the license to it as a **single conditional write** — `UPDATE … SET key_hash=?, key_ciphertext=?, key_version=? WHERE id=? AND key_ciphertext IS NULL`. If the UPDATE matches **zero rows**, a concurrent sign-in already rotated it; fall through to re-read the row and return the now-present decrypted key. This keeps two near-simultaneous legacy sign-ins from minting divergent keys and handing one device a dead key.
  - Do **not** reuse `rotateKeyIfUnsent` here — its `WHERE … AND email_sent = 0` guard matches zero rows for legacy licenses (all already emailed), so it would silently fail to persist the new hash. Add a dedicated `rotateKeyForAccount(db, licenseId, newKeyHash, newCiphertext, keyVersion)` with the conditional-on-null write above.

  Return `{ key }` in the TLS body only. Redact `key`, `code`, and `code_verifier` from any request/response logging or error reporting. Rate-limit per IP. Never touch `/v1/license/validate`.
- Patterns to follow: `requireAccount`/`getAccountLicenses` conventions in `session-guard.ts`/`db.ts`; `generateKey`/`hashKey` in `keys.ts`; `rateLimit`; `{error:'snake_case'}`.
- Test scenarios:
  - Happy path (recoverable): valid code+verifier for an account with `key_ciphertext` returns the decrypted real key.
  - Happy path (legacy): account with null `key_ciphertext` gets a freshly minted key; its hash+ciphertext+version are stored and the license is rotated; the returned key validates.
  - Concurrency (legacy): two exchanges racing on the same null-ciphertext license both return the **same** key — the loser's conditional UPDATE matches zero rows and it re-reads the winner's key.
  - Multi-license: an account with two active licenses returns the most-recently-created one; an account with one active + one refunded returns the active one (never the refunded).
  - Security: wrong `code_verifier` (challenge mismatch) → `400 {error:'invalid_grant'}`, no key returned.
  - Security: reused code (already consumed) → rejected; expired code → rejected.
  - Security: `state` mismatch → rejected.
  - Edge: account with no active license → `{error:'no_license'}`.
  - Error: per-IP rate limit → `429`.
  - Integration: the returned key succeeds against the unchanged `/v1/license/validate` with a `deviceId`.
- Verification: A full start→verify→exchange run returns a key that unlocks via the existing validate flow; PKCE and single-use guards reject tampered requests.

### Phase B — App (`surrealism-application`)

### U6. Wire the unit-test target + PKCE helper

- Goal: Make the existing (currently unwired) tests runnable and add a PKCE helper the auth flow needs.
- Requirements: R5
- Dependencies: none
- Files: `AppexSaverMinimal.xcodeproj/project.pbxproj` (add `AppexSaverMinimalTests` target hosted by the host app), `AppexSaverMinimal/Commerce/PKCE.swift` (new), `AppexSaverMinimal/Commerce/PKCETests.swift` (new); reference `AppexSaverMinimal/Commerce/LicenseStoreTests.swift`
- Approach: Create the unit-test bundle described in `LicenseStoreTests.swift`'s header so `@testable import AppexSaverMinimal` compiles and existing fakes run. Add `PKCE` — generate a high-entropy `code_verifier`, derive `code_challenge = base64url(SHA256(verifier))`, and a `state` nonce. Auth code (host-app-only) must not be added to the extension target.
- Patterns to follow: DI/fakes pattern in `LicenseStoreTests.swift`; `CryptoKit` for SHA-256.
- Test scenarios:
  - Happy path: `code_challenge` equals base64url(SHA256(verifier)) for known vectors.
  - Edge: verifier and state are high-entropy and differ across calls.
  - Test expectation for the target-wiring itself: none — scaffolding; success is that `LicenseStoreTests` now compile and run.
- Verification: `xcodebuild test` runs the existing + new tests green.

### U7. Auth service in `CommerceAPI`

- Goal: Add the app's client for start + exchange, keeping every secret out of the URL.
- Requirements: R1, R2, R7
- Dependencies: U5 (contract), U6
- Files: `AppexSaverMinimal/Commerce/CommerceAPI.swift` (add an `AccountAuthenticating` protocol + `LiveAccountAuth` struct), `AppexSaverMinimal/Commerce/CommerceAPITests.swift` (new or extend)
- Approach: Mirror the existing protocol + `Live…` struct pattern. `startLogin(email:challenge:state:)` → `POST /v1/auth/start`. `exchange(code:verifier:state:)` → `POST /v1/auth/exchange` returning the key from the TLS body. Base URL `https://surrealism.app`. Key/verifier travel in the JSON body, never the URL. Map failures to a typed error that distinguishes expired-link/invalid-grant from network-unreachable (feeds R9's `invalidKey`-vs-`network` distinction).
- Patterns to follow: `LiveLicenseValidator` in `CommerceAPI.swift` (URLSession + async/await, `CommerceError`, timeout, body-not-URL convention line ~89).
- Test scenarios:
  - Happy path: exchange returns a key; start returns success.
  - Failure: `invalid_grant`/expired code maps to an auth-failure error (not `.network`).
  - Failure: network error / non-2xx maps to `.network`, never to a fake-credential state.
  - Security: assert the request carries `code`/`verifier` in the body, not the URL.
- Verification: Against a stub backend, start+exchange returns a key and errors map correctly.

### U8. `surrealism://` receiver + routing

- Goal: Receive the magic-link callback and route it into the auth flow.
- Requirements: R1, R6, R5
- Dependencies: U6
- Files: `AppexSaverMinimal/AppexSaverMinimalApp.swift` (add `.onOpenURL` on the primary `WindowGroup`, or an `NSApplicationDelegateAdaptor`), `AppexSaverMinimal/Commerce/AuthCallbackRouter.swift` (new — parse/validate the callback), `AppexSaverMinimal/Commerce/AuthCallbackRouterTests.swift` (new)
- Approach: Handle `surrealism://auth/callback?code=…&state=…`. Load the pending `{code_verifier, state, createdAt}` from the short-TTL Keychain record (KTD6) — which survives an app relaunch, so a link clicked after the app was quit still completes. Require the callback `state` to match the pending record (reject otherwise), extract the single-use code, and hand it to the sign-in entry point (U9). When there is **no pending record or it has expired** (link clicked too late, or on a machine that never initiated), do not silently drop it — route to a "sign-in link expired — request a new one" state in `LicenseStore` (U9). Ignore genuinely malformed or non-auth URLs safely. No Info.plist change — the scheme is already registered. Test the deep link against a single final-location signed build to avoid the LaunchServices stale-copy gotcha.
- Patterns to follow: SwiftUI `.onOpenURL`; `LicenseStore` as the state owner it routes into.
- Test scenarios:
  - Happy path: a well-formed callback with a matching `state` yields the code and triggers exchange.
  - Security: mismatched `state` is rejected (no exchange attempted).
  - Edge: malformed URL, wrong host/path, or missing `code` is ignored without crashing.
  - Edge: a callback arriving with no pending record (or an expired one) routes to the "link expired — request a new one" state, not a silent drop.
  - Relaunch: pending record persisted before quit is loaded on relaunch and the callback completes.
- Verification: Opening a crafted `surrealism://auth/callback` URL against a signed build drives the exchange; a mismatched-state URL does not.

### U9. Sign-in UI + `LicenseStore` sign-in entry

- Goal: Add the "Sign in with email" affordance and wire the completed exchange into the existing unlock path.
- Requirements: R1, R2, R3, R4, R9
- Dependencies: U7, U8
- Files: `AppexSaverMinimal/Commerce/LicenseView.swift` (add sign-in UI beside the key field), `AppexSaverMinimal/Commerce/LicenseStore.swift` (add `signIn(email:)` start + a callback completion that saves the key and runs `enter`/`revalidateIfNeeded`; extend `signOut` to clear the stored email), `AppexSaverMinimal/ContentView.swift` (shared brand components only), `AppexSaverMinimal/Commerce/LicenseStoreTests.swift` (extend)
- Approach: Add an email field + "Send sign-in link" button (clean white `PrimaryButtonStyle` — no rainbow) alongside the existing key `TextField`, keeping the paste path (R3). `signIn(email:)` generates PKCE (U6), persists the pending `{code_verifier, state, createdAt}` to the short-TTL Keychain record (KTD6), calls `startLogin` (U7), and shows a "check your email — open the link on this Mac" state. On callback (U8), the store saves the returned key via `KeychainLicenseStore.save`, clears the pending record, and runs the existing `enter`-equivalent validate/activate path — so `device_limit`, offline grace, and revocation all behave as today. Add two new terminal states: `noLicense` (exchange returned `no_license` — authenticated but this account owns no active license; message points to purchase/support) and `linkExpired` (no/expired pending record on callback, or an expired-link exchange failure; message offers "request a new link"). Persist the signed-in email in UserDefaults for the unlocked panel's "Signed in as …" display; `signOut` clears key + email. Preserve the `invalidKey`(expired-link)-vs-`network`(unreachable) distinction.
- Patterns to follow: `LicenseView.entry`/`submit`/state-switch and `unlocked(tier:)` sign-out button; `LicenseStore.enter`/`revalidateIfNeeded`/`signOut`; `DeviceID.current` for activation.
- Test scenarios:
  - Happy path: a completed exchange saves the key, transitions the store to `.unlocked`, and shows the signed-in email.
  - Happy path: sign-out clears the Keychain key and the stored email and returns to `.locked`.
  - Edge: `device_limit` from validate surfaces the existing `.deviceLimit` state (key still saved).
  - Edge: `no_license` from exchange shows the "signed in, no active license" state (not "invalid key", not "network").
  - Edge: expired-link exchange failure or an expired/absent pending record shows the "link expired — request a new one" state (not "invalid key", not "network").
  - Error: network failure during start/exchange shows a network message and does not lock out an existing valid key.
  - Regression: the paste-a-key path still validates and unlocks unchanged (R3).
  - Persistence: after relaunch, a signed-in user stays unlocked (key in Keychain) and the email still displays (R4).
- Verification: End-to-end on a signed build — email → link on this Mac → app unlocks with no key typed; relaunch stays unlocked; sign-out clears state; paste fallback still works.

---

## Acceptance Examples

- AE1. **Happy sign-in.** Given a buyer with an active license, when they enter their email in the app, click the link on the same Mac, then the app exchanges the code and unlocks — no key typed. (R1, R2; Covers F1)
- AE2. **Legacy key.** Given a license minted before this feature (hash-only, no ciphertext), when the user signs into the app for the first time, then the exchange mints a fresh key, rotates the license, and unlocks. (R8, KTD3)
- AE3. **Intercepted callback.** Given a malicious app also registered `surrealism://` and grabs the callback code, when it tries to exchange without the app's `code_verifier`, then the exchange returns `invalid_grant` and no key is released. (R5, R6)
- AE4. **Device limit.** Given the account already has 3 activated devices, when a 4th signs in, then the app surfaces the existing `device_limit` state and points to the web "free a slot" flow. (R9)
- AE5. **Expired link.** Given the user clicks the magic link after it expires, when verify runs, then the existing invalid-link response shows and no code is minted; the app shows an expired-link (not invalid-key) message. (R9)

---

## Alternatives Considered

- **Durable, refreshable app session token.** Rejected (KTD2). Adds a second revocation surface that does the same job as the existing periodic validate less well, is worse for offline use, and has a larger theft blast radius than a seat-bounded license key. Revisit only if the app gains account-level features (in-app device management, multiple products).
- **Rotate the key on every app sign-in** (no storage change). Rejected (KTD3). Minting a new key each sign-in invalidates any previously-saved/emailed key, breaking other already-activated devices on their next revalidation — a real regression for 2–3-device buyers.
- **Re-send the key by email instead of returning it in-app.** Rejected. Still requires rotation (plaintext is gone) and reintroduces the copy-a-key friction R1 exists to remove.
- **`ASWebAuthenticationSession` or loopback (`127.0.0.1`) return.** Considered; both are stronger than a raw custom scheme in general. Deferred: the classic "click the link in your email later" hop happens in a separate browser context, so it may not return through the same auth session; loopback adds a local-HTTP-server dependency. PKCE makes the custom-scheme return safe for v1 (KTD4).
- **Cross-device return via polling (device-authorization-grant style, RFC 8628).** Deferred to follow-up (see Scope Boundaries). Would let the link be clicked on any device but adds backend pending-auth state and an app polling loop.

---

## Scope Boundaries

### In scope
App-side magic-link sign-in (R1–R4), the new PKCE-protected `start`/`verify`-branch/`exchange` endpoints, recoverable-encrypted key storage with a legacy mint-and-rotate fallback, and the security posture in R5–R8. Pasting a key stays.

### Deferred to follow-up work
- Cross-device link return (polling / device-authorization grant) — v1 is same-Mac.
- Showing the license key in the web account dashboard (an existing gap — the dashboard copy promises it but doesn't render it); this feature makes keys recoverable, so it could be revisited later.
- Proactively backfilling `key_ciphertext` for all legacy licenses (v1 rotates lazily on first app sign-in).

### Outside this pass (separate plans)
- Playback controls, in-app theater, and desktop wallpaper mode — the other three features in the origin requirements doc, each to be planned separately.

---

## Risks & Dependencies

- **Live purchase path change (U2).** Adding ciphertext storage touches `stripe-webhook.ts`, the fulfillment path. Mitigation: the change is additive (new column written alongside the existing hash), the plaintext-email path is unchanged, and the webhook mint/rotate paths get explicit tests before ship.
- **Encryption-key management.** `KEY_ENCRYPTION_KEY` becomes a load-bearing secret; if it and the D1 data both leak, keys are exposed. Mitigation: store as a Workers secret (`wrangler pages secret put`), never in `wrangler.toml`; the `key_version` column (U1/U2) makes rotation real — a new KEK version decrypts old rows and re-encrypts lazily on next write, so a suspected leak doesn't force an ad-hoc bulk re-encrypt under incident pressure.
- **Legacy rotate-on-first-fetch.** For a pre-migration license used on multiple devices, the first app sign-in rotates the key and the old key stops validating on the other devices. Mitigation: acceptable and bounded to legacy licenses; the user is signing in fresh anyway; document the behavior. Signing in on each device re-activates it.
- **LaunchServices stale-copy / scheme squatting.** A deep link can open a stale build; and because `surrealism://` is not exclusive, a malicious app that also registers it could swallow the callback code. PKCE prevents that app from completing the exchange (no verifier), but the legitimate sign-in fails until retried — a mild DoS, not a key-theft path. Mitigation: test `surrealism://` against a single, final-location signed copy (learnings finding #6); surface the `linkExpired` retry state (U9) so a swallowed callback is recoverable.
- **Email-account trust.** Magic-link sign-in ties app unlock to email-account security: anyone who can read or forward the victim's email can complete their own PKCE flow and obtain the key. This is the standard magic-link trade-off (the paste path has the same key-possession exposure) and bounded by the ≤3-device cap; named here as an accepted residual risk.
- **Schema drift.** The parent accounts plan predates the 2026-07-10 ship by a day. Before U1, verify the shipped `sessions`/`login_tokens` schema and confirm no app-facing endpoint already exists.
- **Dependencies:** the live accounts backend (magic-link primitives in `auth.ts`, Cloudflare D1); the `surrealism://` scheme already registered in the app's sealed `Info.plist`; `/v1/license/validate` unchanged and downstream of the new exchange.

---

## Operational Notes

- New Workers secret `KEY_ENCRYPTION_KEY` must be set in production before U2 ships (`wrangler pages secret put`).
- No `docs/solutions/` learnings tree exists in either repo yet; this is the first app-side auth work — capture the flow with `/ce-compound` after it lands.
- Stale docs to ignore while working in the backend: `README.md` and `netlify.toml` describe a Netlify setup; the live deploy is Cloudflare Pages (`@astrojs/cloudflare`, `wrangler.toml`).

---

## Sources / Research

- Origin requirements: `docs/brainstorms/2026-07-11-ambient-surrealism-app-improvements-requirements.md` (R1–R4, F1, the three decided approaches, the durable-session open question).
- Parent accounts plan (backend token/session mechanics, the deferred app-login open question): `surrealism-app-website/docs/plans/2026-07-09-001-feat-accounts-magic-link-plan.md`.
- App integration seams: `AppexSaverMinimal/Commerce/LicenseStore.swift` (`enter`/`revalidateIfNeeded`/`signOut`, `EntryError` split), `Keychain.swift` (`KeychainLicenseStore`), `CommerceAPI.swift` (`LiveLicenseValidator`, body-not-URL convention), `DeviceID.swift`, `LicenseView.swift`, `AppexSaverMinimalApp.swift` (no `onOpenURL` yet), `Info.plist` (`surrealism` scheme registered).
- Backend seams: `src/lib/commerce/auth.ts` (`mintLoginToken`/`consumeToken`/`createSession`), `src/pages/auth/login.ts` + `verify.ts` (magic-link flow), `src/lib/commerce/keys.ts` (hash-only key storage), `src/pages/v1/license/validate.ts` (unchanged contract), `src/pages/api/stripe-webhook.ts` (key mint), `src/lib/commerce/session-guard.ts`, `db.ts` (`getAccountLicenses`), `email.ts` (Cloudflare Email Sending).
- External (security posture — RFC 8252 / PKCE): [RFC 8252 OAuth for Native Apps](https://datatracker.ietf.org/doc/html/rfc8252) (§7.3 redirect types, §8.6 interception), [RFC 7636 PKCE](https://datatracker.ietf.org/doc/html/rfc7636), [Stytch: PKCE for magic links](https://stytch.com/docs/consumer-auth/authentication/magic-links/adding-pkce), [Apple: kSecAttrAccessible](https://developer.apple.com/documentation/security/ksecattraccessible/), [oauth.net native apps](https://oauth.net/2/native-apps/). Load-bearing: shaped KTD2 (one-shot over durable session), KTD4 (custom-scheme + PKCE), R5–R7.
