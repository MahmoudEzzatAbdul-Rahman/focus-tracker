#!/usr/bin/env bash
# Runs the unit tests. With only Command Line Tools installed (no Xcode), the Swift Testing
# macro plugin lives in a subdirectory the compiler doesn't search, so point it there.
set -euo pipefail

cd "$(dirname "$0")/.."
PLUGIN_DIR="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
if [[ -d "$PLUGIN_DIR" ]]; then
  swift test -Xswiftc -plugin-path -Xswiftc "$PLUGIN_DIR" "$@"
else
  swift test "$@"
fi
