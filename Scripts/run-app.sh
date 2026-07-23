#!/bin/bash
#
# Build DockKeeper.app and launch it.
# Usage: Scripts/run-app.sh [debug|release]   (default: debug for a fast loop)

set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT/Scripts/build-app.sh" "$CONFIG"
open "$ROOT/dist/DockKeeper.app"
