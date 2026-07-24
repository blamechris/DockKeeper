#!/bin/bash
#
# Assemble DockKeeper.app from the SwiftPM build product.
#
# SwiftPM builds a bare executable; this wraps it in a proper .app bundle with
# Info.plist, icon, and entitlements, then code-signs it so LSUIElement,
# SMAppService (Launch at Login), and TCC permissions behave.
#
# Usage: Scripts/build-app.sh [debug|release]           (default: release)
#   SIGNING_IDENTITY="Developer ID Application: ..."    real signing + hardened
#                                                       runtime (release path);
#                                                       defaults to ad-hoc "-"
#   VERSION=1.0.0                                       overrides the bundle
#                                                       version stamped in

set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DockKeeper"
BUNDLE_ID="com.dockkeeper.app"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

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
cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
printf 'APPL????' > "$CONTENTS/PkgInfo"

if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$CONTENTS/Info.plist"
    echo "==> Stamped version $VERSION"
fi

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    echo "==> Ad-hoc code-signing (set SIGNING_IDENTITY for a release build)"
    codesign --force --sign - \
        --entitlements "$ROOT/Resources/DockKeeper.entitlements" \
        --identifier "$BUNDLE_ID" \
        "$APP"
else
    # Hardened runtime is required for notarization (ADR-002); no sandbox
    # entitlement may ever be added (it would break killall/dlsym).
    echo "==> Signing with: $SIGNING_IDENTITY (hardened runtime)"
    codesign --force --sign "$SIGNING_IDENTITY" \
        --options runtime \
        --timestamp \
        --entitlements "$ROOT/Resources/DockKeeper.entitlements" \
        --identifier "$BUNDLE_ID" \
        "$APP"
fi
codesign --verify --strict --verbose=1 "$APP"

echo "==> Done: $APP"
