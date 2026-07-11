---
title: "Ambient Surrealism — app improvement pass (controls, theater, wallpaper, account login)"
date: 2026-07-11
type: requirements
status: draft
scope: deep-feature
---

# Ambient Surrealism — App Improvement Pass

## Summary

Evolve the Surrealism Mac app from a **screensaver installer + library manager** into an **ambient-art control center**: a shared playback-control layer that drives multiple "surfaces" where the loops play, plus frictionless account sign-in. Four improvements, ordered by priority: **(1) app-side account login** (primary), **(2) playback controls**, **(3) in-app theater**, **(4) desktop wallpaper mode**. This is the concrete first step of the **"Ambient Surrealism"** positioning — living/ambient motion art that plays on idle (screensaver), always-on the desktop (wallpaper), and on demand (theater); an audio-reactive **visualizer** is a separate future mode.

**Target repos:** primarily `surrealism-application` (the Mac app). App-side login also adds one endpoint in `surrealism-app-website` (the live commerce/accounts backend).

---

## Problem Frame

The app today makes the user a **spectator to their own loops**. It installs a screensaver and manages a library, but:

- **Unlock is friction.** Users must paste a `SURR-XXXX-XXXX-XXXX` key. We shipped real accounts (magic-link login) on the web today, but the app still can't use them.
- **No playback control.** There's no play/pause, skip, shuffle-vs-order, cross-fade adjustment, or way to choose which loops are in rotation. The screensaver just plays everything, shuffled, on its own.
- **Nowhere to actively watch.** There's a "Play all" fullscreen and click-to-play on tiles (`FullScreenPlayer`), but no real on-demand player with controls — no "theater."
- **Loops only appear on idle.** The art can't be an always-on ambient presence on the desktop.

The user named the top two directly: *"no playback controls, change video controls, or in-app theater."* Account login is primary because it removes the highest-friction step before promoting the product widely.

---

## Actors / Users

- **A1 — Buyer/owner:** has purchased; wants to unlock without hunting for a key, control what plays, watch on demand, and set loops as an ambient desktop.
- **A2 — Free/trial user:** has the starter loops; wants to preview the experience (theater, wallpaper) with what they have, as a purchase nudge.

---

## Requirements

### Primary — App-side account login (R1–R4)

- **R1.** From the app, a user can sign in with their **email via magic link** (the account system shipped 2026-07-10) — no pasted key.
- **R2.** After sign-in, the app **silently fetches the account's license key** and runs the existing validate + device-activation flow. The license key stays the underlying credential; accounts just deliver it. `/v1/license/validate`'s contract is **unchanged**.
- **R3.** Pasting a key **remains supported** as a fallback (don't remove the existing path).
- **R4.** Sign-in survives relaunch (the app stores what it needs in the Keychain, as it does the key today) and offers sign-out.

### Playback controls (R5–R8)

- **R5.** A shared control set: **play/pause, next/skip, shuffle vs. in-order, cross-fade duration**, and **choose which loops are in rotation** (a rotation/selection, not necessarily full playlists in v1).
- **R6.** Controls apply to the **in-app surfaces (theater + wallpaper) live**.
- **R7.** The **screensaver keeps its current behavior** in this pass (shuffle + cross-fade); wiring controls to the sandboxed appex is deferred (see Scope Boundaries).
- **R8.** Rotation/settings **persist** across launches.

### In-app theater (R9–R11)

- **R9.** A dedicated **on-demand player** to watch loops inside the app, **fullscreen or windowed**, building on `FullScreenPlayer`/`VideoPlayerController`.
- **R10.** The theater exposes the R5 controls (skip, shuffle, cross-fade, pick loop) with a clean, auto-hiding control overlay (cursor-hide already exists for fullscreen).
- **R11.** Theater plays the current rotation and honors the same cross-fade transitions as the screensaver, so it feels like the same product.

### Desktop wallpaper mode (R12–R16)

- **R12.** A **"Set as wallpaper"** action plays the current rotation in a **borderless window pinned to the desktop level** (behind icons), via the safe desktop-window mechanism (Plash-style) — **not** the aerial-slot rewrite.
- **R13.** Wallpaper mode runs from a **menu-bar agent** so it persists after the main window closes, with quick controls (play/pause, next, stop wallpaper) in the menu-bar item.
- **R14.** **Battery/thermal courtesy:** pause or throttle wallpaper playback when on battery and/or when fully occluded by foreground windows; resume when visible/plugged in. (Default behavior configurable.)
- **R15.** **Multi-display:** at minimum, show the wallpaper on all displays; per-display loop selection is a nice-to-have, not required for v1.
- **R16.** Turning wallpaper off cleanly restores the user's normal desktop wallpaper (we never overwrite system wallpaper files).

### Cross-cutting (R17–R18)

- **R17.** **"Ambient Surrealism" positioning** is reflected in-app: the three surfaces (screensaver / wallpaper / theater) are presented as one coherent product, with "screensaver" kept as the functional term where it aids clarity/SEO.
- **R18.** No regression to what shipped today: notarized build, the corrected macOS-26 settings deep-link, glossy orb, "Surrealism" naming, iris fallback.

---

## Key Flows

- **F1 — Sign in and unlock (primary):** User clicks *Sign in* → enters email → gets a magic link → link opens back to the app (via `surrealism://`) → app exchanges the authenticated session for the license key → validates + activates this device → library unlocks. No key ever typed.
- **F2 — Control what plays:** In the theater or wallpaper, the user hits shuffle/next, drags a cross-fade slider, or toggles which loops are in rotation → the change takes effect immediately on that surface and persists.
- **F3 — Watch in theater:** User opens Theater → current rotation plays fullscreen/windowed with cross-fades → control overlay appears on mouse-move, hides on idle.
- **F4 — Set as wallpaper:** User clicks *Set as wallpaper* → loops play behind the desktop icons → the menu-bar item shows quick controls → closing the main window keeps it running → on battery it eases off → *Stop wallpaper* restores the normal desktop.

---

## Approaches Considered (and decided)

- **Wallpaper mechanism — DECIDED: desktop-pinned window.** There is **no public macOS API** for third parties to set a video as the system wallpaper (Apple's dynamic/aerial wallpapers are Apple-only; a modern third-party appex wallpaper/screensaver API was deferred beyond macOS 26 — FB6363533). The two real options are (a) a **borderless desktop-level window** we fully control (Plash-style) and (b) **rewriting macOS's aerial slot files** unsandboxed (Wallpaper-Sync-style) which also reaches the lock screen. **Chose (a):** safe, reuses `VideoPlayerController`, survives OS updates. **Rejected (b):** unsupported and fragile — the same terrain that just broke the screensaver on macOS 26; it can break on any point release.
- **Account-login model — DECIDED: accounts deliver the key, don't replace it.** Rather than reworking the app's device/entitlement auth, sign-in fetches the existing key and runs the unchanged validate flow. Lowest risk; the key/validate/device-cap logic (just shipped and notarized) is untouched.
- **Control reach — DECIDED: in-app surfaces now, screensaver later.** Theater + wallpaper are in the host process and get controls immediately; wiring controls to the sandboxed screensaver appex needs a shared settings file it reads on launch — deferred.

---

## Scope Boundaries

### In scope
App-side magic-link login (+ one backend token/endpoint), shared playback controls for the in-app surfaces, in-app theater, desktop-window wallpaper mode with a menu-bar agent and battery courtesy, and the in-app "Ambient Surrealism" framing.

### Deferred for later
- **Screensaver control-bridge:** a shared `/Users/Shared` settings file the appex reads so rotation/shuffle/cross-fade also shape the screensaver (applied on its next launch). Noted trade-off: cross-process, appex can't be steered live.
- **Playlists/collections/moods** beyond a simple rotation selection.
- **Per-display loop selection** for wallpaper.
- **Lock-screen** coverage (the desktop-window mechanism can't reach it; only the rejected aerial-rewrite could).

### Outside this product's identity
- **Audio-reactive visualizer mode** — a distinct future product with its own brainstorm/plan (`docs/brainstorms/2026-07-05-visualizer-mode-requirements.md`). "Visualizer" is reserved for that; this pass is passive ambient playback, not sound-reactive.
- **Overwriting Apple's system wallpaper/aerial files** — rejected mechanism; we never touch them.

---

## Success Criteria

- A new buyer unlocks the app **without ever typing a key** (email → link → unlocked).
- The user can **change what's playing** (skip, shuffle, cross-fade, rotation) and it takes effect immediately in theater/wallpaper and persists.
- Loops play **on the desktop as an always-on wallpaper** and stop cleanly, without harming battery in the common case.
- The three surfaces read as **one product**, not three disconnected features.
- Zero regression to the shipped screensaver/build.

---

## Dependencies / Assumptions

- **New backend endpoint (app-facing auth → key).** The app needs a way to exchange an authenticated account session for its license key. This resolves the open question flagged in the accounts plan ("should the account API need an app-facing token later?"). Assumption: implemented in `surrealism-app-website` reusing the session/magic-link primitives shipped 2026-07-10.
- **`surrealism://` URL scheme** is already registered by the app (added 2026-07-10) — the magic-link return path.
- **Menu-bar agent** is a prerequisite for wallpaper mode — an architectural shift from an open-when-needed app to an always-available background presence. It also hosts quick controls, so it's a shared enabler, not wallpaper-only overhead.
- **Reuses existing playback engine** (`VideoPlayerController`, `FullScreenPlayer`) and the `/Users/Shared` loop cache; assumes no change to how loops are downloaded/cached.
- **macOS 26 caveat:** several screensaver/wallpaper behaviors are Apple bugs we can't fix (isPreview misreport, duplicate/accumulating instances, secondary-monitor gaps, removed settings URL). The wallpaper mode is *our* window, so it sidesteps most of these — but multi-display and occlusion handling should be tested on-device.

---

## Outstanding Questions (for planning)

- **App session vs. one-shot key fetch:** after magic-link, does the app get a durable app session (revocable, refreshes the key on tier/refund changes) or just a one-time key fetch? The former is more robust for revocation reaching the app; decide in planning.
- **Cross-fade/rotation as global vs per-surface:** is the rotation/cross-fade one shared setting across theater+wallpaper, or can each surface differ? (Assume shared for v1 unless planning finds a reason to split.)
- **Menu-bar-only vs. dock+menu-bar:** should the app become a menu-bar-primary app (LSUIElement) when wallpaper is active, or keep the normal dock presence? UX + lifecycle decision for planning.
- **Battery policy defaults:** exact default for pause-on-battery / pause-on-occlusion (off by default with a toggle, or on by default?).
