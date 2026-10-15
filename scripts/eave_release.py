#!/usr/bin/env python3
"""Prepare an ad-hoc signed Eave release (optionally notarized), then publish it."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from eave_version import ROOT, archive, version_parts

REPO = 'k1ngr4m/eave'
ACCOUNT = 'com.eave.app'
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
FEED = f'https://github.com/{REPO}/releases/latest/download/appcast.xml'
ET.register_namespace('sparkle', SPARKLE)
ARCHITECTURES = {'Intel': 'x86_64', 'AppleSilicon': 'arm64'}


def run(*args, cwd=ROOT):
    return subprocess.check_output([str(a) for a in args], cwd=cwd, text=True).strip()


def digest(path):
    with path.open('rb') as stream:
        checksum = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            checksum.update(chunk)
        return checksum.hexdigest()


def architecture_app(source, destination, architecture, identity='-'):
    run('ditto', source, destination)
    for binary in destination.rglob('*'):
        if binary.is_symlink() or not binary.is_file():
            continue
        with binary.open('rb') as stream:
            magic = stream.read(4)
        if magic not in (b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca',
                         b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca',
                         b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf'):
            continue
        architectures = run('lipo', '-archs', binary).split()
        if architecture not in architectures:
            raise ValueError(f'{binary} is missing {architecture}')
        if len(architectures) > 1:
            temporary = binary.with_name(binary.name + '.thin')
            run('lipo', binary, '-thin', architecture, '-output', temporary)
            temporary.replace(binary)
        if run('lipo', '-archs', binary) != architecture:
            raise ValueError(f'{binary} was not thinned to {architecture}')
    # Slice signatures survive lipo, but resource-embedded frameworks change the app's seal.
    run('codesign', '--force', '--sign', identity,
        '--preserve-metadata=identifier,entitlements,requirements,flags,runtime', destination)
    run('codesign', '--verify', '--deep', '--strict', destination)


def notarize(app, output, profile):
    submission = output / 'notarization.zip'
    run('ditto', '-c', '-k', '--keepParent', app, submission)
    result = json.loads(run('xcrun', 'notarytool', 'submit', submission, '--keychain-profile', profile,
                           '--wait', '--output-format', 'json'))
    (output / 'notarization.json').write_text(json.dumps(result, indent=2) + '\n')
    if result.get('status') != 'Accepted':
        raise ValueError(f'Notarization failed; inspect {output / "notarization.json"}')
    run('xcrun', 'stapler', 'staple', app)
    run('xcrun', 'stapler', 'validate', app)
    run('spctl', '--assess', '--type', 'execute', app)


def available_version(version, releases):
    requested = version_parts(version)
    for release in releases:
        tag = release['tag_name']
        if tag == f'v{version}':
            raise ValueError(f'{tag} already exists (including drafts); never overwrite a release')
        if not release['draft'] and not release['prerelease']:
            if not re.fullmatch(r'v\d+\.\d+\.\d+', tag):
                raise ValueError(f'Unexpected release tag: {tag}')
            if requested <= version_parts(tag[1:]):
                raise ValueError(f'Version must be newer than published release {tag}')


def check_remote(version):
    pages = json.loads(run('gh', 'api', '--paginate', '--slurp', f'repos/{REPO}/releases?per_page=100'))
    available_version(version, [item for page in pages for item in page])
    refs = json.loads(run('gh', 'api', f'repos/{REPO}/git/matching-refs/tags/v{version}'))
    if any(ref['ref'] == f'refs/tags/v{version}' for ref in refs):
        raise ValueError(f'Remote tag v{version} already exists')


def appcast(version, package, signature, minimum_os):
    version_parts(version)
    rss = ET.Element('rss', version='2.0')
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'Eave'
    ET.SubElement(channel, 'link').text = f'https://github.com/{REPO}'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'Eave {version}'
    ET.SubElement(item, f'{{{SPARKLE}}}version').text = version
    ET.SubElement(item, f'{{{SPARKLE}}}shortVersionString').text = version
    ET.SubElement(item, f'{{{SPARKLE}}}minimumSystemVersion').text = minimum_os
    ET.SubElement(item, 'enclosure', {
        'url': f'https://github.com/{REPO}/releases/download/v{version}/{package.name}',
        'length': str(package.stat().st_size), 'type': 'application/octet-stream',
        f'{{{SPARKLE}}}edSignature': signature,
    })
    ET.indent(rss)
    return ET.tostring(rss, encoding='utf-8', xml_declaration=True)


def prepare(args):
    version_parts(args.version)
    if (ROOT / 'VERSION').read_text().strip() != args.version:
        raise ValueError('Set VERSION to the intended release and commit it before preparing')
    if run('git', 'status', '--porcelain', '--untracked-files=normal'):
        raise ValueError('Commit source changes before preparing a release')
    if not args.sparkle_bin:
        raise ValueError('Missing --sparkle-bin (or EAVE_SPARKLE_BIN)')
    if args.signing == 'notarized':
        for name in ('identity', 'team', 'notary_profile'):
            if not getattr(args, name):
                raise ValueError(f'Missing --{name.replace("_", "-")} for notarized signing')
        if not args.identity.startswith('Developer ID Application:') or not re.fullmatch(r'[A-Z0-9]{10}', args.team):
            raise ValueError('A Developer ID Application identity and 10-character team ID are required')
        if f'({args.team})' not in args.identity or args.identity not in run('security', 'find-identity', '-v', '-p', 'codesigning'):
            raise ValueError('Developer ID identity is missing or does not match the team')
    binaries = Path(args.sparkle_bin).expanduser()
    public_key = run(binaries / 'generate_keys', '--account', ACCOUNT, '-p')
    source_info = plistlib.loads((ROOT / 'DynamicIsland/Info.plist').read_bytes())
    if public_key != source_info['SUPublicEDKey']:
        raise ValueError('The Eave Keychain signing key does not match SUPublicEDKey')
    if args.signing == 'notarized':
        run('xcrun', 'notarytool', 'history', '--keychain-profile', args.notary_profile, '--output-format', 'json')
    check_remote(args.version)
    output = ROOT / 'build' / f'release-{args.version}'
    output.mkdir(parents=True, exist_ok=False)
    commit = run('git', 'rev-parse', 'HEAD')
    app = output / 'export/Eave.app'
    if args.signing == 'local':
        # amfid rejects this restricted entitlement on ad-hoc signed apps.
        entitlements = plistlib.loads((ROOT / 'DynamicIsland/DynamicIsland.entitlements').read_bytes())
        entitlements.pop('com.apple.security.mach-services', None)
        entitlements_path = output / 'LocalSigning.entitlements'
        entitlements_path.write_bytes(plistlib.dumps(entitlements))
        archive(ROOT, args.version, [
            'CODE_SIGN_IDENTITY=-', 'CODE_SIGN_STYLE=Manual', 'DEVELOPMENT_TEAM=',
            'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGNING_REQUIRED=NO',
            'ENABLE_HARDENED_RUNTIME=NO', 'CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO',
            f'CODE_SIGN_ENTITLEMENTS={entitlements_path}',
        ])
        run('ditto', ROOT / 'build' / f'Eave-{args.version}.xcarchive/Products/Applications/Eave.app', app)
    else:
        archive(ROOT, args.version, [f'DEVELOPMENT_TEAM={args.team}', f'CODE_SIGN_IDENTITY={args.identity}'])
        options = output / 'ExportOptions.plist'
        options.write_bytes(plistlib.dumps({'method': 'developer-id', 'teamID': args.team,
            'signingStyle': 'manual', 'signingCertificate': args.identity}))
        run('xcodebuild', '-exportArchive', '-archivePath', ROOT / 'build' / f'Eave-{args.version}.xcarchive',
            '-exportPath', output / 'export', '-exportOptionsPlist', options)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    expected = {'CFBundleIdentifier': ACCOUNT, 'EaveBuildChannel': 'release',
        'CFBundleVersion': args.version, 'CFBundleShortVersionString': args.version,
        'SUPublicEDKey': public_key, 'SUFeedURL': FEED}
    if any(info.get(key) != value for key, value in expected.items()):
        raise ValueError('Exported app identity/version/update configuration does not match')
    run('codesign', '--verify', '--deep', '--strict', app)
    if args.signing == 'notarized':
        notarize(app, output, args.notary_profile)
    package = output / f'Eave-{args.version}.zip'
    run('ditto', '-c', '-k', '--keepParent', app, package)
    signature = run(binaries / 'sign_update', '--account', ACCOUNT, '-p', package)
    run(binaries / 'sign_update', '--account', ACCOUNT, '--verify', package, signature)
    feed = output / 'appcast.xml'
    feed.write_bytes(appcast(args.version, package, signature, info['LSMinimumSystemVersion']))
    artifacts = [package, feed]
    for label, architecture in ARCHITECTURES.items():
        variant = output / label / 'Eave.app'
        architecture_app(app, variant, architecture, args.identity if args.signing == 'notarized' else '-')
        if args.signing == 'notarized':
            notarize(variant, variant.parent, args.notary_profile)
        package = output / f'Eave-{args.version}-{label}.zip'
        run('ditto', '-c', '-k', '--keepParent', variant, package)
        artifacts.append(package)
    (output / 'release.json').write_text(json.dumps({'version': args.version, 'commit': commit, 'signing': args.signing,
        'sha256': {p.name: digest(p) for p in artifacts}}, indent=2) + '\n')
    print(f'Ready: {output}. Review artifacts, then use publish with a release notes file.')


def publish(args):
    version_parts(args.version)
    output = ROOT / 'build' / f'release-{args.version}'
    manifest = json.loads((output / 'release.json').read_text())
    names = {f'Eave-{args.version}.zip', 'appcast.xml',
             *(f'Eave-{args.version}-{label}.zip' for label in ARCHITECTURES)}
    if manifest['version'] != args.version or set(manifest['sha256']) != names:
        raise ValueError('Release manifest does not match the requested version')
    for name, checksum in manifest['sha256'].items():
        if digest(output / name) != checksum:
            raise ValueError(f'Prepared artifact changed: {name}; rebuild before publishing')
    notes = Path(args.notes).resolve()
    if not notes.is_file() or not notes.read_text().strip():
        raise ValueError('A non-empty release notes file is required')
    commit = manifest['commit']
    # Verify GitHub has the exact source commit used for the archive.
    if run('gh', 'api', f'repos/{REPO}/commits/{commit}', '--jq', '.sha') != commit:
        raise ValueError('Push the release source commit before publishing')
    check_remote(args.version)
    tag = f'v{args.version}'
    run('gh', 'release', 'create', tag, *(output / name for name in sorted(names)), '--repo', REPO,
        '--target', commit, '--draft', '--title', f'Eave {args.version}', '--notes-file', notes)
    # A failure leaves a draft for inspection, never an incomplete public feed.
    with tempfile.TemporaryDirectory() as directory:
        run('gh', 'release', 'download', tag, '--repo', REPO, '--dir', directory)
        for name, checksum in manifest['sha256'].items():
            if digest(Path(directory) / name) != checksum:
                raise ValueError(f'Uploaded asset differs: {name}; release remains a draft')
    run('gh', 'release', 'edit', tag, '--repo', REPO, '--draft=false', '--latest')
    print(f'Published https://github.com/{REPO}/releases/tag/{tag}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    prep = commands.add_parser('prepare')
    prep.add_argument('version')
    prep.add_argument('--signing', choices=('local', 'notarized'), default='local',
                      help='local: ad-hoc signing without Apple credentials (default)')
    for name in ('identity', 'team', 'notary-profile', 'sparkle-bin'):
        prep.add_argument(f'--{name}', default=os.environ.get('EAVE_' + name.upper().replace('-', '_')))
    pub = commands.add_parser('publish')
    pub.add_argument('version')
    pub.add_argument('--notes', required=True)
    args = parser.parse_args()
    try:
        (prepare if args.command == 'prepare' else publish)(args)
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'error: {error}\n')


if __name__ == '__main__':
    main()
