#!/bin/bash
#
# Build DockKeeper.app and launch it.
# Usage: Scripts/run-app.sh [debug|release]   (default: debug for a fast loop)
#
# The quit step is not hygiene — it is the fix for the defect this script had.
# LaunchServices keys its already-running check on the bundle's INODE identity,
# and build-app.sh does `rm -rf "$APP"` then rebuilds, so the freshly built
# bundle is a brand-new application to LaunchServices. Without the quit below,
# `open` LAUNCHES A SECOND PROCESS alongside the one still running, every single
# iteration. (Measured with a control: inode changed -> LAUNCH; inode unchanged
# -> REOPEN.) The single-instance guard (DK-FR-012) would then exit the new one,
# so the script would silently run nothing at all.
#
# Only the dist/ copy is terminated. Processes are matched by exact process name
# and then verified by executable path — never `pkill -f`: matched on the name it
# also kills /Applications/DockKeeper.app (the user's daily driver), and matched
# on the dist path it also kills any `codesign`, `lldb`, or `strip` invocation
# naming that path.

set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/DockKeeper.app"
EXEC="$APP/Contents/MacOS/DockKeeper"

# Pids of live processes running THIS worktree's dist binary, and nothing else.
# `pgrep -x` matches the accounting name exactly (so `dockkeeper-cli` and any
# `…DockKeeperHelper` are already out); `ps -o comm=` then reports the full
# executable path, which is what distinguishes the dist copy from an installed
# one at the same version.
dist_pids() {
    local pid
    for pid in $(pgrep -x DockKeeper 2>/dev/null || true); do
        if [[ "$(ps -o comm= -p "$pid" 2>/dev/null || true)" == "$EXEC" ]]; then
            echo "$pid"
        fi
    done
}

# Wait up to 2s for every dist pid to go away. Returns 1 if any survive.
# The wait is scoped to the dist pids: an installed copy running in parallel is
# legitimate and must not make this spin out its full timeout.
wait_for_dist_exit() {
    local _
    for _ in $(seq 1 20); do
        [[ -z "$(dist_pids)" ]] && return 0
        sleep 0.1
    done
    [[ -z "$(dist_pids)" ]]
}

quit_dist_instances() {
    local pid
    for pid in $(dist_pids); do
        echo "==> Terminating previous dist build (pid $pid)"
        kill "$pid" 2>/dev/null || true
    done
    wait_for_dist_exit && return 0

    # SIGTERM ignored, or the process is wedged. Escalate rather than proceed:
    # build-app.sh is about to `rm -rf` this bundle and `open` a fresh one, and a
    # survivor would deflect that launch (DK-FR-012), leaving the loop running
    # nothing at all — the exact outcome the header above says this step exists
    # to prevent. SIGKILL is safe here precisely because dist_pids is path-exact:
    # it can only ever name this worktree's dist binary, never an installed copy.
    for pid in $(dist_pids); do
        echo "==> pid $pid ignored SIGTERM after 2s; sending SIGKILL" >&2
        kill -9 "$pid" 2>/dev/null || true
    done
    wait_for_dist_exit && return 0

    echo "ERROR: previous dist build ($(dist_pids | tr '\n' ' ')) will not die." >&2
    echo "       Rebuilding now would launch a process that immediately deflects." >&2
    return 1
}

# The guard deflects our `open` if ANY other DockKeeper is live, and we
# deliberately refuse to kill an installed copy — it is the user's daily driver.
# Say so, because `open` detaches and the deflected process's stderr notice never
# reaches this terminal: without this the script would appear to succeed while
# changing nothing.
warn_about_other_instances() {
    local pid comm dist
    dist="$(dist_pids)"
    for pid in $(pgrep -x DockKeeper 2>/dev/null || true); do
        grep -qx "$pid" <<<"$dist" && continue
        comm="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
        echo "==> WARNING: another DockKeeper is running: pid $pid ($comm)" >&2
        echo "    DK-FR-012 will exit the build about to be launched. Quit it first, or:" >&2
        echo "      DOCKKEEPER_ALLOW_MULTIPLE_INSTANCES=1 open '$APP'" >&2
    done
}

quit_dist_instances
"$ROOT/Scripts/build-app.sh" "$CONFIG"
warn_about_other_instances
open "$APP"
