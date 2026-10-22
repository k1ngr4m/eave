"""Run with python3 tests/test_focus_system_state.py (requires Swift/macOS)."""
from pathlib import Path
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[1] / 'DynamicIsland/managers/DoNotDisturbManager.swift').read_text()
parser = 'struct FocusSystemState {' + source.split('struct FocusSystemState {', 1)[1].split('private final class FocusLogStream', 1)[0]
with tempfile.TemporaryDirectory() as directory:
    main = Path(directory) / 'main.swift'
    main.write_text('import Foundation\n' + parser + r'''
let prefix = "Did receive state update, will handle; stateUpdate=<DNDStateUpdate: reason: automation; source: cloud; state: <DNDState: "
let work = "activeModeConfiguration: <DNDMutableModeConfiguration: mode: <DNDMode: name: 工作; modeIdentifier: com.apple.focus.work; >; >; activeModeIdentifier: com.apple.focus.work>"
let off = "suppressionState: off; activeModeConfiguration: (null); activeModeIdentifier: (null)>"
let active = FocusSystemState.parse(prefix + work + "; previousState: <DNDState: " + off)!
assert(active.isActive && active.identifier == "com.apple.focus.work" && active.name == "工作")
let inactive = FocusSystemState.parse(prefix + off + "; previousState: <DNDState: " + work)!
assert(!inactive.isActive && inactive.name == nil)
let custom = work.replacingOccurrences(of: "com.apple.focus.work", with: "com.apple.donotdisturb.mode.custom")
assert(FocusSystemState.parse(prefix + custom)!.identifier == "com.apple.donotdisturb.mode.custom")
assert(FocusSystemState.parse(prefix + "activeModeIdentifier: <private>>") == nil)
assert(FocusSystemState.parse(prefix + "activeModeConfiguration: <private>; previousState: <DNDState: " + work) == nil)
assert(FocusSystemState.parse("unrelated " + work) == nil)
if CommandLine.arguments.count > 1 {
    let logs = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
    let latest = logs.components(separatedBy: "\n").reversed().compactMap { FocusSystemState.parse($0) }.first!
    print("Latest system Focus:", latest.isActive, latest.identifier ?? "none", latest.name ?? "none")
}
print("Focus state regression checks passed")
''')
    import sys
    subprocess.run(['swift', str(main), *sys.argv[1:]], check=True)
