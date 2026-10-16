#!/bin/sh
# Builds a universal Release app and packs it into dist/Claudenotchi-<version>.dmg.
#
#   scripts/release.sh                         unsigned build (testing the packaging)
#   VERSION=1.1 scripts/release.sh             a new version: dist/Claudenotchi-1.1.dmg
#                                              (default: the project's MARKETING_VERSION)
#   BUILD_NUMBER=7 ...                         the build number (default: the number of git commits)
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/release.sh
#                                              signed with the hardened runtime
#   ... NOTARY_PROFILE=claudenotchi scripts/release.sh
#                                              also notarizes and staples
#
# One-time notarization setup (stores the credentials in the keychain):
#   xcrun notarytool store-credentials claudenotchi --apple-id <id> --team-id <TEAMID>
#
# Earlier versions in dist/ are kept. A DMG is never overwritten: if one with this version already exists,
# the script stops before building; pick a new VERSION or delete the old file.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
APP="$BUILD/Build/Products/Release/Claudenotchi.app"

if [ -z "${VERSION:-}" ]; then
  VERSION="$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' "$ROOT/Claudenotchi.xcodeproj/project.pbxproj" | head -1)"
fi
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"
DMG="$DIST/Claudenotchi-$VERSION.dmg"

mkdir -p "$DIST"
if [ -e "$DMG" ]; then
  echo "$DMG already exists. Use a new version, for example: VERSION=<new> scripts/release.sh" >&2
  exit 1
fi
rm -rf "$BUILD"

# Build settings go in "$@" so an identity name with spaces stays one argument.
set -- "MARKETING_VERSION=$VERSION" "CURRENT_PROJECT_VERSION=$BUILD_NUMBER"
if [ -n "${SIGN_IDENTITY:-}" ]; then
  set -- "$@" CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$SIGN_IDENTITY" OTHER_CODE_SIGN_FLAGS=--timestamp ENABLE_HARDENED_RUNTIME=YES
else
  set -- "$@" CODE_SIGNING_ALLOWED=NO
fi

xcodebuild -project "$ROOT/Claudenotchi.xcodeproj" -scheme Claudenotchi -configuration Release \
  -derivedDataPath "$BUILD" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO "$@" build

BUILT="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[ "$BUILT" = "$VERSION" ] || { echo "The app says version $BUILT, expected $VERSION" >&2; exit 1; }

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
