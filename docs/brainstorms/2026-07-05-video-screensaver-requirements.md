---
date: 2026-07-05
topic: video-screensaver
---

# Video Screensaver — Requirements

## Summary

Turn the AppexSaverMinimal template into a macOS video screensaver that plays surrealist loops from surrealism.tv / surrealism.ai, sold direct as a notarized download. The app installs free with a couple of bundled sample loops that play immediately and offline. Paying unlocks a browsable catalog of the full library, which downloads from Cloudflare R2 to a local cache and plays offline. The host app becomes the storefront, downloader, and library manager; the extension swaps its rainbow animation for a looping video player. The project also includes a net-new backend that handles Stripe checkout, license-key issuance and delivery, and gated serving of the R2 manifest and signed URLs.

## Problem Frame

The current repo is the unmodified AerialScreensaver template — a `.appex` screensaver that renders a six-color rainbow via `CABasicAnimation` (`AppexSaverMinimal/RainbowAnimator.swift`). Jay already produces surrealist video and hosts/streams it from R2 for surrealism.tv and surrealism.ai. There is no way today to bring that library to the Mac screensaver surface, and it is a natural paid product: people who like the videos on the web would keep them running on their desktop. The value is a beautiful, always-fresh screensaver of Jay's content that is cheap to distribute (small app, videos pulled on demand) and easy to keep current (add videos server-side, no app update).

## Key Decisions

- **Download-and-cache, not streaming.** The extension only ever plays local files. Videos download once from R2 via the host app and play from cache, so the screensaver runs with no network dependency and the library updates without shipping app updates.
- **Direct sale, not the App Store.** Distributed as a notarized, signed download from surrealism.tv. This buys full entitlement freedom (auto-activate the screensaver via PaperSaver, download videos freely) at the cost of running licensing and notarization ourselves. The host app stays unsandboxed (verified: `AppexSaverMinimal/AppexSaverMinimal.entitlements` is empty).
- **Server-gated licensing, not local crypto.** The app is free to install; the backend serves the video manifest and signed R2 URLs only to a valid license key. Enforcement lives server-side rather than in fragile client-side license validation.
- **Net-new backend, Stripe / self-hosted licensing.** The key-validation + manifest + signed-URL backend does not exist yet and is built as part of this project. Payments run through Stripe (not a merchant-of-record), so the backend also generates license keys, delivers them to buyers, and we own tax/VAT compliance — chosen for lowest fees and full control over the lowest-friction alternatives (Lemon Squeezy / Gumroad / Paddle).
- **Free tier ships bundled samples.** 1–2 small sample loops are bundled inside the app (not downloaded) so a free user with no key and no network still sees it working the moment they install.
- **Curated catalog picker, not auto-download-all or packs.** After unlock the user browses the library and chooses which loops to keep locally. This controls disk use and doubles as a branded gallery. Auto-download-all and themed paid packs were considered and set aside (packs may return later as an upsell).
- **Shared cache via an App Group.** The extension is sandboxed (verified: `AppexSaverMinimalExtension/AppexSaverMinimalExtension.entitlements`) and declares no App Group today. Downloaded videos must live in a shared container both the unsandboxed host app and the sandboxed extension can read, which requires adding an App Group to both targets.
- **Consumer-grade protection, no DRM.** Once unlocked, cached MP4s sit on disk in the clear and a technical user could copy them out. Accepted as good-enough for this product; no encryption or hard copy-protection.

## Actors

- A1. **Viewer** — installs the app, may buy a license, picks videos, watches the screensaver.
- A2. **Host app** — storefront/unlock UI, catalog browser, download + cache manager, screensaver installer/activator, in-app preview.
- A3. **Screensaver extension** — sandboxed process that loops cached videos when the screensaver is active.
- A4. **surrealism.tv backend + R2** (net-new, built here) — takes Stripe payments, issues and delivers license keys, validates keys, serves the video manifest and signed download URLs, hosts the MP4s.

## Key Flows

- F1. First run (free)
  - **Trigger:** Viewer installs and opens the host app with no license.
  - **Steps:** Host app can install/activate the screensaver via the existing pluginkit + PaperSaver flow; the screensaver plays the bundled sample loop(s) immediately, offline.
  - **Outcome:** A working, free screensaver that showcases the product.
  - **Covers R1, R4, R5, R6.**

- F2. Purchase and unlock
  - **Trigger:** Viewer buys a license on surrealism.tv and receives a key.
  - **Steps:** Viewer enters the key in the host app; the backend validates it and returns the catalog manifest; unlock state persists locally.
  - **Outcome:** Full catalog becomes browsable; key is entered once.
  - **Covers R7, R8, R9.**

- F3. Build the library
  - **Trigger:** Unlocked viewer opens the catalog.
  - **Steps:** Viewer browses loops with thumbnails, selects some, and they download from R2 to the shared cache; viewer can remove loops and see disk usage.
  - **Outcome:** A local set of chosen loops ready for playback; catalog reflects new server-side additions.
  - **Covers R10, R11, R12, R13.**

- F4. Screensaver playback
  - **Trigger:** macOS activates the screensaver.
  - **Steps:** The extension reads the shared cache and loops the selected videos across all displays, muted; if the cache is empty it plays the bundled samples.
  - **Outcome:** Seamless, offline video screensaver.
  - **Covers R1, R2, R3, R4.**

## Requirements

**Playback (extension)**

- R1. The extension plays MP4 loops from the shared local cache, cycling through the viewer's selected videos.
- R2. Playback loops seamlessly and runs muted by default.
- R3. Playback covers all connected displays while the screensaver is active.
- R4. When the cache holds no downloaded videos, the extension falls back to the bundled sample loop(s).

**Free tier and activation**

- R5. The app installs and runs free, with 1–2 sample loops bundled in the app so it works immediately and offline with no key.
- R6. The host app installs and activates the screensaver through the existing pluginkit registration + PaperSaver activation flow.

**Purchase and unlock**

- R7. The viewer purchases a license on surrealism.tv and receives a license key.
- R8. Entering a valid key unlocks the full library; the backend serves the catalog manifest and signed R2 URLs only to valid keys.
- R9. Unlock state persists across launches so the key is entered only once.

**Library and downloads (host app)**

- R10. After unlock, the host app shows a catalog of the full library with thumbnails.
- R11. The viewer selects which loops to download; selected loops download from R2 into the shared cache.
- R12. The viewer can remove downloaded loops and see how much disk the cache is using.
- R13. Downloads run without blocking the UI and survive interruption (resume or retry rather than corrupt the cache).
- R14. The catalog reflects videos added server-side without requiring an app update.

**Backend (net-new)**

- R15. On a successful Stripe payment, the backend generates a license key and delivers it to the buyer (e.g., by email).
- R16. The backend exposes an endpoint that validates a submitted key and returns the catalog manifest plus signed, time-limited R2 URLs.
- R17. The catalog manifest is editable server-side so new videos appear in the app without a release (supports R14).

**Distribution**

- R18. The app ships as a notarized, code-signed direct download (DMG or ZIP) from surrealism.tv, not the Mac App Store.

## Acceptance Examples

- AE1. **Covers R4.** Given a fresh free install with no key and no downloads, when the screensaver activates, then the bundled sample loop plays.
- AE2. **Covers R8.** Given an invalid or empty license key, when the viewer submits it, then the library stays locked and the failure is shown clearly.
- AE3. **Covers R1, R4.** Given an unlocked viewer who has not finished downloading any catalog videos, when the screensaver activates, then it plays the bundled samples until at least one selected video is cached.
- AE4. **Covers R1.** Given selected videos already cached, when the machine is offline and the screensaver activates, then playback proceeds normally from the cache.

## Scope Boundaries

**Deferred for later**

- Themed paid "packs" and other upsells beyond the base unlock.
- An auto-download-all mode as an alternative to the catalog picker.
- Free-trial timers or time-limited unlocks.

**Outside this product's identity**

- Live streaming / on-the-fly network playback in the screensaver.
- Mac App Store distribution.
- Hard DRM or at-rest encryption of cached videos.

## Dependencies / Assumptions

- **Backend is a second deliverable.** The key-validation + manifest + signed-URL + Stripe-checkout backend is net-new and likely lives outside this Xcode repo; planning covers two deliverables (Mac app + backend).
- **Tax/VAT is our responsibility.** Consequence of Stripe over a merchant-of-record; a compliance obligation, not app behavior.
- **App Group + Developer team.** A shared App Group container must be added to both targets; requires the `DEVELOPMENT_TEAM` currently empty in `AppexSaverMinimal.xcodeproj` to be set.
- **Entitlements delta.** Host app is unsandboxed today, so network access for downloads is free; if it is ever sandboxed, it will need `com.apple.security.network.client`. The extension stays sandboxed and reads the shared container read-only.
- **Video format.** Assumes AVFoundation-playable MP4 (H.264/HEVC). Source encoding of the surrealism.tv library is assumed compatible or transcodable.
- **Shared-code build gotcha.** Any playback code shared between the extension and the host preview must have membership in both targets, following the `RainbowAnimator.swift` dual-membership pattern documented in `CLAUDE.md`. Bundled sample videos must be added as a folder reference, not a group.

## Outstanding Questions

**Deferred to planning**

- Backend hosting and stack; Stripe webhook → key-generation → email-delivery flow; key-validation API contract the host app calls.
- Signed-URL TTL and how the app handles an expired URL mid-download.
- Cache location and download-manager approach (resumable downloads, concurrency).
- Thumbnail source: generated from the video vs. provided by the manifest.
- License-key format and how unlock state is persisted locally.
- Playback ordering (shuffle vs. sequential) and behavior on multi-display with differing resolutions.
