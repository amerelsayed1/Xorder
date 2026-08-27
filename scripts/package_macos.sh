#!/usr/bin/env bash
#
# Build and package XOrder POS for macOS distribution.
#
# Produces  dist/XOrder-POS-<version>.dmg  containing the release app and a
# drag-to-Applications shortcut.
#
#   ./scripts/package_macos.sh
#
# Signing. Flutter ad-hoc signs the release build and Xcode injects
# `com.apple.security.get-task-allow` while doing it — a debugger-attach
# entitlement that has no business in a shipped till. This script always
# re-signs to strip it. Export CODESIGN_IDENTITY to sign for real:
#
#   CODESIGN_IDENTITY="Developer ID Application: … (TEAMID)" ./scripts/package_macos.sh
#
# which additionally enables the hardened runtime and a secure timestamp, both
# of which notarisation requires. Without it the DMG is ad-hoc signed and
# Gatekeeper will refuse it on any Mac other than the one that built it.
#
# Notarising. With a stored notarytool profile:
#
#   xcrun notarytool store-credentials xorder --apple-id … --team-id … --password …
#   CODESIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=xorder \
#     ./scripts/package_macos.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="XOrder POS"
BUILD_DIR="build/macos/Build/Products/Release"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
ENTITLEMENTS="macos/Runner/Release.entitlements"
DIST_DIR="dist"

VERSION="$(sed -n 's/^version: *\([0-9.]*\)+.*/\1/p' pubspec.yaml)"
BUILD_NUMBER="$(sed -n 's/^version: *[0-9.]*+\(.*\)/\1/p' pubspec.yaml)"
DMG_PATH="$DIST_DIR/XOrder-POS-$VERSION.dmg"

echo "==> Building $APP_NAME $VERSION ($BUILD_NUMBER)"
flutter build macos --release

[ -d "$APP_PATH" ] || { echo "Build produced no app at $APP_PATH" >&2; exit 1; }

echo "==> Signing"
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  sign_args=(--force --timestamp --options runtime --sign "$CODESIGN_IDENTITY")
else
  echo "    CODESIGN_IDENTITY unset — ad-hoc signing. Gatekeeper will block this"
  echo "    build on other Macs. See the header of this script."
  sign_args=(--force --sign -)
fi

# Inside out: every nested framework before the bundle that contains them,
# otherwise the outer signature seals a payload that then changes.
find "$APP_PATH/Contents/Frameworks" -maxdepth 1 -name "*.framework" -print0 |
  while IFS= read -r -d '' framework; do
    codesign "${sign_args[@]}" "$framework"
  done
codesign "${sign_args[@]}" --entitlements "$ENTITLEMENTS" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> Packaging $DMG_PATH"
rm -rf "$DIST_DIR/dmg-staging" "$DMG_PATH"
mkdir -p "$DIST_DIR/dmg-staging"
cp -R "$APP_PATH" "$DIST_DIR/dmg-staging/"
ln -s /Applications "$DIST_DIR/dmg-staging/Applications"

hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$DIST_DIR/dmg-staging" \
  -ov -format UDZO \
  "$DMG_PATH"
rm -rf "$DIST_DIR/dmg-staging"

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$DMG_PATH"
fi

if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "==> Notarising"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

echo
echo "==> Done: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
