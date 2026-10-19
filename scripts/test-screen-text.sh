#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/eave-screen-text.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc DynamicIsland/managers/ScreenTextManager.swift tests/ScreenTextChecks.swift -o "$test_dir/checks"
"$test_dir/checks"
