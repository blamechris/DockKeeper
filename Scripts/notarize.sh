#!/bin/bash
#
# Notarize and staple a DockKeeper artifact — the .app (release checklist §4)
# and the .dmg that carries it (§5).
#
# Both need their own ticket. `brew install --cask` copies DockKeeper.app *out*
# of the image into /Applications, and the DMG's ticket does not travel with it
# — an app with no ticket of its own makes every first launch wait on a network
# round-trip to Apple's Gatekeeper service (and fail closed offline). Verified
# on the shipped v0.9.0 artifact: the DMG validated, the app inside it reported
# "does not have a ticket stapled to it". So: staple the app *before* it is
# packaged, then notarize and staple the DMG as well.
#
# notarytool accepts .zip/.dmg/.pkg only, so a .app argument is zipped with
# ditto (which preserves the signature) purely for submission; the ticket is
# then stapled onto the bundle itself, never the throwaway zip.
#
# One-time setup (owner; needs an Apple Developer account):
#   xcrun notarytool store-credentials dockkeeper-notary \
#       --apple-id you@example.com --team-id TEAMID
#
# Usage: Scripts/notarize.sh dist/DockKeeper.app              [keychain-profile]
#        Scripts/notarize.sh dist/DockKeeper-<version>.dmg    [keychain-profile]

set -euo pipefail

TARGET="${1:?usage: Scripts/notarize.sh <app-or-dmg> [keychain-profile]}"
PROFILE="${2:-dockkeeper-notary}"
TARGET="${TARGET%/}"

[[ -e "$TARGET" ]] || { echo "error: $TARGET not found"; exit 1; }

ZIP=""
cleanup() { [[ -n "$ZIP" ]] && rm -f "$ZIP"; return 0; }
trap cleanup EXIT

if ! xcrun notarytool history --keychain-profile "$PROFILE" > /dev/null 2>&1; then
    echo "error: notarytool profile '$PROFILE' not configured."
    echo "Run:   xcrun notarytool store-credentials $PROFILE --apple-id <id> --team-id <team>"
    exit 1
fi

SUBMISSION="$TARGET"
if [[ "$TARGET" == *.app ]]; then
    # Ad-hoc signatures are rejected by the notary service with a much less
    # obvious error, so fail here instead.
    if codesign --display --verbose=2 "$TARGET" 2>&1 | grep -q 'Signature=adhoc'; then
        echo "error: $TARGET is ad-hoc signed — rebuild with SIGNING_IDENTITY set:"
        echo "       VERSION=x.y.z SIGNING_IDENTITY='Developer ID Application: …' Scripts/build-app.sh release"
        exit 1
    fi
    ZIP="${TARGET%.app}-notarize.zip"
    rm -f "$ZIP"
    echo "==> Zipping $TARGET for submission"
    ditto -c -k --keepParent "$TARGET" "$ZIP"
    SUBMISSION="$ZIP"
fi

echo "==> Submitting $SUBMISSION for notarization (waits for the verdict)"
SUBMIT_OUT="$(xcrun notarytool submit "$SUBMISSION" --keychain-profile "$PROFILE" --wait 2>&1 | tee /dev/stderr)"
SUBMISSION_ID="$(echo "$SUBMIT_OUT" | awk '/id:/ {print $2; exit}')"
if ! echo "$SUBMIT_OUT" | grep -q 'status: Accepted'; then
    echo "==> REJECTED — fetching the notary log for $SUBMISSION_ID"
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$PROFILE" || true
    exit 1
fi

# Staple the artifact itself: for an app that is the bundle, not the zip we
# submitted (a zip has nowhere to keep a ticket).
echo "==> Stapling $TARGET"
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"

echo "==> Gatekeeper check"
if [[ "$TARGET" == *.app ]]; then
    spctl --assess --type execute -vv "$TARGET" || true
    echo "==> Done. Next: Scripts/package-dmg.sh — it builds the DMG from this stapled app."
else
    spctl --assess --type open --context context:primary-signature -v "$TARGET" || true

    # Stapling rewrites the DMG, so the checksum package-dmg.sh printed is
    # already stale by now. This one is the shipped bytes — it is what goes in
    # the cask and the release notes (v0.9.0 shipped with the pre-staple hash
    # and `brew install` failed on a checksum mismatch until it was corrected).
    echo "==> Checksum of the STAPLED dmg — use this one in Casks/dockkeeper.rb:"
    shasum -a 256 "$TARGET"
    echo "==> Verify the copied-out app still carries its ticket (checklist §6):"
    echo "       hdiutil attach $TARGET && xcrun stapler validate /Volumes/DockKeeper*/DockKeeper.app"
    echo "==> Done. First run validates the TDD's 'no entitlement conflicts' claim — record the result in docs/decision-log.md."
fi
