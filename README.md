# AppexSaver

A minimal macOS screensaver extension (.appex) demonstrating the modern ScreenSaver framework.

## Requirements

- macOS 14.0+
- Xcode 15+

## Build

```bash
xcodebuild -scheme AppexSaver -configuration Debug build
```

## Register Extension

macOS may automatically register the extension when the app is placed in `/Applications`. You can also register manually:

```bash
pluginkit -a ~/Library/Developer/Xcode/DerivedData/AppexSaver-*/Build/Products/Debug/AppexSaver.app/Contents/PlugIns/AppexSaverExtension.appex
```

## Set as Active Screensaver

Launch the app and use the built-in button to register. Enabling the screensaver is done via [PaperSaver](https://github.com/AerialScreensaver/PaperSaver) 0.2.0+.

## Test

```bash
# Monitor logs
log stream --predicate 'subsystem == "com.glouel.AppexSaver"' --level debug

# Trigger screensaver
open -a ScreenSaverEngine
```

Or open System Settings > Screen Saver and select "Appex Saver".

## Structure

- `AppexSaver/` - Host app (required to bundle the extension)
- `AppexSaverExtension/` - The screensaver extension
  - `AppexSaverExtension.swift` - Principal class
  - `AppexSaverViewController.swift` - View controller
  - `AppexSaverView.swift` - Animation implementation

## Animation Architecture

Traditional `ScreenSaverView` methods (`draw()`, `animateOneFrame()`, `startAnimation()`) are **not reliably called** in the modern appex architecture. Instead, animate by manipulating CALayer directly:

- Update `layer.backgroundColor` from a Timer callback
- Use `CATextLayer` or other sublayers for overlays
- Use `CATransaction.setDisableActions(true)` for smooth updates
- Start your own Timer in `viewDidMoveToWindow()` rather than relying on `startAnimation()`

See [BACKGROUND.md](BACKGROUND.md) for detailed technical information.

## Development Caveat

Once registered from `/Applications`, macOS will not run builds from Xcode's DerivedData and won't allow registering the extension from another location. On a development machine, it is recommended to only use DerivedData builds and test deployment in `/Applications` in a separate VM.
