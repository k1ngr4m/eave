#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/eave-clipboard.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc DynamicIsland/components/Clipboard/ClipboardHistory.swift DynamicIsland/components/Clipboard/ClipboardHistoryStore.swift tests/ClipboardHistoryChecks.swift -o "$test_dir/checks"
"$test_dir/checks"
