"""Run: python3 tests/test_desktop_ping.py [--ui] (UI check requires a logged-in Mac)."""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / '.build/desktop-ping'
subprocess.run(['bash', 'scripts/build-desktop-ping.sh', '--test'], cwd=ROOT, check=True)
subprocess.run(['swiftc', 'DynamicIsland/models/DesktopPingConfiguration.swift',
                'DynamicIsland/models/DesktopEmoteCatalog.swift', 'DynamicIsland/models/DesktopEmoteConfiguration.swift',
                'DynamicIsland/managers/DesktopEmoteLibrary.swift', 'DynamicIsland/managers/DesktopPingOverlay.swift',
                'DynamicIsland/components/Settings/DesktopPingWheelEditor.swift', 'tests/DesktopPingRegression.swift',
                '-o', str(WORK / 'regression')], cwd=ROOT, check=True)
(WORK / 'DesktopPing').symlink_to(ROOT / 'Support/DesktopPing/web', target_is_directory=True) if not (WORK / 'DesktopPing').exists() else None
subprocess.run([str(WORK / 'regression'), str(ROOT), *sys.argv[1:]], check=True)

config = dict(type='config', trigger='alt', clickPing=False, emoteTrigger='off', emoteClick=False,
              dragThresholdPx=8, toggleMods=3, toggleVk=80, enabled=True)
def event(ev, **fields):
    return dict(type='sim', ev=ev, **fields)

def simulate(events, overrides=None):
    result = subprocess.run([str(WORK / 'EavePingHelper'), '--simulate'], input=''.join(
        json.dumps(e) + '\n' for e in [{**config, **(overrides or {})}, *events, dict(type='shutdown')]),
        text=True, capture_output=True, check=True, timeout=5)
    return [json.loads(line) for line in result.stdout.splitlines()]

result = simulate([event('kdown', vk=0x12), event('mdown', btn='left', x=100, y=100),
                   event('move', x=100, y=200), event('mup', btn='left', x=100, y=200)])
assert [e['type'] for e in result if e['type'].startswith('wheel')] == ['wheelOpen', 'wheelMove', 'wheelRelease']
assert all(e.get('wheel', 'ping') == 'ping' for e in result)
result = simulate([event('kdown', vk=0x12), event('mdown', btn='left'), event('mup', btn='left')])
assert any(e.get('inject') == 'down:left,up:left' for e in result), result
result = simulate([event('kdown', vk=0x11), event('mdown', btn='left'), event('move', x=200), event('mup', btn='left')])
assert not any(e.get('swallow') for e in result), 'Control must not activate the deferred emote feature'
result = simulate([dict(type='setEnabled', enabled=False), event('kdown', vk=0x12),
                   event('mdown', btn='left'), event('move', x=200), event('mup', btn='left')])
assert not any(e.get('swallow') for e in result), 'Paused input must pass through'
result = simulate([event('kdown', vk=0x11), event('kdown', vk=0x12), event('kdown', vk=80)])
assert any(e['type'] == 'toggled' and not e['enabled'] for e in result)
print('Helper protocol: gesture, click replay, disabled emotes, pause and toggle passed.')

# The same helper routes emote drags/clicks, cancels, and passes ambiguous keys through.
emote = dict(emoteTrigger='ctrl', emoteClick=True)
result = simulate([event('kdown', vk=0x11), event('mdown', btn='left', x=100, y=100),
                   event('move', x=250, y=100), event('mup', btn='left', x=250, y=100)], emote)
assert [e['type'] for e in result if e.get('wheel') == 'emote'] == ['wheelOpen', 'wheelMove', 'wheelRelease'], result
result = simulate([event('kdown', vk=0x11), event('mdown', btn='left'), event('mup', btn='left')], emote)
assert any(e['type'] == 'click' and e['wheel'] == 'emote' for e in result), result
result = simulate([event('kdown', vk=0x11), event('kdown', vk=0x12), event('mdown', btn='left'),
                   event('move', x=200), event('mup', btn='left')], emote)
assert not any(e.get('swallow') for e in result), result
result = simulate([dict(type='setEnabled', enabled=False), event('kdown', vk=0x11),
                   event('mdown', btn='left'), event('move', x=200), event('mup', btn='left')], emote)
assert not any(e.get('swallow') for e in result), result
print('Emote helper gestures, click, ambiguous triggers and pause passed.')
