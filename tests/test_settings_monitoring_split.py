"""Run with python3 tests/test_settings_monitoring_split.py (requires Swift/macOS)."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'DynamicIsland/components/Settings/SettingsView.swift').read_text()
navigation = source.split('private enum SettingsTabGroup:', 1)[1]
navigation = 'private enum SettingsTabGroup:' + navigation.split('final class SettingsHighlightCoordinator:', 1)[0]

# Run the actual selection/search implementation without launching app services.
selection = source.split('    private var resolvedSelection:', 1)[1].split('    @ToolbarContentBuilder', 1)[0]
tabs = source.split('    private var availableTabs:', 1)[1].split('    /// Groups the filtered tabs', 1)[0]
search = source.split('    private func searchEntries(', 1)[1].split('    @ViewBuilder\n    private func detailView', 1)[0]
logic = ('private struct SearchCheck {\n'
         'var selectedTab: SettingsTab = .general\nvar enableMinimalisticUI = false\n'
         + 'var resolvedSelection:' + selection
         + 'var availableTabs:' + tabs
         + 'func searchEntries(' + search.replace('private ', '') + '\n}\n')

with tempfile.TemporaryDirectory() as directory:
    main = Path(directory) / 'main.swift'
    main.write_text('import SwiftUI\n' + navigation + logic + '''
private var check = SearchCheck()
for minimal in [false, true] {
    check.enableMinimalisticUI = minimal
    for tab in SettingsTab.allCases {
        check.selectedTab = tab
        assert(check.resolvedSelection == (check.availableTabs.contains(tab) ? tab : .general))
    }
    assert(check.searchEntries(matching: "  ").isEmpty)
    for entry in SettingsSearchIndex.entries {
        let results = check.searchEntries(matching: "  " + entry.title + "  ")
        assert(results.contains { $0.id == entry.id } == check.availableTabs.contains(entry.tab))
        assert(results.allSatisfy { check.availableTabs.contains($0.tab) })
    }
}
check.enableMinimalisticUI = false
private let utilities: [SettingsTab] = [.media, .timer, .calendar, .notes, .shelf, .stocks, .desktopPing, .screenText, .stats, .llmAgents, .terminal]
assert(check.availableTabs.filter { $0.group == .utilities } == utilities)
assert(SettingsTabGroup.allCases == [.core, .utilities, .displayAndSystem, .info])
private let displayAndSystem: [SettingsTab] = [.liveActivities, .lockScreen, .devices, .hudAndOSD, .battery]
assert(check.availableTabs.filter { $0.group == .displayAndSystem } == displayAndSystem)
assert(check.availableTabs.firstIndex(of: .terminal)! < check.availableTabs.firstIndex(of: .liveActivities)!)
assert(SettingsTab.stats.group == .utilities)
assert(SettingsTab.llmAgents.group == .utilities)
private let expected: [(SettingsTab, [String])] = [
    (.stats, ["Enable system stats monitoring", "Stop monitoring after closing the notch",
              "CPU Usage", "Temperature unit", "Memory Usage", "GPU Usage", "Network Activity", "Disk I/O", "Show network widget when collapsed"]),
    (.llmAgents, ["Enable LLM Usage Monitor", "Claude Provider", "Codex Provider", "Cursor Provider",
                  "Antigravity Provider", "New API Provider", "New API Accounts"])
]
for (tab, titles) in expected {
    for title in titles {
        let matches = SettingsSearchIndex.entries.filter {
            $0.title == title && ($0.tab == .stats || $0.tab == .llmAgents)
        }
        assert(matches.count == 1, title)
        assert(matches[0].tab == tab, title)
        assert(matches[0].highlightID == tab.highlightID(for: title), title)
    }
}
print("Monitoring and LLM settings navigation checks passed.")
''')
    subprocess.run(['swift', str(main)], check=True)
