#!/bin/sh
# Builds a universal Release app and packs it into dist/Claudenotchi-<version>.dmg.
#
#   scripts/release.sh                         unsigned build (testing the packaging)
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/release.sh
#                                              signed with the hardened runtime
#   ... NOTARY_PROFILE=claudenotchi scripts/release.sh
#                                              also notarizes and staples
#
# One-time notarization setup (stores the credentials in the keychain):
#   xcrun notarytool store-credentials claudenotchi --apple-id <id> --team-id <TEAMID>
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
APP="$BUILD/Build/Products/Release/Claudenotchi.app"

rm -rf "$BUILD" "$DIST"
mkdir -p "$DIST"

# Build settings go in "$@" so an identity name with spaces stays one argument.
if [ -n "${SIGN_IDENTITY:-}" ]; then
  set -- CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$SIGN_IDENTITY" OTHER_CODE_SIGN_FLAGS=--timestamp ENABLE_HARDENED_RUNTIME=YES
else
  set -- CODE_SIGNING_ALLOWED=NO
fi

xcodebuild -project "$ROOT/Claudenotchi.xcodeproj" -scheme Claudenotchi -configuration Release \
  -derivedDataPath "$BUILD" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO "$@" build

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST/Claudenotchi-$VERSION.dmg"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  # The embedded helper is signed by the build phase with the app's identity; sign it again with the
  # hardened runtime and a timestamp (both are required for notarization), then the app around it.
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP/Contents/Helpers/claudenotchi-hook"
  codesign --force --options runtime --timestamp --entitlements "$ROOT/Claudenotchi/Claudenotchi.entitlements" --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
fi

STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Claudenotchi" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

if [ -n "${SIGN_IDENTITY:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

shasum -a 256 "$DMG"
echo "Built $DMG"
