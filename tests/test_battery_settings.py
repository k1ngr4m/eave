"""Run with python3 tests/test_battery_settings.py on macOS."""
from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'DynamicIsland/components/Settings/SettingsView.swift').read_text()
navigation = source.split('private enum SettingsTabGroup:', 1)[1]
navigation = 'private enum SettingsTabGroup:' + navigation.split('final class SettingsHighlightCoordinator:', 1)[0]
with tempfile.TemporaryDirectory() as directory:
    main = Path(directory) / 'main.swift'
    main.write_text('import SwiftUI\n' + navigation + '''
assert(!SettingsTab.allCases.contains { $0.rawValue == "battery" })
let titles = ["Show battery alerts", "Play low battery alert sound",
              "Show charging HUD", "Show low battery HUD", "Show fully charged HUD",
              "Charging duration", "Low battery duration", "Full battery duration",
              "Test charging HUD", "Test low battery HUD", "Test full battery HUD",
              "Low battery style", "Low battery threshold", "Full battery style", "Full charge threshold"]
for title in titles {
    let matches = SettingsSearchIndex.entries.filter { $0.title == title }
    assert(matches.count == 1)
    assert(matches[0].tab == .liveActivities)
    assert(matches[0].highlightID == SettingsTab.liveActivities.highlightID(for: title))
}
''')
    subprocess.run(['swift', str(main)], check=True)

catalog = json.loads((root / 'DynamicIsland/Localizable.xcstrings').read_text())['strings']
for title in ['Show battery alerts', 'Battery Alerts', 'Charging Alert', 'Low Battery Alert', 'Full Battery Alert']:
    for language in ['zh-Hans', 'zh-Hant']:
        assert catalog[title]['localizations'][language]['stringUnit']['value']
print('Battery settings navigation, search destinations and translations passed.')
