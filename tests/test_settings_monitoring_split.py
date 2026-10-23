"""Run with python3 tests/test_settings_monitoring_split.py (requires Swift/macOS)."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'DynamicIsland/components/Settings/SettingsView.swift').read_text()
navigation = 'private enum SettingsTabGroup:' + source.split('private enum SettingsTabGroup:', 1)[1].split('final class SettingsHighlightCoordinator:', 1)[0]
registry = 'private struct SettingsModule:' + source.split('private struct SettingsModule:', 1)[1].split('private struct MenuBarSettings:', 1)[0]
registrations = source.split('static func appModules()', 1)[1].split('static func feature<', 1)[0]
# Use the production declarations, replacing only app services and page builders
# with in-memory switches and inert views. Never touch the user's preferences.
ids = re.findall(r'(?:SettingsModule|feature)\(\.(\w+)', registrations)
restricted = re.findall(r'feature\(\.(\w+),[^\n]+supportsMinimalMode: false', registrations)
kinds = dict(re.findall(r'SettingsModule\(\.(\w+), kind: \.(\w+)', registrations))
features = re.findall(r'feature\(\.(\w+),', registrations) + ['clipboard', 'desktopPing']
assert len(ids) == len(set(ids))
assert set(restricted) == {'timer', 'stats', 'llmAgents', 'stocks', 'shelf', 'notes', 'terminal', 'developerTools'}
fixtures = []
for name in ids:
    if name in features:
        fixtures.append(f'''SettingsModule(.{name}, kind: .toggleable, enabled: Binding(get: {{ values[.{name}]! }}, set: {{ values[.{name}] = $0; changes.send(()) }}), supportsMinimalMode: {str(name not in restricted).lower()}, changes: changes.eraseToAnyPublisher()) {{ builtPages += 1; return EmptyView() }}''')
    else:
        fixtures.append(f'SettingsModule(.{name}, kind: .{kinds[name]}) {{ builtPages += 1; return EmptyView() }}' )
checks = '''
private var values: [SettingsTab: Bool] = Dictionary(uniqueKeysWithValues: SettingsTab.allCases.map { ($0, true) })
private var builtPages = 0
private let changes = PassthroughSubject<Void, Never>()
private let registry = SettingsModuleRegistry(modules: [FIXTURES])
private let primaryTabs: [SettingsTab] = [.liveActivities, .menuBar, .lockScreen]
assert(builtPages == 0, "Pages must be created lazily")
assert(Set(registry.modules.map(\.id)) == Set(SettingsTab.allCases.filter { $0 != .features }))
private let original = values
for minimal in [false, true] {
    let sidebar = registry.sidebarTabs(minimal: minimal)
    assert(sidebar.prefix(6) == [.general, .appearance, .features] + primaryTabs)
    assert(Set(sidebar).count == sidebar.count, "Sidebar destinations must not repeat")
    assert(sidebar.suffix(2) == [.shortcuts, .about])
    for module in registry.features {
        assert(sidebar.contains(module.id) == (!minimal || module.supportsMinimalMode))
        assert(registry.requiresGallery(module.id, minimal: minimal) == (minimal && !module.supportsMinimalMode))
        assert(registry.search(module.title).contains { $0.tab == module.id })
    }
}
assert(values == original, "Mode policy must not overwrite feature switches")
private var notifications = 0
private let observation = registry.objectWillChange.sink { notifications += 1 }
for module in registry.features {
    module.enabled!.wrappedValue = false
    assert(!registry.sidebarTabs(minimal: false).contains(module.id))
    assert(registry.requiresGallery(module.id, minimal: false))
    assert(registry.search(module.title).contains { $0.tab == module.id })
}
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
assert(notifications > 0, "Existing settings changes must refresh navigation")
observation.cancel()
assert(registry.enabledIDs.isEmpty)
for module in registry.modules where module.kind == .configuration || primaryTabs.contains(module.id) {
    assert(registry.sidebarTabs(minimal: true).contains(module.id))
}
for module in registry.features { module.enabled!.wrappedValue = true }
assert(values == original)
assert(registry.search("  ").isEmpty)
for entry in SettingsSearchIndex.entries {
    let matches = registry.search("  " + entry.title + "  ")
    assert(matches.contains { $0.id == entry.id }, entry.title)
    assert(Set(matches.map(\.id)).count == matches.count)
}
for title in ["Show lock screen media panel", "Show lock screen timer", "Show lock screen reminder",
              "Show next calendar event", "Always show volume control", "Enable album art parallax"] {
    let matches = SettingsSearchIndex.entries.filter { $0.title == title }
    assert(matches.count == 1 && matches[0].tab == .lockScreen, title)
    assert(matches[0].highlightID == SettingsTab.lockScreen.highlightID(for: title))
}
assert(SettingsSearchIndex.entries.first { $0.title == "Enable minimalistic UI" }?.tab == .features)
assert(registry.appearancePages.map(\.id) == [.appearance, .interaction])
for id: SettingsTab in [.liveActivities, .menuBar, .lockScreen, .media, .calendar, .devices, .hudAndOSD] {
    let isPrimary = primaryTabs.contains(id)
    assert(registry.module(id)?.kind == (isPrimary ? .core : .configuration))
    assert(registry.module(id)?.enabled == nil)
    assert(registry.galleryModules.contains { $0.id == id } == !isPrimary)
    if isPrimary { assert(id.group == .core) }
    assert(id.sidebarTab == id, "Search must highlight its own destination")
    assert(registry.search(id.title).contains { $0.tab == id })
    for minimal in [true, false] {
        assert(registry.sidebarTabs(minimal: minimal).contains(id))
        assert(!registry.requiresGallery(id, minimal: minimal))
    }
}
for module in registry.modules {
    assert(registry.galleryModules.contains { $0.id == module.id } == (module.kind != .core))
}
assert(!registry.requiresGallery(.lockScreen, minimal: true))
_ = registry.module(.stats)!.makeSettings()
assert(builtPages == 1)
print("Registry, enabled sidebar, full search, mode policy, observation and lazy builder checks passed.")
'''.replace('FIXTURES', ',\n'.join(fixtures))
with tempfile.TemporaryDirectory() as directory:
    main = Path(directory) / 'main.swift'
    main.write_text('import SwiftUI\nimport Combine\n' + navigation + registry + '\nMainActor.assumeIsolated {\n' + checks.replace('private ', '') + '\n}\n')
    subprocess.run(['swift', str(main)], check=True)

assert 'hiddenSettingsTools' not in source
for key in ('alwaysShowLockScreenVolume', 'lockScreenMusicAlbumParallaxEnabled',
            'enableLockScreenMediaWidget', 'enableLockScreenTimerWidget',
            'enableLockScreenReminderWidget', 'lockScreenShowCalendarEvent'):
    assert source.count('Defaults.Toggle(key: .' + key + ')') == 1, key
print('Canonical lock-screen setting ownership checks passed.')

assert 'LockScreenSettingsSection' not in source
assert 'visibleSection' not in source
