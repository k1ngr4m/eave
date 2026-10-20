#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/eave-clipboard.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc DynamicIsland/components/Clipboard/ClipboardHistory.swift DynamicIsland/components/Clipboard/ClipboardHistoryStore.swift tests/ClipboardHistoryChecks.swift -o "$test_dir/checks"
"$test_dir/checks"

python3 - <<'PYTHON'
import json
import re
from pathlib import Path

catalog = json.loads(Path("DynamicIsland/Localizable.xcstrings").read_text())["strings"]
keys = set()
for path in Path("DynamicIsland/components/Clipboard").glob("*.swift"):
    for literal in re.findall(r'String\(localized: "((?:\\.|[^"\\])*)"', path.read_text()):
        key = re.sub(r'\\\(([^)]*)\)', lambda match: "%lld" if ".count" in match[1] or match[1].startswith("index") or match[1] in ("$0", "count") else "%@", literal)
        keys.add(key)
        assert key in catalog, (path, key)
        for language in ("zh-Hans", "zh-Hant"):
            localized = catalog[key]["localizations"][language]["stringUnit"]["value"]
            assert localized and sorted(re.findall(r"%[@a-z]+", key)) == sorted(re.findall(r"%[@a-z]+", localized)), (key, language)
for key in ("%lld items", "%lld characters", "%lld days", "%lld weeks", "%lld months", "%lld files"):
    forms = catalog[key]["localizations"]["en"]["variations"]["plural"]
    assert forms["one"]["stringUnit"]["value"] != forms["other"]["stringUnit"]["value"]
assert len(keys) >= 80
print(f"Clipboard localization checks passed: {len(keys)} keys, Chinese translations, placeholders, and English plurals.")
PYTHON
