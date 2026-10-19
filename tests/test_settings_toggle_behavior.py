"""Run with python3 tests/test_settings_toggle_behavior.py (Swift/macOS)."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
settings = root / 'DynamicIsland/components/Settings'
source = (settings / 'SettingsView.swift').read_text()
hud = source.split('private struct HUDAndOSDSettingsView:', 1)[1]
hud = hud.split('private struct ExternalDisplayIntegrationsSection:', 1)[0]
binding = hud.split('    private var hudEnabled:', 1)[1].split('    private var paneBackgroundColor:', 1)[0]
actions = re.findall(r'action: \{\s*(let wasEnabled = hudEnabled.wrappedValue.*?hudEnabled.wrappedValue = wasEnabled)\s*\}', hud, re.S)
assert len(actions) == 4
ping = (settings / 'DesktopPingSettings.swift').read_text()
sound = ping.split('Toggle("Play desktop sounds", isOn: Binding(', 1)[1].split('))', 1)[0]

# Execute the bindings and card actions extracted from the UI, including persisted muted values.
program = '''import SwiftUI
final class HUDCheck {
    enum Tab: CaseIterable { case hud, osd, vertical, circular }
    var selectedTab: Tab = .hud
    var enableSystemHUD = false
    var enableCustomOSD = false
    var enableVerticalHUD = false
    var enableCircularHUD = false
    var hudEnabled:''' + binding + '''
    var flags: [Bool] { [enableSystemHUD, enableCustomOSD, enableVerticalHUD, enableCircularHUD] }
    func select(_ tab: Tab) {
        switch tab {
''' + '\n'.join('case .' + tab + ':\n' + action for tab, action in zip(['hud', 'osd', 'vertical', 'circular'], actions)) + '''
        }
    }
}
struct Configuration { var muted = false }
final class Manager { var configuration = Configuration() }
let manager = Manager()
let sound = Binding<Bool>(
''' + sound + ''')
for initiallyMuted in [false, true] {
    manager.configuration.muted = initiallyMuted
    assert(sound.wrappedValue == !initiallyMuted)
    sound.wrappedValue = true
    assert(!manager.configuration.muted)
    sound.wrappedValue = false
    assert(manager.configuration.muted)
}
let check = HUDCheck()
assert(!check.hudEnabled.wrappedValue)
for enabled in [false, true] {
    check.hudEnabled.wrappedValue = enabled
    for (index, tab) in HUDCheck.Tab.allCases.enumerated() {
        check.select(tab)
        assert(check.hudEnabled.wrappedValue == enabled)
        assert(check.flags == (0..<4).map { enabled && $0 == index })
        check.hudEnabled.wrappedValue = false
        assert(check.flags.allSatisfy { !$0 })
        check.hudEnabled.wrappedValue = true
        assert(check.flags == (0..<4).map { $0 == index })
        check.hudEnabled.wrappedValue = enabled
    }
}
print("Settings HUD and sound binding checks passed.")
'''
with tempfile.TemporaryDirectory() as directory:
    main = Path(directory) / 'main.swift'
    main.write_text(program)
    subprocess.run(['swift', str(main)], check=True)
