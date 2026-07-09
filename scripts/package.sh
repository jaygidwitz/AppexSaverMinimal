#!/usr/bin/env bash
#
# package.sh — build → Developer-ID sign → notarize → staple → DMG.
#
# Produces a notarized, stapled Surrealism.dmg (drag-to-/Applications) ready for
# direct distribution off surrealism.app. Not for the Mac App Store.
#
# Prerequisites (one-time):
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
PRODUCT_NAME="Surrealism"                 # display name of the shipped .app / DMG volume
BUNDLE_EXECUTABLE="AppexSaverMinimal"     # the built binary name inside Contents/MacOS

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
APP_SRC="$(find "$BUILD/dd/Build/Products/${CONFIG}" -maxdepth 1 -name "${SCHEME}.app" | head -1)"
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

# ── 4. Build the DMG (drag-to-/Applications) ─────────────────────────────────
log "Building ${PRODUCT_NAME}.dmg…"
DMGROOT="$BUILD/dmgroot"; mkdir -p "$DMGROOT"
cp -R "$APP" "$DMGROOT/"
ln -s /Applications "$DMGROOT/Applications"
rm -f "$DMG"
hdiutil create -volname "$PRODUCT_NAME" -srcfolder "$DMGROOT" -ov -format UDZO "$DMG" >/dev/null

# Staple the DMG too (so the ticket travels with the download).
if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
  xcrun stapler staple "$DMG" || true
fi

log "Done → $DMG"
[ "${SKIP_NOTARIZE:-0}" != "1" ] && spctl -a -vvv -t open --context context:primary-signature "$DMG" 2>&1 | tail -3 || true
