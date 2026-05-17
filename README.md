# AppexSaverMinimal

A minimal sample project for building a macOS screensaver as an **`.appex` extension** (the modern XPC-based ExtensionKit format introduced in macOS Sonoma), maintained by [Guillaume Louel](https://github.com/glouel).

Use this as a starting point for your own Appex screensaver. The companion project [ScreenSaverMinimal](https://github.com/AerialScreensaver/ScreenSaverMinimal) covers the legacy `.saver` plug-in format for comparison.

## What this sample shows

- A complete host app + `.appex` extension wired up to build, sign, and install
- A six-color rainbow fallback (matching [Aerial](https://github.com/AerialScreensaver/Aerial)'s fallback view) driven by `CABasicAnimation`
- Programmatic registration via `pluginkit` and activation via [PaperSaver](https://github.com/AerialScreensaver/PaperSaver)
- Shared rendering code between the screensaver and an in-app preview window
- A configuration sheet stub that you can extend with SwiftUI or AppKit

See [BACKGROUND.md](BACKGROUND.md) for detailed technical notes on the Appex screensaver architecture.

## Building and Installation

### Prerequisites

- Xcode 15 or newer (tested with Xcode 26)
- macOS 14.0 (Sonoma) or newer
- An Apple Developer Team ID if you want to distribute the screensaver to other machines

### Getting Started

1. **Clone the repository:**

   ```bash
   git clone https://github.com/AerialScreensaver/AppexSaverMinimal.git
   cd AppexSaverMinimal
   ```

2. **Open the project in Xcode:**

   ```bash
   open AppexSaverMinimal.xcodeproj
   ```

3. **Set your own Team ID:** open the project settings, select the `AppexSaverMinimal` target, and under **Signing & Capabilities** set your **Team**. Repeat for the `AppexSaverMinimalExtension` target. The project ships with `DEVELOPMENT_TEAM = ""` so you must add yours before signing kicks in.

### Project Targets

This project contains two targets:

- **AppexSaverMinimal** — A SwiftUI host application that bundles and registers the screensaver extension. Run this in Xcode (⌘R) to drive install / uninstall and preview from a normal app window.
- **AppexSaverMinimalExtension** — The screensaver itself, packaged as an `.appex` and embedded inside the host app's `Contents/PlugIns/`.

### Building

```bash
xcodebuild -project AppexSaverMinimal.xcodeproj -scheme AppexSaverMinimal -configuration Debug build
```

### Installing

There are two ways to register the screensaver with macOS:

1. **From the host app** — run the host app and click **Install**. This calls `pluginkit -a` on the embedded `.appex`.
2. **Manually with pluginkit:**

   ```bash
   pluginkit -a ~/Library/Developer/Xcode/DerivedData/AppexSaverMinimal-*/Build/Products/Debug/AppexSaverMinimal.app/Contents/PlugIns/AppexSaverMinimalExtension.appex
   ```

Then open **System Settings → Screen Saver** and choose **AppexSaverMinimal**, or use the **Enable as Screensaver** button in the host app (powered by [PaperSaver](https://github.com/AerialScreensaver/PaperSaver) 0.2.0+).

### Distribution

To distribute a signed and notarized build to others:

1. **Archive** in Xcode (Product → Archive), then export from the Organizer.
2. **Notarize via command line:**

   ```bash
   xcrun notarytool submit "AppexSaverMinimal.app.zip" \
     --keychain-profile "AC_PASSWORD" \
     --wait

   xcrun stapler staple "AppexSaverMinimal.app"
   xcrun stapler validate "AppexSaverMinimal.app"
   ```

   You need a keychain profile set up first:

   ```bash
   xcrun notarytool store-credentials "AC_PASSWORD" \
     --apple-id "your@email.com" \
     --team-id "TEAMID" \
     --password "app-specific-password"
   ```

## Logs via Console.app

Both the host app and the extension log to a single subsystem so you can watch their lifecycles side-by-side.

1. Open **Console.app**.
2. Filter by subsystem:

   ```
   subsystem:net.aerialscreensaver.AppexSaverMinimal
   ```

3. Trigger the screensaver:

   ```bash
   open -a ScreenSaverEngine
   ```

   You'll see log lines from three processes: the host app (when previewing), the extension (when rendering), and `legacyScreenSaver` / `ScreenSaverEngine` lifecycle events.

You can also stream logs from the command line:

```bash
log stream --predicate 'subsystem == "net.aerialscreensaver.AppexSaverMinimal"' --level debug
```

## Project Structure

```
AppexSaverMinimal/                            Host app
├── AppexSaverMinimalApp.swift                @main SwiftUI app entry
├── ContentView.swift                         Install / uninstall / activate UI
├── PluginManager.swift                       pluginkit + PaperSaver wrappers
├── PreviewView.swift                         NSView for the host's preview window
├── PreviewViewRepresentable.swift            SwiftUI wrapper around PreviewView
├── RainbowAnimator.swift                     Shared 6-color animation
├── Helpers/
│   └── Logger.swift                          Shared OSLog subsystem
├── Info.plist
└── AppexSaverMinimal.entitlements

AppexSaverMinimalExtension/                   Screensaver appex
├── AppexSaverMinimalExtension.swift          Principal class
├── AppexSaverMinimalViewController.swift     ScreenSaverViewController
├── AppexSaverMinimalView.swift               ScreenSaverView (uses RainbowAnimator)
├── AppexSaverMinimalConfigurationViewController.swift   Configuration sheet
├── PrivateHeaders/
│   └── ScreenSaverPrivate.h                  Private API declarations (pre-public SDK)
├── AppexSaverMinimalExtension-Bridging-Header.h
├── Info.plist                                NSExtensionPrincipalClass etc.
└── AppexSaverMinimalExtension.entitlements
```

## Comparison to the legacy `.saver` format

If you need to target older macOS versions that don't support Appex screensavers, see the companion repo [ScreenSaverMinimal](https://github.com/AerialScreensaver/ScreenSaverMinimal). The two projects intentionally share the same rainbow fallback look so you can read them as a pair.

| | `.appex` (this repo) | `.saver` ([companion](https://github.com/AerialScreensaver/ScreenSaverMinimal)) |
|---|---|---|
| **Bundle type** | `XPC!` (ExtensionKit) | `BNDL` (NSBundle plug-in) |
| **Process** | Separate sandboxed process | In-process with `legacyScreenSaver.appex` |
| **Min macOS** | 14.0 (Sonoma) | All supported macOS |
| **Distribution** | Embedded in a `.app` | Standalone `.saver` file |
| **System Settings entry** | Listed alongside Apple's first-party savers | Listed under a separate "Other" group |

## Development Caveat

Once a copy of the appex is registered from `/Applications` (e.g. after installing a release build), macOS will not pick up DerivedData builds, and `pluginkit` won't let you register a second copy from elsewhere. On a development machine it's safest to use DerivedData builds only and test `/Applications` deployment in a separate VM.

## License

[MIT](LICENSE) © 2026 Guillaume Louel
