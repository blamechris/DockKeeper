# DockKeeper 0.9.5 — Release and Install Runbook

| | |
|---|---|
| **Status** | PREPARED — not yet signed, notarized or published. Nothing in this file is evidence that a 0.9.5 artifact exists. |
| **Date** | 2026-09-26 |
| **Owner** | blamechris |
| **Source** | `main` at the merge commit of the PR that adds this file (the `[0.9.5]` changelog section rides with it). The exact SHA is recorded in the PR's closing comment and the session handoff; tag **that** commit, never a later one. |
| **Channel** | GitHub **pre-release** only. `Casks/dockkeeper.rb` and `blamechris/homebrew-tap` are **not** updated for this candidate (owner direction: no stable-channel promotion). |

Evidence labels: **CONFIRMED** · **INFERRED** · **PROPOSED** · **UNKNOWN**.

This is a worked, one-release instance of the [release checklist](release-checklist.md) §3–§7, for the owner-selected milestone "works on both Macs, on your real desk": get both Macs onto one notarized build that has the live readout (`status --live`, #78) and the #79/#99 copy fixes. The full 1.0 hardware matrix is deferred by the owner and is **not** a gate here.

---

## 1. Prerequisite (owner): a signing identity in the shell

The release must be signed with the existing Developer ID Application identity and notarized with the existing `dockkeeper-notary` profile. Nothing here creates, changes or discovers an identity.

State checked 2026-09-26 in the preparing session:

- `dockkeeper-notary` notary profile: **works** (`xcrun notarytool history --keychain-profile dockkeeper-notary` exit 0).
- `SIGNING_IDENTITY`: **not set** in that environment. The preparing session was not permitted to list keychain identities, so it could not sign. **This is the one step that needs you.**

In the shell you will release from:

```sh
export SIGNING_IDENTITY="Developer ID Application: <your name> (<TEAMID>)"   # exact string, the one used for 0.9.0–0.9.4
unset ALLOW_UNSTAPLED_APP
[ -n "$SIGNING_IDENTITY" ] && [ "$SIGNING_IDENTITY" != "-" ] && echo "identity set" || echo "NOT SET — stop"
```

⚠️ `build-app.sh` and `package-dmg.sh` **silently fall back to ad-hoc signing** when `SIGNING_IDENTITY` is unset. That produces an artifact that looks finished and fails notarization, or worse, ships unsigned. Check the last line above says `identity set` before continuing.

## 2. Check out the exact source

```sh
cd <a clean clone of blamechris/DockKeeper>
git fetch origin
git checkout --detach <SOURCE_SHA>          # from the PR's closing comment
git status --short                          # must print nothing
swift test                                  # must end "Test run with … tests … passed"
```

## 3. Build, sign, notarize, package — pick ONE path

### Path A — the release driver (you run it)

```sh
Scripts/release.sh 0.9.5
```

It asserts the identity against the keychain (`security find-identity`), stamps the version, notarizes and staples the app, packages, notarizes and staples the DMG, mounts the finished image to confirm the inner app's ticket, and prints the sha256 last. Take the checksum from that **final line**.

### Path B — the four lower scripts (no identity discovery)

For a session that has `SIGNING_IDENTITY` set but may not list keychain identities. It is the same sequence `release.sh` runs, minus its preflight, so the checks it would make are done by hand after each step.

```sh
# [1/4] build + sign, with the version stamped explicitly
VERSION=0.9.5 Scripts/build-app.sh release
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/DockKeeper.app/Contents/Info.plist   # → 0.9.5
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion'            dist/DockKeeper.app/Contents/Info.plist   # → 0.9.5
codesign --verify --strict --verbose=2 dist/DockKeeper.app                                              # → valid on disk / satisfies its Designated Requirement
codesign -dv dist/DockKeeper.app 2>&1 | grep -E '^Authority=Developer ID Application|flags=.*runtime'   # → both lines present

# [2/4] notarize + staple the APP — before packaging; never re-run build-app.sh after this
Scripts/notarize.sh dist/DockKeeper.app
xcrun stapler validate dist/DockKeeper.app                                                              # → The validate action worked!

# [3/4] package from the stapled app (same shell, same SIGNING_IDENTITY)
Scripts/package-dmg.sh 0.9.5

# [4/4] notarize + staple the DMG
Scripts/notarize.sh dist/DockKeeper-0.9.5.dmg
xcrun stapler validate dist/DockKeeper-0.9.5.dmg                                                        # → The validate action worked!
```

Then check the artifact as it will ship: the app **inside** the image must carry its own ticket (the v0.9.0 regression).

```sh
M=$(mktemp -d)
hdiutil attach dist/DockKeeper-0.9.5.dmg -nobrowse -readonly -mountpoint "$M"
xcrun stapler validate "$M/DockKeeper.app"                                  # → The validate action worked!
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$M/DockKeeper.app/Contents/Info.plist"   # → 0.9.5
codesign --verify --strict --verbose=2 "$M/dockkeeper"                      # → CLI signed (it cannot be stapled; checklist §5)
hdiutil detach "$M"
shasum -a 256 dist/DockKeeper-0.9.5.dmg                                     # ← THE checksum; record it
```

**Any failed check above means the artifact does not ship.** Do not publish it, and ignore any checksum printed for it.

## 4. Publish the pre-release (no cask, no tap)

```sh
git tag -a v0.9.5 <SOURCE_SHA> -m "DockKeeper 0.9.5"
git push origin v0.9.5
# Put the recorded sha256 into the notes file's placeholder first (see §4a).
gh release create v0.9.5 dist/DockKeeper-0.9.5.dmg \
  --prerelease --verify-tag \
  --title "DockKeeper 0.9.5 — public beta" \
  --notes-file <notes file from §4a>
```

Verify what was published, not what was uploaded:

```sh
gh release view v0.9.5 --json isPrerelease,tagName,assets -q '.isPrerelease, .tagName, .assets[].name'   # → true, v0.9.5, DockKeeper-0.9.5.dmg
DK095_VERIFY_DIR=$(mktemp -d)
gh release download v0.9.5 -R blamechris/DockKeeper -p DockKeeper-0.9.5.dmg -D "$DK095_VERIFY_DIR"
shasum -a 256 "$DK095_VERIFY_DIR/DockKeeper-0.9.5.dmg"                     # → matches §3
git rev-list -n1 v0.9.5                                                    # → <SOURCE_SHA>
```

**Not done for this candidate**, deliberately: `Casks/dockkeeper.rb` and `blamechris/homebrew-tap` stay at 0.9.4, so `brew install/upgrade --cask dockkeeper` keeps installing 0.9.4. Promoting 0.9.5 to the cask is a separate owner decision after desk QA.

### 4a. Release notes

The `[0.9.5]` section of [CHANGELOG.md](../CHANGELOG.md), then:

```markdown
## Install

Download `DockKeeper-0.9.5.dmg` below. Notarized and stapled; the app inside the image carries its own ticket.
Homebrew still installs 0.9.4 — this beta is not in the cask yet.

**sha256** `<from §3>`
```

## 5. Install the exact DMG — each Mac (owner)

Both Macs originally installed DockKeeper from the Homebrew cask. These steps replace the **app** in place with the exact 0.9.5 build and keep the old one for rollback. Run them in Terminal on the Mac being updated.

**5.1 Record what is there now** (paste it back. The work Mac's baseline is unknown, probably 0.9.0):

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/DockKeeper.app/Contents/Info.plist
brew list --cask --versions dockkeeper
pgrep -lx DockKeeper
```

**5.2 Download and check the checksum.** Download from the release page, or:

```sh
gh release download v0.9.5 -R blamechris/DockKeeper -p DockKeeper-0.9.5.dmg -D ~/Downloads --clobber
shasum -a 256 ~/Downloads/DockKeeper-0.9.5.dmg      # must equal the published sha256 exactly — stop if not
```

A browser download may be named `DockKeeper-0.9.5 (1).dmg`. The steps below use `~/Downloads/DockKeeper-0.9.5.dmg`, so use the `gh` command or rename the file.

**5.3 Quit the running copy.** Use the DockKeeper menu-bar icon ▸ **Quit**, which runs the clean quit (it restores any Dock auto-hide DockKeeper borrowed). Then:

```sh
pgrep -lx DockKeeper                                  # must print nothing before you continue
```

**5.4 Swap the app, keeping the old one.** Paste the whole block. It runs in its own `bash` with `-e`, so it **stops at the first failure**. If the image fails to mount or holds the wrong build, it stops before anything is moved. It refuses if DockKeeper is still running. The old app is moved to a new, timestamped path, which is appended to `~/.dockkeeper-backups` for §7. Nothing is deleted.

```sh
bash -euo pipefail <<'EOF'
DMG=~/Downloads/DockKeeper-0.9.5.dmg
BACKUP=~/DockKeeper-before-0.9.5-$(date -u +%Y%m%dT%H%M%SZ).app
if pgrep -x DockKeeper >/dev/null; then echo "REFUSING: DockKeeper is still running. Quit it from the menu bar first."; exit 1; fi
[ -d /Applications/DockKeeper.app ] || { echo "REFUSING: /Applications/DockKeeper.app not found."; exit 1; }
[ ! -e "$BACKUP" ] || { echo "REFUSING: $BACKUP already exists."; exit 1; }
M=$(mktemp -d /tmp/dk-0.9.5.XXXXXX)
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$M"
trap 'hdiutil detach "$M" >/dev/null 2>&1 || true' EXIT
V=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$M/DockKeeper.app/Contents/Info.plist")
[ "$V" = "0.9.5" ] || { echo "REFUSING: the image holds $V, not 0.9.5."; exit 1; }
xcrun stapler validate "$M/DockKeeper.app"
[ -x "$M/dockkeeper" ] || { echo "REFUSING: no dockkeeper CLI in the image."; exit 1; }
mv /Applications/DockKeeper.app "$BACKUP"
printf '%s\n' "$BACKUP" >> ~/.dockkeeper-backups
ditto "$M/DockKeeper.app" /Applications/DockKeeper.app
mkdir -p ~/.local/bin
ditto "$M/dockkeeper" ~/.local/bin/dockkeeper-0.9.5
echo "OK: 0.9.5 installed. Previous app kept at $BACKUP"
EOF
```

Only if the block ends with `OK:`, start it:

```sh
open /Applications/DockKeeper.app
```

If it stopped after the `mv` (for example, `ditto` failed), the previous app is at the path on the last line of `~/.dockkeeper-backups`, and §7 restores it.

Why the CLI goes to its own path: any `dockkeeper` already on your `PATH` is the CLI from whichever Homebrew cask version that Mac last installed (0.9.4 on the personal Mac as of 2026-09-23; unknown on the work Mac). Every published version predates `status --live`. `~/.local/bin/dockkeeper-0.9.5` is the CLI from the same image as the app, so its report matches the running app.

**5.5 Verify:**

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/DockKeeper.app/Contents/Info.plist   # → 0.9.5
spctl -a -vv /Applications/DockKeeper.app            # → accepted, source=Notarized Developer ID
xcrun stapler validate /Applications/DockKeeper.app  # → The validate action worked!
pgrep -lx DockKeeper | wc -l                         # → 1
~/.local/bin/dockkeeper-0.9.5 status --live; echo "exit $?"
/Applications/DockKeeper.app/Contents/MacOS/DockKeeper --diagnostics
```

Expected from `status --live`: it names the running app's version **0.9.5** and install path `/Applications/DockKeeper.app`, and exits `0` (live and agreeing). Exit `6` means live but diverging: the report names the disagreement and says which side is in force. `3`/`4`/`5` mean no usable live record. Paste the whole output either way.

Expected, and not a problem: `brew list --cask --versions dockkeeper` still shows the version from 5.1, because a manual install leaves Homebrew's record unchanged. Separately, the published cask is at 0.9.4, so a later `brew upgrade --cask dockkeeper` would replace 0.9.5 with 0.9.4. Don't run it on these Macs until the cask is promoted.

Accessibility: an existing grant is **INFERRED** to carry over, because the grant is tied to the signing identity and bundle ID, and those do not change. If the Preferences caption says it is waiting for Accessibility, grant it in System Settings ▸ Privacy & Security ▸ Accessibility. For this guard, DockKeeper uses it to hold the pointer a few points clear of the bottom edge of your other displays, so a bottom Dock is not summoned there. One other optional feature uses the same permission: "Keep windows in place when pinning" (Preferences ▸ General), which moves windows back after a pin. Nothing leaves the Mac.

**5.6 Work Mac only — turn the guard on.** It is off by default, and the work Mac is probably coming from 0.9.0, which has no guard. With the external monitor attached:

1. DockKeeper menu ▸ Preferences ▸ **Dock**: Lock Edge **Bottom**. Then DockKeeper menu ▸ **Preferred Display** ▸ the screen the Dock belongs on.
2. Preferences ▸ **Advanced**: turn on "Keep a bottom Dock on my preferred display", then grant Accessibility when asked (purpose above).
3. Re-run `~/.local/bin/dockkeeper-0.9.5 status --live` and `--diagnostics` from 5.5, and paste both.

**Personal Mac:** the guard should already be on. 5.5's `status --live` output confirms it rather than assumes it.

## 6. What to check, and send back

| # | Check | How | Status before your run |
|---|---|---|---|
| Q1 | Both Macs run the notarized 0.9.5 | 5.5 on each Mac: version, `spctl`, `stapler`, one process | UNKNOWN |
| Q2 | The running app is the one the report describes | `status --live` exit code and full output on each Mac | UNKNOWN |
| Q3 | **#79 menu copy renders untruncated** | With separate Spaces on and a bottom lock: open the menu with the guard **off**, then **on**. Every line reads in full, with no "…" in the middle. The guard-on message says the setting is on with "details in Preferences › Advanced". It does not say the Dock is being kept. | Unit-tested at ≤110 characters per line. **Real-menu rendering not verified.** |
| Q4 | **#99 Preferences text** | Preferences ▸ Advanced, under the toggle: no sentence about hot corners | Unit-tested; not seen rendered |
| Q5 | Guard caption vs live state | If the caption says "Active — holding…", compare it with `status --live`. The caption is derived from the plan, not the tap (#105). A mismatch is #105 on a real desk; paste both. | Known defect, INFERRED from code |
| Q6 | **Stacked-monitor jump** | On your current desk, with the guard active, use it normally. **If the Dock jumps:** immediately run `--diagnostics` and `status --live`, note the exact motion and arrangement, and send all three. | **UNVERIFIED — not claimed fixed.** Never reproduced on a current build. Nothing in 0.9.5 targets it. |

## 7. Rollback

**One Mac** (the build misbehaves): menu-bar icon ▸ **Quit**, then paste the block. Like 5.4, it stops at the first failure. It refuses if DockKeeper is running or the recorded backup is missing. 0.9.5 is moved aside to a new timestamped path, never over anything.

```sh
bash -euo pipefail <<'EOF'
[ -s ~/.dockkeeper-backups ] || { echo "REFUSING: no recorded backup in ~/.dockkeeper-backups."; exit 1; }
BACKUP=$(tail -n 1 ~/.dockkeeper-backups)
[ -d "$BACKUP" ] || { echo "REFUSING: recorded backup $BACKUP is missing."; exit 1; }
if pgrep -x DockKeeper >/dev/null; then echo "REFUSING: DockKeeper is still running. Quit it from the menu bar first."; exit 1; fi
ASIDE=~/DockKeeper-0.9.5-removed-$(date -u +%Y%m%dT%H%M%SZ).app
[ ! -e "$ASIDE" ] || { echo "REFUSING: $ASIDE already exists."; exit 1; }
if [ -e /Applications/DockKeeper.app ]; then mv /Applications/DockKeeper.app "$ASIDE"; fi
[ ! -e /Applications/DockKeeper.app ] || { echo "REFUSING: /Applications/DockKeeper.app is still present."; exit 1; }
mv "$BACKUP" /Applications/DockKeeper.app
echo "OK: restored $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/DockKeeper.app/Contents/Info.plist). 0.9.5 kept at $ASIDE"
EOF
```

Only if the block ends with `OK:`: `open /Applications/DockKeeper.app`.

If the Dock was left auto-hiding, use **Turn Off Dock Auto-Hide**, in the menu or in Preferences ▸ Advanced.

**The release** (the artifact is bad): mark it rather than silently delete it. Add a first line to the release notes: "WITHDRAWN: <reason>. Use 0.9.4." (`gh release edit v0.9.5 --notes-file <edited notes>`; `--notes` alone replaces the whole body). Or use `--draft` to hide it. The cask never pointed at it, so Homebrew users are unaffected. Fix forward as 0.9.6. Never re-tag v0.9.5 at a different commit.
