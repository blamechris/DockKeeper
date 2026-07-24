#!/bin/bash
#
# Package dist/DockKeeper.app (and the CLI) into a distributable .dmg with an
# /Applications symlink, plus a checksum for release notes and the cask.
#
# Usage: Scripts/package-dmg.sh [version]     (default: read from the bundle)
#   SIGNING_IDENTITY="Developer ID Application: ..."  also signs the CLI with
#   hardened runtime + timestamp (notarization rejects any unsigned executable
#   in the DMG — learned from submission eb36ef6c). Defaults to ad-hoc.
# Run Scripts/build-app.sh first (with the same SIGNING_IDENTITY).

set -euo pipefail
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/DockKeeper.app"
[[ -d "$APP" ]] || { echo "error: $APP not found — run Scripts/build-app.sh first"; exit 1; }

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
DMG="$DIST/DockKeeper-$VERSION.dmg"
STAGE="$DIST/dmg-stage"

echo "==> Building CLI (release)"
swift build -c release --product dockkeeper-cli
mkdir -p "$STAGE"
rm -rf "$STAGE"/* "$DMG"
cp -R "$APP" "$STAGE/"
cp "$ROOT/.build/release/dockkeeper-cli" "$STAGE/dockkeeper"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    echo "==> Ad-hoc signing CLI (set SIGNING_IDENTITY for a notarizable build)"
    codesign --force --sign - --identifier com.dockkeeper.cli "$STAGE/dockkeeper"
else
    echo "==> Signing CLI with: $SIGNING_IDENTITY (hardened runtime)"
    codesign --force --sign "$SIGNING_IDENTITY" \
        --options runtime --timestamp \
        --identifier com.dockkeeper.cli \
        "$STAGE/dockkeeper"
fi
codesign --verify --strict "$STAGE/dockkeeper"

ln -s /Applications "$STAGE/Applications"

echo "==> Creating $DMG"
hdiutil create -volname "DockKeeper $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" > /dev/null
rm -rf "$STAGE"

echo "==> Checksum (for release notes and Casks/dockkeeper.rb):"
shasum -a 256 "$DMG"
