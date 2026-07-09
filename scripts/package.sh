#!/usr/bin/env bash
#
# package.sh — build → Developer-ID sign → notarize → staple → DMG.
#
# Produces a notarized, stapled Surrealism.dmg (drag-to-/Applications) ready for
# direct distribution off surrealism.app. Not for the Mac App Store.
#
# Prerequisites (one-time):
#   • create-dmg (branded DMG layout):  brew install create-dmg
#     (the background PNG is scripts/assets/dmg-background.png; regenerate with
#      python3 scripts/make-dmg-background.py)
#   • A "Developer ID Application" cert in your login keychain
#       security find-identity -v -p codesigning   # should list Jay Gidwitz (8FYWMC4BJ3)
#   • A notarytool credential profile named "$NOTARY_PROFILE":
#       xcrun notarytool store-credentials surrealism-notary \
#         --apple-id "you@example.com" --team-id 8FYWMC4BJ3 --password <app-specific-password>
#     …or with an App Store Connect API key:
#       xcrun notarytool store-credentials surrealism-notary \
#         --key AuthKey_XXXX.p8 --key-id <KEY_ID> --issuer <ISSUER_UUID>
#
# Usage:  scripts/package.sh            # full build → notarized DMG
#         SKIP_NOTARIZE=1 scripts/package.sh   # sign + DMG only (no notarization), for a local smoke test
#
set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────
SCHEME="AppexSaverMinimal"
CONFIG="Release"
TEAM_ID="8FYWMC4BJ3"
SIGN_ID="Developer ID Application: Jay Gidwitz (${TEAM_ID})"
NOTARY_PROFILE="${NOTARY_PROFILE:-surrealism-notary}"
PRODUCT_NAME="Surrealism"                 # product/.app/executable name (PRODUCT_NAME in the project)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/package"
STAGE="$BUILD/stage"
APP_SRC=""                                # resolved after the build
APP="$STAGE/${PRODUCT_NAME}.app"
DMG="$BUILD/${PRODUCT_NAME}.dmg"

log() { printf '\n\033[1;35m▶ %s\033[0m\n' "$*"; }

# ── 1. Clean build (unsigned; we sign manually for full control) ─────────────
log "Building ${SCHEME} (${CONFIG})…"
rm -rf "$BUILD"; mkdir -p "$STAGE"
xcodebuild -scheme "$SCHEME" -configuration "$CONFIG" -destination 'platform=macOS' \
  -derivedDataPath "$BUILD/dd" CODE_SIGNING_ALLOWED=NO clean build >/dev/null
APP_SRC="$(find "$BUILD/dd/Build/Products/${CONFIG}" -maxdepth 1 -name "${PRODUCT_NAME}.app" | head -1)"
[ -n "$APP_SRC" ] || { echo "build produced no .app"; exit 1; }

# Stage under the shipped product name (Finder shows Surrealism.app; the inner
# executable keeps its build name — CFBundleName drives the display name).
cp -R "$APP_SRC" "$APP"

# ── 2. Sign inner → outer (Hardened Runtime + secure timestamp) ──────────────
log "Signing (Developer ID, inner → outer)…"
codesign --force --options runtime --timestamp \
  --entitlements "$ROOT/AppexSaverMinimalExtension/AppexSaverMinimalExtension.entitlements" \
  --sign "$SIGN_ID" "$APP/Contents/PlugIns/AppexSaverMinimalExtension.appex"
codesign --force --options runtime --timestamp \
  --entitlements "$ROOT/AppexSaverMinimal/AppexSaverMinimal.entitlements" \
  --sign "$SIGN_ID" "$APP"

log "Verifying signature…"
codesign --verify --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -E "Identifier|Authority=Developer ID|TeamIdentifier|Timestamp|Runtime"

# ── 3. Notarize (zip the .app, submit, wait) ─────────────────────────────────
if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
  log "Notarizing via profile '${NOTARY_PROFILE}'…"
  ZIP="$BUILD/${PRODUCT_NAME}.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  log "Stapling ticket to the .app…"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
else
  log "SKIP_NOTARIZE=1 → skipping notarization/stapling (local smoke test only)."
fi

# ── 4. Build a laid-out DMG, then sign, notarize & staple it ─────────────────
# create-dmg sets the compact window, icon positions, branded background, and the
# Applications drop-link. The .app inside is already notarized+stapled (step 3);
# the DMG then gets its OWN sign→notarize→staple so it passes Gatekeeper offline.
# Requires: brew install create-dmg
log "Building ${PRODUCT_NAME}.dmg (create-dmg, branded layout)…"
rm -f "$DMG"
create-dmg \
  --volname "$PRODUCT_NAME" \
  --volicon "$APP/Contents/Resources/AppIcon.icns" \
  --background "$ROOT/scripts/assets/dmg-background.tiff" \
  --window-pos 200 120 \
  --window-size 660 420 \
  --icon-size 120 \
  --icon "${PRODUCT_NAME}.app" 175 205 \
  --app-drop-link 485 205 \
  --hide-extension "${PRODUCT_NAME}.app" \
  --no-internet-enable \
  "$DMG" "$STAGE" || true   # create-dmg can exit non-zero on a benign AppleScript hiccup
[ -f "$DMG" ] || { echo "create-dmg failed to produce $DMG"; exit 1; }

if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
  log "Signing, notarizing & stapling the DMG…"
  codesign --force --sign "$SIGN_ID" --timestamp "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

log "Done → $DMG"
[ "${SKIP_NOTARIZE:-0}" != "1" ] && spctl -a -vvv -t open --context context:primary-signature "$DMG" 2>&1 | tail -3 || true
