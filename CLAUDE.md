# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Surrealism** — a paid macOS video-loop screensaver + ambient app, built as an
ExtensionKit `.appex` screensaver (macOS 14.0+) embedded in a SwiftUI host app.
Forked from the `AppexSaverMinimal` rainbow sample; the fork point still shows in
on-disk names (see "Naming mismatch" below). The paid loop library is sold at
surrealism.app — the sibling repo `../surrealism-app-website` is the backend.

See `BACKGROUND.md` for generic appex-screensaver architecture notes (still
accurate) and `docs/plans/` for feature plans. `README.md` still describes the
original rainbow sample and is NOT a guide to this app.

## Naming mismatch (deliberate, don't "fix" casually)

Brand and bundle identity are migrated; on-disk names are not:

- Bundle IDs: host `app.surrealism.screensaver`, extension
  `app.surrealism.screensaver.Extension`, tests `app.surrealism.screensaver.Tests`.
  `DEVELOPMENT_TEAM = 8FYWMC4BJ3`. Built product is `Surrealism.app`.
- Still `AppexSaverMinimal*`: the `.xcodeproj`, target names, scheme names,
  source folders, and the shared video cache path
  `/Users/Shared/AppexSaverMinimal/videos`.
- OSLog subsystem: `app.surrealism.screensaver` (via `AppexLog`,
  `AppexSaverMinimal/Helpers/Logger.swift`) — shared by host and extension.

## Two targets + tests, one host app

- **AppexSaverMinimal** — SwiftUI host app (`Surrealism.app`): library/catalog
  manager, license + account sign-in, screensaver install/activate, live
  preview, Theater mode, Desktop Wallpaper.
- **AppexSaverMinimalExtension** — the actual screensaver `.appex`, embedded at
  `Surrealism.app/Contents/PlugIns/…`. Discovered via `pluginkit`; never runs
  standalone.
- **AppexSaverMinimalTests** — unit-test bundle hosted in the app
  (`TEST_HOST = …/Surrealism.app/Contents/MacOS/Surrealism`). Test files sit
  next to the code they test (`*Tests.swift` in `AppexSaverMinimal/` and
  `Commerce/`). `AppexSaverMinimalApp.swift` detects XCTest via
  `ProcessInfo.isRunningUnitTests` and skips mounting networked/account UI in
  the test host — keep that guard in mind when adding startup UI.

## Critical: shared code lives via dual target membership

Five files are compiled into BOTH the host and extension targets (two
`Sources` build phases in `project.pbxproj`):

- `AppexSaverMinimal/VideoPlayerController.swift` — the playback engine
- `AppexSaverMinimal/SettingsBridge.swift` — settings file the appex reads on launch
- `AppexSaverMinimal/RotationResolver.swift` — pure rotation-selection resolver
- `AppexSaverMinimal/RainbowAnimator.swift` — legacy fallback when the cache is empty
- `AppexSaverMinimal/Helpers/Logger.swift`

**Any file both the screensaver and the host preview must share MUST be added to
both targets' membership** — a file in only one target silently breaks rendering
parity. Everything else (`Commerce/`, `Ambient/`, settings, catalog) is
host-app only.

## Source layout (host app)

- `AppexSaverMinimal/` root — app entry (`AppexSaverMinimalApp.swift`),
  `ContentView.swift`, `PluginManager.swift` (pluginkit install/activate via
  PaperSaver), preview views, playback engine + settings
  (`VideoPlayerController.swift`, `PlaybackSettings.swift`,
  `PlaybackPropagation.swift`, `RotationResolver.swift`,
  `PlaybackControlsView.swift`).
- `AppexSaverMinimal/Ambient/` — Theater + Wallpaper surfaces:
  `TheaterWindow.swift`, `TheaterControlsOverlay.swift`,
  `WallpaperController.swift`, `WallpaperWindow.swift`, `MenuBarAgent.swift`,
  `CourtesyMonitor.swift` (battery/thermal pause), `PlaybackCommands.swift`,
  `PlaybackShortcuts.swift`.
- `AppexSaverMinimal/Commerce/` — license/account/catalog/download:
  `CommerceAPI.swift`, `LicenseStore.swift`, `LicenseView.swift`,
  `CatalogModel.swift`, `CatalogView.swift`, `LoopDownloader.swift`,
  `AuthCallbackRouter.swift`, `PKCE.swift`, `DeviceID.swift`, `Keychain.swift`.
- `AppexSaverMinimalExtension/` — the appex: `AppexSaverMinimalView.swift`
  (ScreenSaverView; plays the shared cache via `VideoPlayerController`, falls
  back to `RainbowAnimator` when empty), view/config controllers,
  `PrivateHeaders/` for the private ScreenSaver.framework ExtensionKit symbols.

## Playback engine

`VideoPlayerController.swift` drives both the screensaver and every host
surface: two `AVPlayerLayer`s cross-faded for rotation (the fade is gated on
the incoming player having a ready frame — don't regress this; it fixed a
flash/crash), `AVPlayerLooper` for gapless single-clip loop, playback-speed
support. Clips come from `/Users/Shared/AppexSaverMinimal/videos`.

Settings reach the screensaver via the **control-bridge**: the host serializes
`PlaybackSettings` (debounced, via `SettingsBridgeWriter`) to the world-readable
`/Users/Shared/AppexSaverMinimal/playback.json`; the appex reads it on its next
launch (`SettingsBridge.read()` in `AppexSaverMinimalView`). No IPC — the appex
is never steered live. Missing/corrupt file → historic defaults.

**Cache permission gotcha**: the host app writes downloads with explicit 0o644
perms (`LoopDownloader.swift`) because the sandboxed extension runs as a
different process and must be able to read them.

## Commerce / auth (talks to surrealism.app)

`CommerceAPI.swift`, base `https://surrealism.app`:
`POST /v1/license/validate`, `POST /v1/auth/start` (magic link),
`POST /v1/auth/exchange` (one-time code + PKCE verifier → license key),
`GET /v1/catalog`, `POST /v1/download` (short-lived presigned R2 URL; 403 =
expired, re-request). Sign-in returns via the `surrealism://auth/callback`
deep link (`AuthCallbackRouter.swift` validates `state`; PKCE protects against
URL-scheme squatting). Keys (`SURR-XXXX-…`) live in the Keychain with offline
grace and a 3-device limit (`LicenseStore.swift`).

## Telemetry

`Telemetry.swift` (host-only) sends anonymous `app_*` events to the same GA4
property as the website via the Measurement Protocol — persisted random UUID,
`platform: "macos"` on every event, user toggle in the Playback panel. It's a
silent no-op until a real MP API secret replaces `Telemetry.apiSecret`'s
placeholder, and always a no-op in the unit-test host. Never send license
keys, emails, or file paths.

## Dependencies (SPM)

- **PaperSaver** (`github.com/AerialScreensaver/PaperSaver`) — sets the active
  screensaver system-wide from `PluginManager.swift` (which also shells out to
  `/usr/bin/pluginkit` and matches the extension by its bundle id).

## Build / test / package

```bash
# Build the host app (embeds the extension automatically)
xcodebuild -project AppexSaverMinimal.xcodeproj -scheme AppexSaverMinimal -configuration Debug build

# Run unit tests
xcodebuild test -project AppexSaverMinimal.xcodeproj -scheme AppexSaverMinimal

# Developer-ID sign → notarize → staple → DMG
scripts/package.sh
```

### Registering / activating the screensaver

macOS usually auto-discovers the appex after a build; opening **System
Settings → Screen Saver** is often enough, or run the host app and click
**Install** / **Enable as Screensaver**. Manual registration:

```bash
pluginkit -a ~/Library/Developer/Xcode/DerivedData/AppexSaverMinimal-*/Build/Products/Debug/Surrealism.app/Contents/PlugIns/AppexSaverMinimalExtension.appex
```

**Gotcha — pick ONE location per machine.** `pluginkit` caches where it found
an extension and prefers `/Applications/`. If copies exist in both DerivedData
and `/Applications/`, macOS keeps loading the `/Applications/` one. While
iterating, stay entirely in DerivedData.

### Triggering + debugging

```bash
open -a ScreenSaverEngine   # exercise the extension
log stream --predicate 'subsystem == "app.surrealism.screensaver"' --level debug
```

The extension runs in a separate sandboxed process — the shared log stream is
the primary debugging tool; you can't breakpoint it like the host app.

## Thumbnails

System Settings only shows landscape thumbnails from
`AppexSaverMinimalExtension/Assets.xcassets/thumbnail.imageset` (107×65 @1x,
214×130 @2x). macOS caches them aggressively — re-register with `pluginkit -a`,
reopen System Settings, log out/in if a stale one persists.

## Docs

- `docs/plans/` — dated feature plans (video screensaver, visualizer mode,
  app-side account login, playback controls, rotation tiles, ambient surfaces).
- `docs/brainstorms/` — requirements docs behind the plans.
- `BACKGROUND.md` — generic appex architecture deep-dive (still valid).
