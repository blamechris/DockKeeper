#!/bin/bash
#
# Notarize and staple a DockKeeper .dmg (release checklist §4).
#
# One-time setup (owner; needs an Apple Developer account):
#   xcrun notarytool store-credentials dockkeeper-notary \
#       --apple-id you@example.com --team-id TEAMID
#
# Usage: Scripts/notarize.sh dist/DockKeeper-<version>.dmg [keychain-profile]

set -euo pipefail

DMG="${1:?usage: Scripts/notarize.sh <dmg> [keychain-profile]}"
PROFILE="${2:-dockkeeper-notary}"

if ! xcrun notarytool history --keychain-profile "$PROFILE" > /dev/null 2>&1; then
    echo "error: notarytool profile '$PROFILE' not configured."
    echo "Run:   xcrun notarytool store-credentials $PROFILE --apple-id <id> --team-id <team>"
    exit 1
fi

echo "==> Submitting $DMG for notarization (waits for the verdict)"
SUBMIT_OUT="$(xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait 2>&1 | tee /dev/stderr)"
SUBMISSION_ID="$(echo "$SUBMIT_OUT" | awk '/id:/ {print $2; exit}')"
if ! echo "$SUBMIT_OUT" | grep -q 'status: Accepted'; then
    echo "==> REJECTED — fetching the notary log for $SUBMISSION_ID"
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$PROFILE" || true
    exit 1
fi

echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> Gatekeeper check"
spctl --assess --type open --context context:primary-signature -v "$DMG" || true

# Stapling rewrites the DMG, so the checksum package-dmg.sh printed is already
# stale by now. This one is the shipped bytes — it is what goes in the cask and
# the release notes (v0.9.0 shipped with the pre-staple hash and `brew install`
# failed on a checksum mismatch until it was corrected).
echo "==> Checksum of the STAPLED dmg — use this one in Casks/dockkeeper.rb:"
shasum -a 256 "$DMG"
echo "==> Done. First run validates the TDD's 'no entitlement conflicts' claim — record the result in docs/decision-log.md."
