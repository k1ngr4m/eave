#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/eave-note-checks.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
# Use the actual encoder without running AppleScript or touching the user's Notes.
python3 - "$test_dir/SyncEncodingProbe.swift" <<'PY'
from pathlib import Path
import sys
source = Path('DynamicIsland/managers/AppleNotesSyncManager.swift').read_text()
body = source.split('    private func htmlBody(for note: NoteItem) -> String {', 1)[1].split('    private func appleScriptEscape', 1)[0]
Path(sys.argv[1]).write_text('import Foundation\nstruct NoteItem { let id: UUID; let content: String }\nstruct SyncEncodingProbe {\nfunc htmlBody(for note: NoteItem) -> String {' + body + '}\n')
PY
xcrun swiftc DynamicIsland/helpers/NoteMarkdown.swift "$test_dir/SyncEncodingProbe.swift" \
    tests/NoteMarkdownChecks.swift -o "$test_dir/checks"
"$test_dir/checks"

# Exercise the actual SwiftUI editor in an isolated window, with in-memory notes.
python3 - "$test_dir/NoteEditorView.swift" <<'PY'
from pathlib import Path
import sys
source = Path('DynamicIsland/components/Notch/NotchNotesView.swift').read_text()
editor = 'struct NoteEditorView: View {' + source.split('struct NoteEditorView: View {', 1)[1]
editor = editor.replace('Defaults[.enableNoteCharCount]', 'false').replace('Color.notchBackground', 'Color.black')
Path(sys.argv[1]).write_text('import SwiftUI\n' + editor)
PY
xcrun swiftc DynamicIsland/helpers/NoteMarkdown.swift \
    DynamicIsland/components/Notch/NoteMarkdownPreview.swift "$test_dir/NoteEditorView.swift" \
    tests/NoteEditorInteractionChecks.swift -o "$test_dir/editor-checks"
"$test_dir/editor-checks"
