#!/bin/sh
# Xcode build phase: builds the claudenotchi-hook helper with SwiftPM and embeds it in the app
# bundle at Contents/Helpers/claudenotchi-hook. At runtime the app copies it to a stable path
# (see HelperDeployer) and registers that copy in Claude Code's settings.json.
#
# Note: builds for the host architecture only. A universal (arm64 + x86_64) helper is needed for
# distribution and is part of the release milestone.
set -eu

PACKAGE="$SRCROOT/Packages/ClaudenotchiCore"
CONFIG=debug
[ "${CONFIGURATION:-Debug}" = "Release" ] && CONFIG=release
SCRATCH="${DERIVED_FILE_DIR:-${TMPDIR:-/tmp}}/hook-helper-build"
DEST="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"

# SwiftPM runs in a clean environment: Xcode's build settings leak in and confuse it.
swiftpm() {
  if [ -n "${DEVELOPER_DIR:-}" ]; then
    env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" DEVELOPER_DIR="$DEVELOPER_DIR" \
      /usr/bin/xcrun swift build -c "$CONFIG" --product claudenotchi-hook \
      --package-path "$PACKAGE" --scratch-path "$SCRATCH" "$@"
  else
    env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      /usr/bin/xcrun swift build -c "$CONFIG" --product claudenotchi-hook \
      --package-path "$PACKAGE" --scratch-path "$SCRATCH" "$@"
  fi
}

swiftpm >&2
BIN="$(swiftpm --show-bin-path)"

mkdir -p "$DEST"
cp -f "$BIN/claudenotchi-hook" "$DEST/claudenotchi-hook"

# Sign with the app's identity so the bundle's signature stays valid.
if [ "${CODE_SIGNING_ALLOWED:-YES}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$DEST/claudenotchi-hook"
fi
