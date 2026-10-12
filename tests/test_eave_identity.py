"""Run with python3 tests/test_eave_identity.py; no Xcode or network required."""
import json
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'DynamicIsland'
project = (ROOT / 'DynamicIsland.xcodeproj/project.pbxproj').read_text()
assert project.count('PRODUCT_NAME = Eave;') == 2
for identifier in ('com.eave.app', 'com.eave.app.dev', 'com.eave.app.tests', 'com.eave.app.uitests'):
    assert f'PRODUCT_BUNDLE_IDENTIFIER = {identifier};' in project, identifier
assert project.count('$(BUILT_PRODUCTS_DIR)/Eave.app/Contents/MacOS/Eave') == 2
assert 'Atoll.app' not in project
for path in (ROOT / 'DynamicIslandTests').glob('*.swift'):
    assert '@testable import Atoll' not in path.read_text(), path

info = plistlib.loads((APP / 'Info.plist').read_bytes())
assert not any(key.startswith('SU') for key in info), 'An update feed or Sparkle configuration returned'
swift = '\n'.join(path.read_text() for path in APP.rglob('*.swift'))
assert not re.search(r'SPUStandardUpdaterController\s*\(', swift), 'Updater must never be instantiated'
assert not re.search(r'\b(?:CheckForUpdatesView|UpdaterSettingsView)\s*\(', swift), 'Update UI is reachable'
assert 'appcast' not in (APP / 'models/UpdateChannel.swift').read_text()
assert 'ForEach(UpdateChannel.availableChannels)' not in swift
for name in ('release', 'mirror-release', 'nightly-merge'):
    assert not (ROOT / f'.github/workflows/{name}.yml').exists(), name
    assert (ROOT / f'.github/workflows/{name}.yml.disabled').is_file(), name

for old_path in ('"DynamicIsland/IdleAnimations"', 'appendingPathComponent("DynamicIsland"',
                 'documentsPath.appendingPathComponent("ClipboardData")',
                 'documentsPath.appendingPathComponent("NoteImages")',
                 'documentsPath.appendingPathComponent("ScreenAssistantAudio")',
                 'documentsPath.appendingPathComponent("ScreenAssistantScreenshots")',
                 'static let mainDir = "CopiedItems"', '"AtollExtensions"', '"AtollExtensionFiles"', '"atoll_wallpaper_backup.plist"'):
    assert old_path not in swift, old_path
for name in ('MediaControllers/CiderTokenStore.swift', 'managers/Spotify/SpotifyTokenStore.swift',
             'managers/LLMUsage/NewAPIUsage.swift'):
    text = (APP / name).read_text()
    assert 'private static let service = "com.eave.app.' in text, name
for name in ('services/Extensions/EaveDistributedNotifications.swift',
             'managers/Extensions/ExtensionEventBridge.swift'):
    assert 'Notification.Name("com.ebullioscopic.Atoll.' not in (APP / name).read_text(), name

# The third-party SDK and wire endpoints intentionally retain their original identity.
assert 'productName = AtollExtensionKit;' in project
assert 'static let machServiceName = "com.ebullioscopic.Atoll.xpc"' in swift
assert 'case "atoll.getVersion":' in swift
assert 'static let rpcPort: UInt16 = 9020' in swift
assert 'static let redirectURI = "atoll-spotify://oauth-callback"' in swift
assert 'EaveNotchExperienceDescriptor' not in swift
for path in (ROOT / 'Localizable.xcstrings', APP / 'Localizable.xcstrings'):
    strings = json.loads(path.read_text())['strings']
    for key in (('Eave', 'Eave Settings', 'Restart Eave') if path.parent == APP else ('Eave',)):
        assert key in strings, (path, key)
        for language in strings[key].get('localizations', {}).values():
            assert 'Atoll' not in json.dumps(language), (path, key)
print('Eave identity, storage isolation, disabled updates, and compatibility checks passed.')
