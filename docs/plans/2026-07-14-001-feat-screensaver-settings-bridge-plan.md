---
title: "feat: Screensaver control-bridge — shared settings file the appex reads"
type: feat
date: 2026-07-14
origin: docs/plans/2026-07-13-001-feat-ambient-surfaces-theater-wallpaper-plan.md (Deferred for later)
---

# feat: Screensaver control-bridge

## Summary

Close the deferred R7 gap from the ambient-surfaces plan: rotation / shuffle /
cross-fade / speed currently shape every in-app surface (preview, Theater,
wallpaper) but the screensaver appex ignores them — it always plays the whole
cache, shuffled, at the default fade. The host serializes `PlaybackSettings`
to a world-readable JSON file next to the video cache; the sandboxed extension
reads it on launch and applies it. The appex cannot be steered live (separate
process, no IPC surface) — settings apply on the screensaver's next start,
which is the semantics the ambient plan specified.

## Design

- **`AppexSaverMinimal/SettingsBridge.swift`** — dual target membership (host +
  extension), like `VideoPlayerController`. Pure + I/O:
  - `PlaybackSnapshot: Codable, Equatable` — `version`, `shuffle`,
    `crossFadeSeconds`, `rotation: [String]`, `playbackRate`. Decoding is
    forward-tolerant (missing keys → defaults) and clamps fade/rate to the
    accepted ranges, which move here so both processes share one source of
    truth (`PlaybackSettings` re-exports them).
  - `SettingsBridge.write(_:to:)` — atomic write + explicit `0o644` (the
    extension is another user context; same rule as `LoopDownloader`).
    `SettingsBridge.read(from:)` — `nil` on missing/corrupt (extension then
    behaves exactly as today).
  - File: `/Users/Shared/AppexSaverMinimal/playback.json`.
- **`AppexSaverMinimal/SettingsBridgeWriter.swift`** — host-only, mirrors
  `PlaybackPropagator`: writes once at init (so the file exists before any
  change) then observes the four published settings, debounced 250 ms, and
  rewrites the snapshot. Injected `write` closure for tests. Owned by
  `AppDelegate` from `applicationDidFinishLaunching`, skipped in the unit-test
  host (no side-effect writes to /Users/Shared during tests).
- **Extension apply** — `AppexSaverMinimalView.renderIfPossible` reads the
  snapshot, resolves rotation via `RotationResolver` (gains extension target
  membership; it's pure), and constructs `VideoPlayerController` with the
  resolved URLs/shuffle, then `setFadeDuration` / `setRate`. Missing file →
  current behavior (all loops, shuffle, defaults).

## Units

- U1: `SettingsBridge` + tests (roundtrip, clamping, tolerance, corrupt/missing,
  0o644, atomicity).
- U2: `SettingsBridgeWriter` + tests (initial write, debounced rewrite,
  rapid-edit collapse).
- U3: extension apply + target-membership wiring in `project.pbxproj`
  (SettingsBridge → both, RotationResolver → +extension, writer + tests →
  host/tests).

## Acceptance

- AE1: change rotation/shuffle/fade/speed in the app → `playback.json` updates
  (debounced) with clamped values, world-readable.
- AE2: screensaver launch with a snapshot present plays only the selected
  rotation, honoring shuffle/fade/speed.
- AE3: no file / corrupt file → screensaver behaves exactly as before.
- AE4: unit-test host writes nothing to /Users/Shared.

## Out of scope

- Live steering of a running screensaver (no IPC to the appex).
- Per-surface settings (KTD6 in the ambient plan keeps one global store).
