#!/bin/bash
#
# Drive the release-checklist §3-§5 sequence in one invocation.
#
# The four steps below are individually runnable and stay that way — this script
# exists because the sequence is only correct if the operator remembers three
# things, each of which is a silent failure when forgotten:
#
#   1. SIGNING_IDENTITY must be exported for the WHOLE sequence. If it is set for
#      build-app.sh but not package-dmg.sh, the latter defaults to ad-hoc: it
#      skips the staple gate, skips the packaged-ticket check, ad-hoc signs the
#      CLI, and leaves the DMG unsigned. Nothing complains until the notary
#      rejects the CLI, a full submission round trip later.
#   2. build-app.sh must not be re-run after the app is stapled — it rebuilds the
#      bundle from scratch and the ticket goes with it.
#   3. ALLOW_UNSTAPLED_APP is for test builds. Exported in a shell and forgotten,
#      it disables exactly the gates that catch the v0.9.0 defect.
#
# This script removes all three by construction: one identity read once, the
# steps in order, a postcondition asserted between each, and a refusal to start
# if the override is set.
#
# Usage: SIGNING_IDENTITY="Developer ID Application: …" Scripts/release.sh <version>
#   [keychain-profile]   notarytool profile (default: dockkeeper-notary)
#
# Prints the stapled DMG's sha256 as its final line — that is the cask value.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?usage: Scripts/release.sh <version> [keychain-profile]}"
PROFILE="${2:-dockkeeper-notary}"
APP="$ROOT/dist/DockKeeper.app"
DMG="$ROOT/dist/DockKeeper-$VERSION.dmg"

# --- preflight: fail before doing any work, not after a notary round trip -----

if [[ -n "${ALLOW_UNSTAPLED_APP:-}" ]]; then
    echo "error: ALLOW_UNSTAPLED_APP is set (=$ALLOW_UNSTAPLED_APP)."
    echo "       That flag disables the staple gate and the packaged-ticket check —"
    echo "       the two things standing between here and reshipping the v0.9.0 defect."
    echo "       It is for test builds only. Unset it and re-run:  unset ALLOW_UNSTAPLED_APP"
    exit 1
fi

if [[ -z "${SIGNING_IDENTITY:-}" || "$SIGNING_IDENTITY" == "-" ]]; then
    echo "error: SIGNING_IDENTITY must be a real Developer ID identity, not ad-hoc."
    echo "Run:   export SIGNING_IDENTITY=\"Developer ID Application: … (TEAMID)\""
    echo "Available:"
    security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" || echo "  (none found in the keychain)"
    exit 1
fi
export SIGNING_IDENTITY

if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGNING_IDENTITY"; then
    echo "error: '$SIGNING_IDENTITY' is not in the keychain."
    echo "Available:"
    security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" || echo "  (none found)"
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "$PROFILE" > /dev/null 2>&1; then
    echo "error: notarytool profile '$PROFILE' is not configured — a release needs it twice."
    echo "Run:   xcrun notarytool store-credentials $PROFILE --apple-id <id> --team-id <team>"
    exit 1
fi

echo "==> Releasing $VERSION"
echo "    identity: $SIGNING_IDENTITY"
echo "    profile:  $PROFILE"
echo "    Two notary submissions follow; each takes a few minutes."

# --- §3 build & sign ---------------------------------------------------------

echo
echo "===== [1/4] §3  Build and sign the bundle ====="
VERSION="$VERSION" "$ROOT/Scripts/build-app.sh" release

STAMPED="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [[ "$STAMPED" != "$VERSION" ]]; then
    echo "error: bundle reports version '$STAMPED', expected '$VERSION' — refusing to continue."
    exit 1
fi

# --- §4 notarize + staple the APP (before packaging) -------------------------

echo
echo "===== [2/4] §4  Notarize and staple the app ====="
"$ROOT/Scripts/notarize.sh" "$APP" "$PROFILE"

# Postcondition. package-dmg.sh checks this too; asserting here names the failure
# at the step that caused it instead of one step later.
if ! xcrun stapler validate "$APP" > /dev/null 2>&1; then
    echo "error: $APP has no ticket after notarize.sh reported success — refusing to package."
    exit 1
fi
echo "==> App ticket confirmed"

# --- §5 package (from the stapled app) ---------------------------------------
#
# Note what does NOT happen here: build-app.sh is not re-entered. The bundle
# package-dmg.sh consumes is the stapled one from step 2.

echo
echo "===== [3/4] §5  Package the DMG from the stapled app ====="
"$ROOT/Scripts/package-dmg.sh" "$VERSION"

[[ -f "$DMG" ]] || { echo "error: expected $DMG, not found"; exit 1; }

# --- §5 notarize + staple the DMG --------------------------------------------

echo
echo "===== [4/4] §5  Notarize and staple the DMG ====="
"$ROOT/Scripts/notarize.sh" "$DMG" "$PROFILE"

if ! xcrun stapler validate "$DMG" > /dev/null 2>&1; then
    echo "error: $DMG has no ticket after notarize.sh reported success."
    exit 1
fi

# Final proof, on the artifact as it will ship: mount the finished image and
# confirm the app inside still carries its own ticket. This is the v0.9.0
# regression, checked on the real file rather than inferred from the steps.
MOUNT="$(mktemp -d)"
trap 'hdiutil detach "$MOUNT" > /dev/null 2>&1 || true; rmdir "$MOUNT" 2> /dev/null || true' EXIT
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" > /dev/null
INNER_OK=0
if xcrun stapler validate "$MOUNT/DockKeeper.app" > /dev/null 2>&1; then INNER_OK=1; fi
if ! hdiutil detach "$MOUNT" > /dev/null 2>&1; then
    hdiutil detach "$MOUNT" -force > /dev/null 2>&1 || echo "warning: could not detach $MOUNT"
fi
rmdir "$MOUNT" 2> /dev/null || true
trap - EXIT
if [[ "$INNER_OK" != 1 ]]; then
    echo "error: the app inside the shipped DMG has no ticket. Do not release this artifact."
    exit 1
fi

echo
echo "==> Release artifact ready: $DMG"
echo "    app ticket: stapled · dmg ticket: stapled · app-inside-dmg ticket: stapled"
echo "    Next: checklist §6 (fresh-user pass, including an OFFLINE first launch) and §7."
echo
echo "==> sha256 for Casks/dockkeeper.rb and the release notes:"
shasum -a 256 "$DMG"
