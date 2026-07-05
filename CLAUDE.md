# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A minimal sample project for a **macOS screensaver built as an ExtensionKit `.appex`** (the modern XPC-based format, macOS Sonoma 14.0+), as opposed to the legacy `.saver` NSBundle plug-in. See `BACKGROUND.md` for deep technical notes on the appex screensaver architecture and `README.md` for install/distribution details.

The sample renders a six-color rainbow fallback via `CABasicAnimation`. It is intended as a fork point — you replace the rainbow with your own content (e.g. video playback).

## Two targets, one host app

The project has **two targets** and the extension only runs when embedded in the host app:

- **AppexSaverMinimal** (`net.aerialscreensaver.AppexSaverMinimal`) — SwiftUI host app. Its job is to *bundle, register, and activate* the screensaver, plus show an in-app preview. Not the screensaver itself. Run this target (⌘R) to drive install/uninstall/activate.
- **AppexSaverMinimalExtension** (`net.aerialscreensaver.AppexSaverMinimal.Extension`) — the actual screensaver `.appex`, embedded into the host at `AppexSaverMinimal.app/Contents/PlugIns/AppexSaverMinimalExtension.appex`.

macOS discovers the screensaver via `pluginkit`, which reads the embedded appex — so the extension is never used standalone; it must be inside a built host `.app`.

## Critical: shared code lives via dual target membership

`AppexSaverMinimal/RainbowAnimator.swift` physically sits in the **host app folder** but is compiled into **both targets** (it appears in two `Sources` build phases in `project.pbxproj`). This is how the extension and the host's preview window render identically:

- `AppexSaverMinimalExtension/AppexSaverMinimalView.swift` (`ScreenSaverView`) uses `RainbowAnimator`.
- `AppexSaverMinimal/PreviewView.swift` (plain `NSView`) uses the same `RainbowAnimator`.

**When adding any file that both the screensaver and the preview must share, it MUST be added to both targets' membership.** A file compiled into only the extension will not exist for the preview, and vice versa — this is the single most common way to silently break rendering parity. Edit `project.pbxproj` to add the file to both `Sources` build phases (or set both checkboxes in Xcode's File Inspector).

Non-shared code: `PluginManager.swift`, `ContentView.swift`, `AppexSaverMinimalApp.swift` are host-app only. The `*ViewController`, `*Extension`, `*ConfigurationViewController` classes are extension-only.

## Rendering model

The extension does **not** use the framework's per-frame timer. `Info.plist` sets `SSENeedsAnimationTimer = false`; the `RainbowAnimator` drives its own `Timer` + `CABasicAnimation` on the backing `CALayer`. Animation start/stop is anchored on `viewDidMoveToWindow()` (robust across both `ScreenSaverEngine` and the System Settings preview), not solely on the framework's `startAnimation()/stopAnimation()` overrides. `BACKGROUND.md` §5 documents the three valid rendering approaches (direct CALayer, traditional overrides, SwiftUI via `NSHostingView`).

The extension links the private `ScreenSaver.framework` ExtensionKit symbols (`ScreenSaverExtension`, `ScreenSaverViewController`, `ScreenSaverConfigurationViewController`) — declarations are in `AppexSaverMinimalExtension/PrivateHeaders/ScreenSaverPrivate.h` via the bridging header. `Info.plist` wires the classes through `NSExtensionPrincipalClass`, `ScreenSaverViewControllerClass`, and `ScreenSaverConfigurationSheetViewControllerClass`, all using the `$(PRODUCT_MODULE_NAME).ClassName` prefix.

## Dependencies (SPM)

- **PaperSaver** 0.2.0 (`github.com/AerialScreensaver/PaperSaver`) — used by `PluginManager` to set the active screensaver system-wide (`setScreensaverEverywhere`, `getActiveScreensavers`). Pulls in swift-argument-parser transitively.

`PluginManager.swift` shells out to `/usr/bin/pluginkit` (`-a` install, `-r` uninstall, `-m -v -p com.apple.screensaver` query) and matches its extension by the bundle id `net.aerialscreensaver.AppexSaverMinimal.Extension`.

## Build / run

```bash
# Build the host app (embeds the extension automatically)
xcodebuild -project AppexSaverMinimal.xcodeproj -scheme AppexSaverMinimal -configuration Debug build

# Open in Xcode to run/preview (⌘R runs the host app)
open AppexSaverMinimal.xcodeproj
```

Before signing works, set `DEVELOPMENT_TEAM` for **both** targets (ships empty as `DEVELOPMENT_TEAM = ""`). Deployment target is macOS 14.0. No test target exists in this project.

### Registering / activating the screensaver

macOS usually auto-discovers the appex after a build; opening **System Settings → Screen Saver** is often enough. If not, register the built appex manually:

```bash
pluginkit -a ~/Library/Developer/Xcode/DerivedData/AppexSaverMinimal-*/Build/Products/Debug/AppexSaverMinimal.app/Contents/PlugIns/AppexSaverMinimalExtension.appex
```

Or run the host app and click **Install** / **Enable as Screensaver**.

**Gotcha — pick ONE location per machine.** `pluginkit` caches where it found an extension and hardcodes a preference for `/Applications/`. If a copy exists in both DerivedData and `/Applications/`, macOS keeps loading the `/Applications/` one regardless of what you last built. While iterating, stay entirely in DerivedData and never copy to `/Applications/`. If already mixed, remove one copy and re-register the other.

### Triggering + debugging

```bash
# Start the screensaver engine to exercise the extension
open -a ScreenSaverEngine

# Stream logs from host app + extension (single shared OSLog subsystem)
log stream --predicate 'subsystem == "net.aerialscreensaver.AppexSaverMinimal"' --level debug
```

Both processes log to the shared subsystem via `AppexLog` (`Helpers/Logger.swift`) so you can watch host + extension lifecycles together in Console.app. This is the primary debugging tool — the extension runs in a separate sandboxed process, so you cannot simply `print`/breakpoint it the way you would the host app.

## Thumbnails

System Settings only shows landscape thumbnails from `AppexSaverMinimalExtension/Assets.xcassets/thumbnail.imageset` (107×65 @1x, 214×130 @2x). Square images won't render. macOS caches thumbnails aggressively — after changes, re-register with `pluginkit -a`, reopen System Settings, and log out/in if a stale one persists.
