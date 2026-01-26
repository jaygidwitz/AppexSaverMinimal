# macOS Screensaver Extension Technical Background

This document captures technical knowledge about developing screensaver extensions for macOS using ExtensionKit.

---

## 1. macOS Screensaver Extension Architecture

### ExtensionKit vs Legacy `.saver` Bundles

Modern macOS screensavers (Sonoma+) use ExtensionKit-based `.appex` bundles rather than the legacy `.saver` bundle format. Key differences:

- **Bundle type**: XPC bundle (`CFBundlePackageType: XPC!`) instead of `BNDL`
- **Process model**: Extensions run in a separate sandboxed process
- **Framework**: Uses `ScreenSaver.framework` but with extension-specific classes

### Extension Point

- **Identifier**: `com.apple.screensaver`
- **Version**: `1.0`

### Process Isolation Model

The screensaver extension runs in its own process, separate from `ScreenSaverEngine`. The framework handles all inter-process communication transparently:

- View rendering happens through the framework's XPC layer
- Input events are forwarded back through XPC
- No direct XPC code is needed in extensions

---

## 2. Class Hierarchy

### Public API (ScreenSaver.framework)

| Class | Purpose |
|-------|---------|
| `ScreenSaverView` | Base view class with animation methods (`animateOneFrame()`, `startAnimation()`, `stopAnimation()`) |
| `ScreenSaverDefaults` | UserDefaults subclass for storing screensaver preferences |

### Private API (Reverse-Engineered)

These classes are not documented but are essential for extensions:

| Class | Purpose |
|-------|---------|
| `ScreenSaverExtension` | Principal class managing extension lifecycle |
| `ScreenSaverViewController` | View controller managing the screensaver view; has `representedView` property |
| `ScreenSaverConfigurationViewController` | Base class for configuration sheet view controllers |

---

## 3. Info.plist Configuration Keys

### NSExtension Dictionary

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.screensaver</string>
    <key>NSExtensionPointVersion</key>
    <string>1.0</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).YourExtensionClass</string>
</dict>
```

### Root-Level Screensaver Keys

| Key | Type | Description |
|-----|------|-------------|
| `ScreenSaverViewControllerClass` | String | Fully-qualified name of the main view controller |
| `ScreenSaverConfigurationSheetViewControllerClass` | String | Fully-qualified name of the config sheet view controller |
| `SSEHasConfigureSheet` | Boolean | Whether the screensaver has a configuration UI |
| `SSENeedsAnimationTimer` | Boolean | Whether the framework should provide an animation timer |

---

## 4. Apple's Built-in Screensavers

Location: `/System/Library/ExtensionKit/Extensions/`

| Name | Principal Class | View Controller | Has Config |
|------|-----------------|-----------------|------------|
| Arabesque | `Arabesque.ArabesqueExtension` | `ArabesqueViewController` | No |
| Flurry | `Flurry.FlurryExtension` | `FlurryViewController` | Yes |
| Drift | `Drift.FlowExtension` | `FlowViewController` | Yes |
| Hello | `Hello.HelloExtension` | `HelloViewController` | Yes |
| Monterey | `Monterey.CanyonExtension` | `CanyonViewController` | No |
| Ventura | `Ventura.PetalExtension` | `PetalViewController` | No |
| Shell | `Shell.ShellExtension` | `ShellViewController` | No |

### Naming Conventions

- **Principal class**: `Module.ModuleExtension` (e.g., `Arabesque.ArabesqueExtension`)
- **View controller**: `ModuleViewController` (e.g., `ArabesqueViewController`)
- **View class**: `Module.ModuleView` (e.g., `Arabesque.ArabesqueView`)

---

## 5. XPC Communication

The extension communicates with `ScreenSaverEngine` via XPC, but this is entirely handled by the framework:

- Extension runs in a separate process from ScreenSaverEngine
- Framework handles all XPC communication internally
- No direct XPC code needed in extensions
- View rendering happens through framework's XPC layer
- Input events are forwarded back through XPC

---

## 6. Key Implementation Details

### View Controller

```swift
class YourViewController: ScreenSaverViewController {
    override func loadView() {
        // Create your animation view
        let screensaverView = YourScreenSaverView(frame: .zero)

        // Set self.view directly (NOT representedView)
        self.view = screensaverView
    }
}
```

**Important**: Set `self.view` directly. The `representedView` property exists but setting it directly does not work as expected.

### View

```swift
class YourScreenSaverView: ScreenSaverView {
    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)

        // Enable Core Animation
        wantsLayer = true
    }

    override func makeBackingLayer() -> CALayer {
        // Return custom layer for rendering
        return YourCustomLayer()
    }
}
```

---

## 7. Animation: What Works and What Doesn't

### The Problem with Traditional ScreenSaverView Methods

In the modern appex architecture, the traditional `ScreenSaverView` animation methods are **unreliable**:

| Method | Expected Behavior | Actual Behavior in Appex |
|--------|-------------------|--------------------------|
| `startAnimation()` | Called by framework to start animation | May never be called |
| `stopAnimation()` | Called by framework to stop animation | May never be called |
| `animateOneFrame()` | Called repeatedly by framework timer | May never be called |
| `draw(_:)` | Called when `needsDisplay = true` | **Never called** |
| `needsDisplay = true` | Triggers `draw(_:)` | Does nothing |

This is because:
- With `SSENeedsAnimationTimer = false`, the framework doesn't drive the drawing pipeline
- Apple's own screensavers (Hello.appex, Arabesque.appex) don't use `draw()` at all
- They use either SceneKit (GPU-accelerated) or direct CALayer manipulation

### The Solution: Animate CALayer Directly

Instead of relying on `draw()`, manipulate the backing CALayer directly:

```swift
class YourScreenSaverView: ScreenSaverView {
    private var animationTimer: Timer?
    private var textLayer: CATextLayer?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if self.window != nil {
            // Start your own timer - don't rely on startAnimation()
            startAnimationTimer()
            setupTextLayer()
        } else {
            stopAnimationTimer()
        }
    }

    private func startAnimationTimer() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        // Update layer directly - don't use needsDisplay
        CATransaction.begin()
        CATransaction.setDisableActions(true)  // Disable implicit animations
        self.layer?.backgroundColor = newColor.cgColor
        CATransaction.commit()
    }

    private func setupTextLayer() {
        let layer = CATextLayer()
        layer.string = "Hello"
        layer.fontSize = 24
        layer.foregroundColor = NSColor.white.cgColor
        self.layer?.addSublayer(layer)
        textLayer = layer
    }
}
```

### Key Points

1. **Use your own Timer**: Start it in `viewDidMoveToWindow()`, not in `startAnimation()`
2. **Update `layer.backgroundColor` directly**: Don't use `needsDisplay = true`
3. **Use `CATransaction.setDisableActions(true)`**: Prevents implicit Core Animation transitions for smooth 60fps updates
4. **Use CATextLayer for text overlays**: Don't draw text in `draw(_:)`
5. **Use SceneKit for complex graphics**: Apple's screensavers use `SCNView` for GPU-accelerated rendering

---

## 8. Registration and Discovery

### Using pluginkit

```bash
# Register an extension
pluginkit -a /path/to/YourScreensaver.appex

# List all registered screensavers
pluginkit -m -p com.apple.screensaver

# Remove an extension
pluginkit -r /path/to/YourScreensaver.appex
```

### Extension Location

For development, extensions can be registered from any location. For distribution, they should be embedded in an application bundle at:

```
YourApp.app/Contents/PlugIns/YourScreensaver.appex
```

---

## 9. Thumbnails

### Required Dimensions

System Settings displays screensaver thumbnails at a specific landscape aspect ratio. Using incorrect dimensions (e.g., square images) will cause thumbnails not to appear.

| Scale | Dimensions |
|-------|------------|
| 1x | 107 × 65 pixels |
| 2x | 214 × 130 pixels |

### Asset Catalog Setup

Place thumbnails in an asset catalog imageset named `thumbnail`:

```
Assets.xcassets/
└── thumbnail.imageset/
    ├── Contents.json
    ├── thumbnail.png      (107×65)
    └── thumbnail@2x.png   (214×130)
```

Contents.json:
```json
{
  "images" : [
    { "filename" : "thumbnail.png", "idiom" : "universal", "scale" : "1x" },
    { "filename" : "thumbnail@2x.png", "idiom" : "universal", "scale" : "2x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

### Apple's Approach

| Screensaver | Thumbnail Location | Dimensions (2x) |
|-------------|-------------------|-----------------|
| Flurry | Explicit PNGs in Resources + Assets.car | 180×116 |
| Hello | Assets.car only | 214×130 |

Some Apple screensavers include both explicit PNG files in the Resources folder and thumbnails in the compiled Assets.car. The explicit PNGs may take priority.

### Caching

macOS caches screensaver thumbnails aggressively. After changing thumbnails:

1. Rebuild the project
2. Re-register the extension: `pluginkit -a /path/to/Extension.appex`
3. If thumbnail still doesn't appear:
   - Close and reopen System Settings
   - Log out and back in
   - On a fresh machine, thumbnails appear immediately

---

## References

- ScreenSaver.framework headers (Xcode SDK)
- Apple's built-in screensaver extensions (reverse-engineered: Hello.appex, Arabesque.appex)
- ExtensionKit documentation
