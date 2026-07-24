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
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> Gatekeeper check"
spctl --assess --type open --context context:primary-signature -v "$DMG" || true
echo "==> Done. First run validates the TDD's 'no entitlement conflicts' claim — record the result in docs/decision-log.md."
