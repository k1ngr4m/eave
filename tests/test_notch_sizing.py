"""Run: python3 tests/test_notch_sizing.py (macOS Swift toolchain)."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'DynamicIsland/sizing/matters.swift').read_text()
constants = (root / 'DynamicIsland/models/Constants.swift').read_text()


def function(name):
    start = source.index('func ' + name + '(')
    return source[start:source.index('\n}', start) + 2]


keys = constants[constants.index('    static let nonNotchHeight ='):constants.index('    static let reopenTab =')]
program = r'''
import Foundation
import CoreGraphics
enum WindowHeightMode { case matchRealNotchSize, matchMenuBar, custom }
enum Defaults {
    class Keys {}
    final class Key<Value>: Keys {
        let name: String
        let defaultValue: Value
        init(_ name: String, default value: Value) { self.name = name; defaultValue = value }
    }
    static var values: [String: Any] = [:]
    static subscript<Value>(key: Key<Value>) -> Value {
        get { values[key.name] as? Value ?? key.defaultValue }
        set { values[key.name] = newValue }
    }
}
typealias Key = Defaults.Key
extension Defaults.Keys {
    static let enableMinimalisticUI = Key("minimal", default: false)
    static let enableLyrics = Key("lyrics", default: false)
    static let showStandardMediaControls = Key("media", default: true)
    static let autoHideInactiveNotchMediaPlayer = Key("idle", default: false)
    static let lyricsPanelWidth = Key<CGFloat>("lyricsWidth", default: 460)
    static let lyricsPanelOffset = Key<CGFloat>("lyricsOffset", default: 0)
    static let notchHeightMode = Key("notchHeightMode", default: WindowHeightMode.matchRealNotchSize)
    static let nonNotchHeightMode = Key("nonNotchHeightMode", default: WindowHeightMode.matchMenuBar)
''' + keys + r'''
}
struct NSScreen {
    struct Insets { var top: CGFloat = 0 }
    var localizedName: String
    var frame: CGRect
    var visibleFrame: CGRect { frame.insetBy(dx: 0, dy: 24) }
    var safeAreaInsets = Insets()
    var auxiliaryTopLeftArea: CGRect? = nil
    var auxiliaryTopRightArea: CGRect? = nil
    static var screens = [NSScreen(localizedName: "wide", frame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
                          NSScreen(localizedName: "narrow", frame: CGRect(x: 0, y: 0, width: 600, height: 900))]
    static var main: NSScreen? { screens.first }
}
enum TabModel {
    static var count = 3
    static func availableTabs() -> [Int] { Array(0..<count) }
}
struct MusicManager {
    static var shared = MusicManager()
    var hasActiveSession = true
}
''' + source[source.index('enum SideLyricsLayout {'):source.index('var openNotchSize:')] + '\n' + '\n'.join(
    function(name) for name in [
        'getOpenNotchSize', 'maxAllowedNotchWidth', 'enabledStandardTabCount',
        'recommendedMinimumNotchWidth', 'currentRecommendedMinimumNotchWidth',
        'calendarOpenNotchSize', 'getClosedNotchSize',
    ]
) + r'''
Defaults[.openNotchWidth] = 880
assert(!Defaults[.customizeOpenNotchWidth])
for (count, expected) in [(3, 640), (5, 690), (6, 770), (3, 640)] {
    TabModel.count = count
    assert(getOpenNotchSize(screen: "wide").width == CGFloat(expected))
    assert(calendarOpenNotchSize(screen: "wide").width == CGFloat(expected))
    assert(Defaults[.openNotchWidth] == 880)
}
Defaults[.enableLyrics] = true
assert(getOpenNotchSize(screen: "wide", includesSideLyrics: true).width == 900)
assert(calendarOpenNotchSize(screen: "wide").width == 640)
Defaults[.enableLyrics] = false
assert(getOpenNotchSize(screen: "wide", includesSideLyrics: true).width == 640)
assert(getOpenNotchSize(screen: "narrow").width == 540)
assert(calendarOpenNotchSize(screen: "narrow").width == 540)

Defaults[.customizeOpenNotchWidth] = true
Defaults[.openNotchWidth] = 710
TabModel.count = 6
assert(getOpenNotchSize(screen: "wide").width == 770)
assert(Defaults[.openNotchWidth] == 710)
TabModel.count = 3
assert(getOpenNotchSize(screen: "wide").width == 710)
assert(getOpenNotchSize(screen: "narrow").width == 540)
assert(getOpenNotchSize(screen: "wide").width == 710)
Defaults[.enableLyrics] = true
assert(getOpenNotchSize(screen: "wide", includesSideLyrics: true).width == 900)
Defaults[.enableLyrics] = false
assert(getOpenNotchSize(screen: "wide", includesSideLyrics: true).width == 710)
Defaults[.customizeOpenNotchWidth] = false
assert(getOpenNotchSize(screen: "wide").width == 640)
Defaults[.customizeOpenNotchWidth] = true
assert(getOpenNotchSize(screen: "wide").width == 710)
assert(Defaults[.openNotchWidth] == 710)

Defaults[.closedNotchWidth] = 215
assert(getClosedNotchSize(screen: "wide").width == 150)
Defaults[.customizeNonNotchWidth] = true
assert(getClosedNotchSize(screen: "wide").width == 215)
Defaults[.customizeNonNotchWidth] = false
assert(getClosedNotchSize(screen: "wide").width == 150)
assert(Defaults[.closedNotchWidth] == 215)
NSScreen.screens[0].safeAreaInsets.top = 38
NSScreen.screens[0].auxiliaryTopLeftArea = CGRect(x: 0, y: 0, width: 620, height: 38)
NSScreen.screens[0].auxiliaryTopRightArea = CGRect(x: 0, y: 0, width: 620, height: 38)
assert(getClosedNotchSize(screen: "wide").width == 204)
Defaults[.customizePhysicalNotchWidth] = true
assert(getClosedNotchSize(screen: "wide").width == 215)
Defaults[.notchHeight] = 35
Defaults[.nonNotchHeight] = 20
for mode in [WindowHeightMode.matchRealNotchSize, .matchMenuBar] {
    Defaults[.notchHeightMode] = mode
    Defaults[.nonNotchHeightMode] = mode
    assert(getClosedNotchSize(screen: "wide").height == 38)
    assert(getClosedNotchSize(screen: "narrow").height == 24)
    assert(Defaults[.notchHeight] == 35)
    assert(Defaults[.nonNotchHeight] == 20)
}
Defaults[.notchHeightMode] = .custom
Defaults[.nonNotchHeightMode] = .custom
assert(getClosedNotchSize(screen: "wide").height == 35)
assert(getClosedNotchSize(screen: "narrow").height == 20)
print("Notch sizing passed: tabs grow/shrink, lyrics removed, screen bounds, calendar, saved custom values, and adaptive/custom height modes.")
'''
with tempfile.TemporaryDirectory(prefix='eave-notch-sizing-') as directory:
    path = Path(directory) / 'check.swift'
    path.write_text(program)
    subprocess.run(['swift', str(path)], check=True)
