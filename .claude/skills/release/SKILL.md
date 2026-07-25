---
description: "Ship a new version of this project end to end: run the release gates, bump the version, build the artifacts, publish, tag, and verify."
---

# /release

Ship a new version of this project end to end: run the release gates, bump the version, build the artifacts, publish, tag, and verify. One command that encodes the project's release checklist so a release never skips a step or ships a broken build.

Use this **after** changes are merged and the working tree is clean. For diagnosing a *failed* publish or a broken local setup, use `/doctor`. For dependency upkeep before a release, use `/deps`.

## Arguments

- `$ARGUMENTS` — release configuration. Space-separated tokens:
  - First positional: version bump — `patch` | `minor` | `major` | an explicit version like `1.4.0` (default: `patch`).
  - `--dry-run` — run every gate and show what *would* happen, but do not bump, publish, tag, or push.
  - `--no-publish` — bump, build, tag locally, but skip the publish step (for a build-only or manual-publish release).
  - `--from=REF` — base ref for changelog/notes (default: the previous release tag).

Examples:
```
/release                  # patch release, full pipeline
/release minor
/release 2.0.0 --dry-run  # rehearse a major release
/release patch --no-publish
```

## Instructions

### 1. Preflight (stop on any failure)

Confirm the release can safely proceed. Abort with a clear message if any check fails:

- **Clean working tree** — no uncommitted or staged changes (`git status --porcelain` is empty). A release must build from committed state.
- **Correct branch** — on the release branch `main` and up to date with the remote (`git fetch` then compare).
- **Authenticated** — the publish credentials/registry login are present the Developer ID identity is in the keychain (`security find-identity -v -p codesigning` shows "Developer ID Application: … (PG8VP4PTGV)") and the `dockkeeper-notary` notarytool profile resolves (`xcrun notarytool history --keychain-profile dockkeeper-notary`). Both are owner-local — a release cannot run in CI or unattended..

State the resolved bump type and the current → next version before doing anything mutating.

### 2. Run the release gates

Run the project's full verification suite. **Every gate must pass** before the version is touched — a release must never ship red.

[docs/release-checklist.md](../../docs/release-checklist.md) §1 is the authoritative gate list and supersedes anything generic. At minimum:

```bash
swift build -c release
swift test
bash Scripts/build-app.sh release    # ad-hoc assembly must succeed
```

Plus the manual gates the checklist names — hardware matrix rows for this release's macOS versions, the CoreDock and screen-watcher smoke tests on the newest point release, and docs current per AGENTS rule 13. Manual gates cannot be inferred from a green CI run; if they have not been executed for this version, stop and say so.

If any gate fails, stop and report which one — do not continue to the bump.

### 3. Bump the version

Bump per the resolved type from step 1.

Version is stamped, not bumped by a tool: `VERSION=x.y.z Scripts/build-app.sh release` writes `CFBundleShortVersionString` and `CFBundleVersion` into the bundle's `Info.plist`. `Casks/dockkeeper.rb` carries `version` and `sha256` separately and must be updated in the same change. No tool creates a commit or tag — both are manual.

**If the release branch forbids direct pushes** (changes must land via PR), bump *without* auto-creating a tag — the tag is created on the merged commit in step 7, never locally, so it can't point at a commit that the squash/rebase merge will replace. Land the bump via PR and wait for it to merge before publishing. If direct pushes to the release branch are allowed, the bump may commit (and tag) in place.

### 4. Update release notes / changelog

Generate the release notes for the changes since `--from` (default: previous release tag). **Prefer the `/changelog` skill** — invoke it for the range (`/changelog --from=<prev tag> --version=<new version>`) and use its rendered section as the release notes. If `/changelog` is not installed, fall back to generating notes directly from merged PR titles / commit subjects in range.

Release notes live in the GitHub release body (there is no CHANGELOG.md). Use `/changelog` to draft it; user-facing behavior only, per checklist §2.

### 5. Build the release artifacts

Produce the exact artifacts that will be published — never publish from a stale build.

The full §3–§5 sequence, in this order — it is load-bearing:

```bash
export SIGNING_IDENTITY="Developer ID Application: Christopher Pishaki (PG8VP4PTGV)"
VERSION=x.y.z Scripts/build-app.sh release
Scripts/notarize.sh dist/DockKeeper.app          # staple the APP first
Scripts/package-dmg.sh
Scripts/notarize.sh dist/DockKeeper-x.y.z.dmg    # then the image
```

**Footgun:** the app must be stapled before packaging, or cask-installed copies carry no ticket and first launch needs Apple's Gatekeeper service. `package-dmg.sh` enforces this; `ALLOW_UNSTAPLED_APP=1` is for test builds only and must never produce a shipped artifact.

### 6. Publish

If `--dry-run` or `--no-publish`, skip this step and say so.

Publish only from the released state: if the bump landed via a PR (step 3), confirm that PR is **merged** and you have pulled and rebuilt from the updated release branch first — the published artifact must carry the bumped version, never a stale local tree.

Publish to the project's distribution target.

Publishing is a GitHub release plus the Homebrew cask — there is no package registry.

**Footgun that broke v0.9.0:** stapling rewrites the DMG. The `sha256` for `Casks/dockkeeper.rb` and the release notes must come from **`Scripts/notarize.sh`'s final line**, never from `package-dmg.sh`'s informational hash. Verify the value with `shasum -a 256` on the exact file you upload.

Notarization is interactive-ish and slow (two submissions, minutes each) and needs owner-local credentials — never retry blindly on failure; read the notary log the script prints.

Show the publish output in full — do not truncate it, so any auth URL, OTP prompt, or warning is visible to the user.

### 7. Tag and push

If `--dry-run`, skip. Otherwise tag the exact released commit:

- **Bump landed via PR:** the version bump is already in the release branch's history — create the annotated tag on that merged commit and push **only the tag**.
- **Direct-push repos:** commit the version bump if the bump tool did not, create the annotated tag, and push the commit and the tag together.

`origin main`. Direct pushes are allowed (no branch protection), but the working practice is branch + PR; push the tag once the release commit is on `main`.

Do not force-push.

### 8. Post-publish verification

Confirm the release is actually live and usable — a publish that "succeeded" can still be unconsumable.

- `xcrun stapler validate` passes on both the `.dmg` and, after installing, on `/Applications/DockKeeper.app`
- `brew install --cask` succeeds end to end including the `dockkeeper` CLI — this is where a wrong sha256 surfaces
- first launch on a clean machine **with networking off** opens without a Gatekeeper stall
- checklist §6 fresh-user pass completed

### 9. Report

Summarize concisely:

```markdown
## Released: <name> <new version>

- **Gates:** <pass/fail per gate>
- **Published:** <target> (or "skipped — --no-publish/--dry-run")
- **Tag:** <tag> pushed to <remote>
- **Verified:** <post-publish check result>
- **Notes:** <link or summary of changes shipped>
```

If `--dry-run`, make clear that nothing was bumped, published, tagged, or pushed.
