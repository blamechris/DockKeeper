#!/bin/bash
#
# Package dist/DockKeeper.app (and the CLI) into a distributable .dmg with an
# /Applications symlink, plus a checksum for release notes and the cask.
#
# Usage: Scripts/package-dmg.sh [version]     (default: read from the bundle)
#   SIGNING_IDENTITY="Developer ID Application: ..."  also signs the CLI with
#   hardened runtime + timestamp (notarization rejects any unsigned executable
#   in the DMG — learned from submission eb36ef6c). Defaults to ad-hoc.
#   ALLOW_UNSTAPLED_APP=1                             skip the staple gate below
# Run these first, with the same SIGNING_IDENTITY:
#   Scripts/build-app.sh          assemble + sign the bundle
#   Scripts/notarize.sh dist/DockKeeper.app    notarize + staple *the app*
# The app must arrive here already stapled: a cask install copies it out of the
# image, and the DMG's own ticket stays behind (see Scripts/notarize.sh).

set -euo pipefail
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/DockKeeper.app"
[[ -d "$APP" ]] || { echo "error: $APP not found — run Scripts/build-app.sh first"; exit 1; }

# The override disables both the pre-package gate and the post-package ticket
# check, which is enough to reproduce the v0.9.0 defect. Say so loudly — a
# bypass that prints nothing is one an unattended release can ship through.
if [[ "$SIGNING_IDENTITY" != "-" && "${ALLOW_UNSTAPLED_APP:-0}" == "1" ]]; then
    echo "WARNING: ALLOW_UNSTAPLED_APP=1 — staple gate and packaged-ticket check are DISABLED."
    echo "WARNING: the resulting DMG may contain an app with no notarization ticket. Do not ship it."
fi

# Only release builds can be stapled at all — ad-hoc builds skip the gate.
if [[ "$SIGNING_IDENTITY" != "-" && "${ALLOW_UNSTAPLED_APP:-0}" != "1" ]]; then
    if ! xcrun stapler validate "$APP" > /dev/null 2>&1; then
        echo "error: $APP has no stapled notarization ticket."
        echo "       Shipping it would make every first launch after a cask install"
        echo "       wait on Apple's Gatekeeper service (and fail offline)."
        echo "Run:   Scripts/notarize.sh $APP"
        echo "       (ALLOW_UNSTAPLED_APP=1 overrides, for test builds only)"
        exit 1
    fi
    echo "==> App ticket verified (stapled)"
fi

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
DMG="$DIST/DockKeeper-$VERSION.dmg"
STAGE="$DIST/dmg-stage"

echo "==> Building CLI (release)"
swift build -c release --product dockkeeper-cli
mkdir -p "$STAGE"
rm -rf "$STAGE"/* "$DMG"
# ditto, not cp -R: it copies the bundle verbatim — signature, ticket, xattrs.
ditto "$APP" "$STAGE/DockKeeper.app"
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

# The whole point of stapling before packaging is that the ticket survives into
# the image (and out of it again, into /Applications). Prove it here rather than
# discovering it on a user's first offline launch.
if [[ "$SIGNING_IDENTITY" != "-" && "${ALLOW_UNSTAPLED_APP:-0}" != "1" ]]; then
    echo "==> Verifying the packaged app kept its ticket"
    MOUNT="$(mktemp -d)"
    # Detach on any exit path — an abort between attach and detach would leave
    # the image mounted, mid-release, with the DMG still unsigned.
    trap 'hdiutil detach "$MOUNT" > /dev/null 2>&1 || true; rmdir "$MOUNT" 2> /dev/null || true' EXIT
    hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" > /dev/null
    STAPLE_OK=0
    if xcrun stapler validate "$MOUNT/DockKeeper.app" > /dev/null 2>&1; then STAPLE_OK=1; fi
    # A transient busy volume must not abort the release before the ticket
    # verdict below is reported — retry with -force, then give up quietly and
    # let the trap have a last go.
    if ! hdiutil detach "$MOUNT" > /dev/null 2>&1; then
        echo "note: first detach of $MOUNT failed (busy?) — retrying with -force"
        hdiutil detach "$MOUNT" -force > /dev/null 2>&1 || echo "warning: could not detach $MOUNT; unmount it manually"
    fi
    rmdir "$MOUNT" 2> /dev/null || true
    trap - EXIT
    if [[ "$STAPLE_OK" != 1 ]]; then
        echo "error: the app inside $DMG has no ticket — it was lost during packaging."
        exit 1
    fi
fi

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    # Signing the container too keeps `spctl --type open` quiet; the ticket
    # staple is what actually satisfies Gatekeeper.
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG"
    echo "==> Next: Scripts/notarize.sh $DMG (the image needs its own ticket too)"
fi

# NOT the cask checksum: notarize.sh staples the ticket into this file, which
# changes its bytes. Take the hash from notarize.sh's final line instead.
echo "==> Checksum (pre-notarization — informational only):"
shasum -a 256 "$DMG"
