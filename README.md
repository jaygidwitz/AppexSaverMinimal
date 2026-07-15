# Surrealism — macOS app

The Mac app for **[Surrealism](https://surrealism.app)**: a video-loop
screensaver built as a modern ExtensionKit **`.appex`** (macOS 14+), plus a
host app with a loop library/catalog, license + account sign-in, an in-app
Theater mode, and a Desktop Wallpaper mode with a menu-bar agent. The paid loop
library is sold at surrealism.app (backend lives in
[`../surrealism-app-website`](../surrealism-app-website)).

Forked from [AppexSaverMinimal](https://github.com/AerialScreensaver/AppexSaverMinimal)
by [Guillaume Louel](https://github.com/glouel) — the Xcode project, targets,
and source folders keep that name while the shipped product is `Surrealism.app`
with `app.surrealism.*` bundle IDs.

## Docs

- **[CLAUDE.md](CLAUDE.md)** — architecture, conventions, gotchas (start here)
- **[BACKGROUND.md](BACKGROUND.md)** — deep technical notes on the appex
  screensaver format (rendering approaches, pluginkit, private framework wiring)
- **`docs/plans/`** — dated feature plans; **`docs/brainstorms/`** — the
  requirements behind them

## Build / test

```bash
# Build the host app (embeds the screensaver extension automatically)
xcodebuild -project AppexSaverMinimal.xcodeproj -scheme AppexSaverMinimal -configuration Debug build

# Unit tests (hosted in Surrealism.app)
xcodebuild test -project AppexSaverMinimal.xcodeproj -scheme AppexSaverMinimal
```

Or open `AppexSaverMinimal.xcodeproj` and ⌘R the host app — it installs,
registers (`pluginkit`), and activates the screensaver, and previews the
library live.

## Distribution

```bash
scripts/package.sh   # Developer-ID sign → notarize → staple → branded DMG
```

Requires the Developer-ID certificate and an App Store Connect API key for
`notarytool` (kept in `~/.appstoreconnect/private_keys/`, never in the repo).

## Debugging

Host + extension share one OSLog subsystem:

```bash
open -a ScreenSaverEngine   # exercise the extension
log stream --predicate 'subsystem == "app.surrealism.screensaver"' --level debug
```

## License

MIT — see [LICENSE](LICENSE). Upstream sample © Guillaume Louel; Surrealism
changes © 2026 Surrealism · surrealism.app.
