#!/usr/bin/env swift

import Foundation

// Path to the wallpaper plist
let plistPath = NSString(string: "~/Library/Application Support/com.apple.wallpaper/Store/Index.plist").expandingTildeInPath
let plistURL = URL(fileURLWithPath: plistPath)

print("Reading plist from: \(plistPath)")

// Read existing plist
guard let plistData = try? Data(contentsOf: plistURL),
      var plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
    print("❌ Failed to read plist")
    exit(1)
}

print("✅ Plist loaded successfully")

// Path to our appex screensaver
let appexPath = "/Users/guillaume/Library/Developer/Xcode/DerivedData/AppexSaver-duxhlrsetfrlcmcaapzvdyswkqir/Build/Products/Debug/AppexSaver.app/Contents/PlugIns/AppexSaverExtension.appex/"

// Verify appex exists
if !FileManager.default.fileExists(atPath: appexPath) {
    print("❌ Appex not found at: \(appexPath)")
    print("Please build the project first or update the path")
    exit(1)
}

print("✅ Appex found at: \(appexPath)")

// Create screensaver configuration
// The module path needs to be a file URL
let moduleURL = "file://" + appexPath

let config: [String: Any] = [
    "module": ["relative": moduleURL]
]

guard let configData = try? PropertyListSerialization.data(
    fromPropertyList: config,
    format: .binary,
    options: 0
) else {
    print("❌ Failed to serialize config")
    exit(1)
}

print("✅ Created screensaver config")

// Create Idle configuration
let idleConfig: [String: Any] = [
    "Content": [
        "Choices": [[
            "Configuration": configData,
            "Files": [] as [Any],
            "Provider": "com.apple.wallpaper.choice.screen-saver"
        ]]
    ],
    "LastSet": Date(),
    "LastUse": Date()
]

// Update AllSpacesAndDisplays
if var allSpaces = plist["AllSpacesAndDisplays"] as? [String: Any] {
    allSpaces["Idle"] = idleConfig
    plist["AllSpacesAndDisplays"] = allSpaces
    print("✅ Updated AllSpacesAndDisplays.Idle")
} else {
    print("⚠️ AllSpacesAndDisplays not found, creating new structure")
    plist["AllSpacesAndDisplays"] = [
        "Idle": idleConfig
    ]
}

// Write plist back
do {
    let outputData = try PropertyListSerialization.data(
        fromPropertyList: plist,
        format: .binary,
        options: 0
    )
    try outputData.write(to: plistURL)
    print("✅ Plist written successfully")
} catch {
    print("❌ Failed to write plist: \(error)")
    exit(1)
}

// Restart WallpaperAgent to apply changes
print("Restarting WallpaperAgent...")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
process.arguments = ["WallpaperAgent"]
do {
    try process.run()
    process.waitUntilExit()
    print("✅ WallpaperAgent restarted")
} catch {
    print("⚠️ Could not restart WallpaperAgent: \(error)")
}

print("")
print("🎉 Screensaver set!")
print("")
print("To test:")
print("  1. Start log monitoring:")
print("     log stream --predicate 'subsystem == \"com.glouel.AppexSaver\"' --level debug")
print("")
print("  2. Trigger screensaver:")
print("     open -a ScreenSaverEngine")
print("")
print("  3. Move mouse to exit screensaver")
