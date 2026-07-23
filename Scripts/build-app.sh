#!/bin/bash
#
# Assemble DockKeeper.app from the SwiftPM build product.
#
# SwiftPM builds a bare executable; this wraps it in a proper .app bundle with
# Info.plist + entitlements and ad-hoc code-signs it so LSUIElement, SMAppService
# (Launch at Login), and TCC permissions behave. For release you'd swap the
# ad-hoc identity for a Developer ID and notarize.
#
# Usage: Scripts/build-app.sh [debug|release]   (default: release)

set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DockKeeper"
BUNDLE_ID="com.dockkeeper.app"

BUILD_DIR="$ROOT/.build/$CONFIG"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"

echo "==> Building $APP_NAME ($CONFIG)"
swift build -c "$CONFIG" --product "$APP_NAME"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BUILD_DIR/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "==> Ad-hoc code-signing"
codesign --force --sign - \
    --entitlements "$ROOT/Resources/DockKeeper.entitlements" \
    --identifier "$BUNDLE_ID" \
    "$APP"
codesign --verify --strict --verbose=1 "$APP"

echo "==> Done: $APP"
