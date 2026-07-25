---
description: "Merge PRs, verify post-merge version bump, and run post-merge actions (build, deploy, etc.)."
---

# /merge

Merge PRs, verify post-merge version bump, and run post-merge actions (build, deploy, etc.).

## Arguments

- `$ARGUMENTS` - PR numbers, `all`, or flags:
  - `123` or `123 456` — specific PR(s)
  - `all` — all open PRs targeting main
  - `--no-package` — skip the post-merge packaging check
  - `--package-only` — run the post-merge packaging check on current main without merging
  - `--skip-version-check` — don't wait for auto-version CI

## Instructions

### Phase 0: Mandatory Review Gate

**CRITICAL: Every PR MUST be reviewed before merging. No exceptions for "obvious" fixes.**

For each PR to be merged, check if `/full-review` has already been run:

```bash
# Check for existing review comments (agent-review posts a structured review)
gh api repos/${REPO}/issues/${PR_NUM}/comments --jq '[.[] | select(.body | test("Code Review|Review Comments Addressed"))] | length'
```

If no review exists, run `/full-review ${PR_NUM}` **before proceeding to merge**. For multiple PRs, run reviews in parallel (background agents), then merge sequentially after all reviews complete.

Documentation-only changes (`docs/**`, `*.md`) with no changes under `Sources/`, `Tests/`, `Scripts/`, `Resources/`, or `Casks/` may skip review. Anything touching the packaging scripts may not — two shipped releases have been broken by packaging changes that looked trivial.

### Phase 1: Pre-Merge Preparation

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

If the post-merge-only flag is set, skip to Phase 3.

Parse PR numbers from arguments. For `all`:

```bash
gh pr list --base main --state open --json number,title,headRefName,mergeStateStatus
```

For each PR, pre-check:

```bash
# CI status
gh pr checks ${PR_NUM}

# Merge state
gh pr view ${PR_NUM} --json mergeable,mergeStateStatus
```

Display summary table (no confirmation gate — user invoked the command explicitly):

```markdown
## Merge Queue ({N} PRs)

| # | PR | Title | CI | Merge State |
|---|-----|-------|----|-------------|
| 1 | #123 | feat: add feature | PASS | CLEAN |
```

### Phase 2: Merge Execution

#### Small batch (1-2 PRs): Direct merge

For each PR:

1. **Check CI** — if any checks are pending, poll every 30s up to 3 min. If failed, run `/fix-ci` once and retry.
2. **Check merge state** — if BLOCKED, diagnose:

   | Error Pattern | Action | Max Retries |
   |---|---|---|
   | "not up to date" / "branch is behind" | `gh api repos/${REPO}/pulls/${PR_NUM}/update-branch -X PUT`, wait for CI, retry | 1 |
   | "status check" / "required status" | `/fix-ci`, retry | 1 |
   | "review" / "unresolved threads" | Resolve via GraphQL (see below), retry | 1 |
   | "conflict" / "not mergeable" | Skip, report conflict | 0 |
   | "already merged" | Skip silently | 0 |
   | Rate limit (403/429) | Back off 60s, retry | 2 |
   | Unknown | Log error, skip | 0 |

3. **Resolve review threads** if blocking merge:

   ```python
   # MUST use Python — bash corrupts Base64 thread IDs in GraphQL mutations
   python3 -c "
   import subprocess, json
   result = subprocess.run(['gh', 'api', 'graphql', '-f',
     'query={repository(owner:\"OWNER\",name:\"REPO\"){pullRequest(number:PR_NUM){reviewThreads(first:50){nodes{id,isResolved}}}}}'],
     capture_output=True, text=True)
   data = json.loads(result.stdout)
   for t in [x for x in data['data']['repository']['pullRequest']['reviewThreads']['nodes'] if not x['isResolved']]:
       mutation = 'mutation { resolveReviewThread(input: {threadId: \"' + t['id'] + '\"}) { thread { isResolved } } }'
       subprocess.run(['gh', 'api', 'graphql', '-f', f'query={mutation}'], capture_output=True, text=True)
   "
   ```

4. **Squash merge:**
   ```bash
   # gh pr merge ${PR_NUM} --squash --delete-branch
   gh pr merge ${PR_NUM} --squash --delete-branch
   ```

5. **Verify:** `gh pr view ${PR_NUM} --json state -q .state` should be `MERGED`

#### Large batch (3+ PRs): Delegate to /batch-merge

Run `/batch-merge ${PR_NUMS}` — it handles sequential merge with update-branch, CI waiting, Copilot gating, and conflict resolution. After delegation completes, continue to Phase 2b with the list of successfully merged PRs.

### Phase 2b: Version Verification

This repo has no automated version bump. The version lives in two places and is set by hand at release time, not at merge time:
`Resources/Info.plist` (`CFBundleShortVersionString` / `CFBundleVersion`, stamped via `VERSION=x.y.z Scripts/build-app.sh`) and `Casks/dockkeeper.rb` (version + sha256).
Merging does not bump anything — skip version verification unless the merged PR itself claimed a version change, in which case check those two files agree.

After merging, ask the user if they want to bump the version:

```
Current version: vX.Y.Z
Bump version? (patch → vX.Y.(Z+1), or skip)
```

If yes:

```bash
# # No bump command — version is stamped at release time via VERSION=x.y.z Scripts/build-app.sh
bash scripts/bump-version.sh
git checkout -b chore/bump-version main
git add [version files]
NEXT=[read new version]
git commit -m "chore: bump version to v${NEXT}"
git push -u origin chore/bump-version
gh pr create --title "chore: bump version to v${NEXT}" --body "Patch version bump."
```

Merge after CI passes (version-only change, review gate exception).

If `--skip-version-check` is set, skip this phase.

### Phase 3: Post-Merge Actions

**Skip conditions:**
- Post-merge skip flag is set
- No PRs were merged (all skipped/blocked)
- Skip the post-merge check when the merged PRs touch only `docs/`, `.github/`, `.claude/`, or `*.md` — none of those affect the build.

Post-merge check for this repo is a build, not a deploy — there is no server and no registry to push to:

```bash
git checkout main && git pull
swift build -c release          # both products must compile
swift test                      # unit suite
bash Scripts/build-app.sh release   # ad-hoc bundle still assembles
```

A full signed/notarized release is a separate, deliberate act — see [docs/release-checklist.md](../../docs/release-checklist.md) and `/release`. Never notarize or publish as a post-merge side effect.

#### Step 3a: Pull latest main

```bash
git checkout main
git pull --ff-only origin main
# If fast-forward fails (divergent from stale cherry-picks/worktrees):
# git reset --hard origin/main
```

Verify local version matches the auto-versioned remote:
```bash
# /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist
echo "Local version: $(node -p \"require('./packages/server/package.json').version\")"
```

#### Step 3b–N: [Repo-specific build/deploy steps]

_Replace with your repo's post-merge workflow._

### Phase 4: Report

```markdown
## Merge Complete

| PR | Title | Status |
|----|-------|--------|
| #123 | feat: add feature | Merged |
| #456 | fix: resolve crash | Skipped (conflict) |

**Version:** v1.2.3 → v1.2.4
**Post-merge:** `swift build -c release` + `swift test` + ad-hoc bundle assembly green on main
```

## Error Recovery

| Error | Recovery |
|---|---|
| CI failure on PR | Run `/fix-ci`, wait, retry merge |
| Unresolved review threads | Resolve via GraphQL Python script, retry |
| Merge conflict | Skip PR, report to user |
| Version bump timeout | Warn and continue to post-merge actions |
| Post-merge build failure | Report error, suggest manual intervention |
| Divergent local branches | `git reset --hard origin/main` |

## Critical Rules

1. **NEVER merge without /full-review** — every PR must be reviewed before merging. This is a hard gate. Run Phase 0 first.
2. **For 3+ PRs, delegate to /batch-merge** — don't reinvent sequential merge logic
3. **Version verification is informational** — never block post-merge actions on it
3. **GraphQL resolveReviewThread must use Python** — bash corrupts Base64 thread IDs
4. **Never use --admin** — respect branch protections
5. **Idempotent** — safe to re-run; already-merged PRs detected and skipped
6. **No attribution** — Zero Attribution Policy applies to all commits
7. **No release side effects** — merging never notarizes, tags, or publishes. Releases run deliberately through the checklist.
8. **Packaging changes get a real review** — `Scripts/*.sh` and `Casks/dockkeeper.rb` are release-critical; the documentation-only skip never applies to them.
