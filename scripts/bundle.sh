#!/bin/bash
# Build Sesame, assemble Sesame.app, sign with Developer ID + hardened runtime, and
# (if a notarytool keychain profile exists) notarize + staple for distribution.
#
#   ./scripts/bundle.sh            # release build, sign, notarize if profile present
#   ./scripts/bundle.sh debug      # debug build (ad-hoc signed)
#
# Notarization needs a one-time credential store (kept out of this repo):
#   xcrun notarytool store-credentials sesame \
#     --apple-id <you@example.com> --team-id KVGD368RNR --password <app-specific-password>
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
IDENTITY="${SESAME_SIGN_IDENTITY:-Developer ID Application: Anup Chavan (KVGD368RNR)}"
NOTARY_PROFILE="${SESAME_NOTARY_PROFILE:-sesame}"
APP="dist/Sesame.app"
ENTITLEMENTS="Support/Sesame.entitlements"

swift build -c "$CONFIG"
BIN=".build/$CONFIG/Sesame"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Sesame"
cp Support/Info.plist "$APP/Contents/Info.plist"

FRAMEWORK=$(find .build/artifacts -type d -name "WebRTC.framework" -path "*macos*" | head -1)
if [ -n "$FRAMEWORK" ]; then
  cp -R "$FRAMEWORK" "$APP/Contents/Frameworks/"
else
  echo "warning: WebRTC.framework not found under .build/artifacts" >&2
fi

# ---- code signing ----
SIGNED=0
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
  echo "Signing with: $IDENTITY"
  # Embedded framework first (Developer ID + hardened runtime + secure timestamp).
  if [ -d "$APP/Contents/Frameworks/WebRTC.framework" ]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" \
      "$APP/Contents/Frameworks/WebRTC.framework"
  fi
  # Then the app, with entitlements + hardened runtime.
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
  echo "signature verified"
  SIGNED=1
else
  echo "Developer ID identity not found — ad-hoc signing (local dev only)"
  codesign --force --deep --sign - "$APP"
fi

# ---- notarization (optional) ----
if [ "$SIGNED" = "1" ] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "Notarizing (profile: $NOTARY_PROFILE)…"
  ZIP="dist/Sesame.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  ditto -c -k --keepParent "$APP" "$ZIP"   # re-zip the stapled app for distribution
  echo "Notarized + stapled → $ZIP"
  xcrun stapler validate "$APP" && spctl -a -vv "$APP" || true
else
  [ "$SIGNED" = "1" ] && echo "Skipping notarization: no notarytool profile '$NOTARY_PROFILE' (see header)."
fi

echo "Built $APP"
