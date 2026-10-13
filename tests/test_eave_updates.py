"""Offline checks of update ordering and draft-before-public release integrity."""
import argparse
import json
from pathlib import Path
import plistlib
import sys
import tempfile
from unittest.mock import patch
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import eave_release as release
from eave_version import stamp, version_parts


def rejected(action):
    try:
        action()
    except ValueError:
        return
    raise AssertionError('Unsafe operation accepted')


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    # Different machines have unrelated counters; the installation version must
    # still increase. Same-version rebuilds deliberately remain the same version.
    output = root / 'Info.plist'
    output.write_bytes(plistlib.dumps({}))
    counters = root / 'machine-a'
    counters.mkdir()
    (counters / 'release').write_text('900')
    (root / 'VERSION').write_text('0.1.0')
    stamp(root, output, 'release', counters)
    old = plistlib.loads(output.read_bytes())
    (root / 'VERSION').write_text('0.1.1')
    stamp(root, output, 'release', root / 'machine-b')
    new = plistlib.loads(output.read_bytes())
    assert int(new['EaveBuildNumber']) < int(old['EaveBuildNumber'])
    assert version_parts(new['CFBundleVersion']) > version_parts(old['CFBundleVersion'])
    stamp(root, output, 'release', root / 'machine-b')
    assert plistlib.loads(output.read_bytes())['CFBundleVersion'] == new['CFBundleVersion']

    existing = [{'tag_name': 'v0.1.1', 'draft': False, 'prerelease': False}]
    for version in ('0.1.0', '0.1.1', '0.1.2-beta', '../bad'):
        rejected(lambda: release.available_version(version, existing))
    release.available_version('0.1.2', existing)
    rejected(lambda: release.available_version('0.1.2', [{'tag_name': 'v0.1.2', 'draft': True}]))

    prepared = root / 'build/release-0.1.2'
    prepared.mkdir(parents=True)
    package = prepared / 'Eave-0.1.2.zip'
    package.write_bytes(b'test package')
    feed = prepared / 'appcast.xml'
    feed.write_bytes(release.appcast('0.1.2', package, 'test-signature', '14.0'))
    item = ET.fromstring(feed.read_bytes()).find('channel/item')
    assert item.find(f'{{{release.SPARKLE}}}version').text == '0.1.2'
    enclosure = item.find('enclosure')
    assert enclosure.attrib['length'] == str(package.stat().st_size)
    assert enclosure.attrib['url'] == 'https://github.com/k1ngr4m/eave/releases/download/v0.1.2/Eave-0.1.2.zip'
    assert enclosure.attrib[f'{{{release.SPARKLE}}}edSignature'] == 'test-signature'
    manifest = {'version': '0.1.2', 'commit': 'a' * 40,
                'sha256': {p.name: release.digest(p) for p in (package, feed)}}
    (prepared / 'release.json').write_text(json.dumps(manifest))
    notes = root / 'notes.md'
    notes.write_text('Test release')
    args = argparse.Namespace(version='0.1.2', notes=str(notes))
    calls = []
    corrupt = False

    def fake_run(*command, **kwargs):
        calls.append(command)
        if command[:2] == ('gh', 'api'):
            return manifest['commit']
        if command[:3] == ('gh', 'release', 'download'):
            dest = Path(command[command.index('--dir') + 1])
            for name in manifest['sha256']:
                (dest / name).write_bytes(b'corrupt' if corrupt else (prepared / name).read_bytes())
        return ''

    with patch.object(release, 'ROOT', root), patch.object(release, 'run', side_effect=fake_run), \
            patch.object(release, 'check_remote'):
        release.publish(args)
        actions = [c[2] for c in calls if c[:2] == ('gh', 'release')]
        assert actions == ['create', 'download', 'edit']
        assert '--draft' in next(c for c in calls if c[:3] == ('gh', 'release', 'create'))
        assert '--draft=false' in calls[-1]
        calls.clear()
        corrupt = True
        rejected(lambda: release.publish(args))
        assert not any(c[:3] == ('gh', 'release', 'edit') for c in calls)
        calls.clear()
        package.write_bytes(b'tampered locally')
        rejected(lambda: release.publish(args))
        assert not calls

print('Cross-machine version ordering, feed metadata, rollback and draft integrity checks passed.')

# Optional native checks, required in CI after Xcode has resolved Sparkle.
if '--swift' in sys.argv:
    import subprocess
    frameworks = sorted((Path.home() / 'Library/Developer/Xcode/DerivedData').glob(
        '*/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'))
    assert frameworks, 'Build the app to resolve Sparkle first'
    framework_dir = frameworks[0].parent
    with tempfile.TemporaryDirectory() as directory:
        executable = Path(directory) / 'updater-checks'
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-F', str(framework_dir),
            '-framework', 'Sparkle', '-Xlinker', '-rpath', '-Xlinker', str(framework_dir),
            str(ROOT / 'DynamicIsland/components/Settings/CustomUpdaterViews/EaveUserDriver.swift'),
            str(ROOT / 'tests/EaveUpdaterChecks.swift'), '-o', str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
