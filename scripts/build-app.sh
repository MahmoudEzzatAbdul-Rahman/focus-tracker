#!/usr/bin/env bash
# Builds FocusTracker.app into ./build and code-signs it.
#
# macOS ties Camera/Accessibility grants to the code signature. An ad-hoc signature
# changes on every build, so grants would reset each time; signing with a stable
# self-signed identity (see README) keeps them. Override the identity with SIGN_IDENTITY.
set -euo pipefail

cd "$(dirname "$0")/.."
IDENTITY="${SIGN_IDENTITY:-FocusTracker Dev}"
CONFIGURATION="${CONFIGURATION:-release}"
APP="build/FocusTracker.app"

swift build -c "$CONFIGURATION" --arch arm64
BIN_DIR="$(swift build -c "$CONFIGURATION" --arch arm64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/FocusTracker" "$APP/Contents/MacOS/FocusTracker"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" "$APP"
  echo "Signed with \"$IDENTITY\""
else
  codesign --force --sign - "$APP"
  echo "warning: identity \"$IDENTITY\" not found, signed ad-hoc; permissions will reset on every rebuild." >&2
fi

echo "Built $APP"
