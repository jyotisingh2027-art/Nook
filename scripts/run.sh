#!/bin/bash
# Quits any running Nook, rebuilds it, and opens the new version.
set -euo pipefail
cd "$(dirname "$0")/.."
pkill -x Nook 2>/dev/null || true
./scripts/build.sh
open build/Nook.app
