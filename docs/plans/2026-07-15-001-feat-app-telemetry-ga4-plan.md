---
title: "feat: App telemetry — GA4 Measurement Protocol client + privacy toggle"
type: feat
date: 2026-07-15
---

# feat: App telemetry (GA4 Measurement Protocol)

## Summary

Send anonymous usage events from the host app to the existing GA4 property
(`G-58PPSFN96T` — same one the website reports to), via the Measurement
Protocol. One property, app events prefixed `app_*` and stamped
`platform: "macos"` so web reporting stays filterable. No SDK dependency.

## Design

- **`AppexSaverMinimal/Telemetry.swift`** (host-only) — `@MainActor
  ObservableObject`:
  - Persisted random UUID `client_id` (UserDefaults) — no user identifier.
  - `@Published enabled` (default ON), persisted; a Settings toggle binds it.
  - `send(_ name, params)` — fire-and-forget POST to `mp/collect`; every event
    gets `platform: macos`, `app_version`, `engagement_time_msec: 1`.
  - Hard no-ops: toggle off, placeholder API secret, or running under XCTest
    (unless a test injects its own transport). Never throws, never blocks UI.
  - Transport injected as a closure for tests; payload built by a pure
    function (`Telemetry.payload`) so contents are unit-testable.
- **API secret**: `Telemetry.apiSecret` ships as a placeholder; paste a
  Measurement Protocol secret (GA4 Admin → Data streams → MP API secrets —
  create a second secret, distinct from the webhook's). Until then telemetry
  is silently off. Embedding an MP secret in a shipped binary is normal and
  rotatable; it can only write events, not read data.
- **Events wired**: `app_open` (launch), `app_set_screensaver`
  (PluginManager.enableAsScreensaver), `app_license_unlocked` (locked →
  unlocked transition only, param `tier`), `app_loop_downloaded` (params
  `loop_id`, `is_sample`), `app_theater_opened`, `app_wallpaper_started`.
- **Privacy**: "Share anonymous usage data" toggle in the Playback/settings
  panel; disclosure belongs in the website privacy policy (separate change).
  Never send license keys, emails, or file paths.

## Acceptance

- AE1: payload carries the persisted client_id, `platform: macos`, and the
  event params; disabling the toggle stops sends immediately and persists.
- AE2: no telemetry from the unit-test host; no network without a real secret.
- AE3: full test suite green; events visible in GA4 Realtime once a secret
  is pasted.
