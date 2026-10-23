"""Run the production last-played recorder against isolated preferences."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MediaIdleTests(unittest.TestCase):
    def test_history_changes_only_for_new_metadata(self):
        source = (ROOT / 'DynamicIsland/managers/MusicManager.swift').read_text()
        start = source.index('    private func recordLastPlayedTrack(')
        end = source.index('\n    func openMusicApp()', start)
        recorder = source[start:end].replace('private func', 'func', 1)
        harness = r'''
import Foundation
struct LastPlayedTrack: Equatable {
    var title: String
    var artist: String
    var bundleIdentifier: String?
    var recordedAt: Date
}
enum Key { case lastPlayedTrack }
enum Defaults {
    static var value: LastPlayedTrack?
    static var writes = 0
    static subscript(key: Key) -> LastPlayedTrack? {
        get { value }
        set { value = newValue; writes += 1 }
    }
}
struct Manager {
    static let placeholderTitles: Set<String> = ["i'm handsome", "unknown", "not playing"]
    static let placeholderArtists: Set<String> = ["me", "unknown"]
''' + recorder + r'''
}
let manager = Manager()
manager.recordLastPlayedTrack(title: "Unknown", artist: "Me", bundleIdentifier: nil)
precondition(Defaults.writes == 0)
manager.recordLastPlayedTrack(title: " Song ", artist: " Artist ", bundleIdentifier: "app.one")
let first = Defaults.value
precondition(first?.title == "Song" && Defaults.writes == 1)
for _ in 0..<100 {
    manager.recordLastPlayedTrack(title: "Song", artist: "Artist", bundleIdentifier: "app.one")
}
precondition(Defaults.value == first && Defaults.writes == 1, "Repeated events must preserve timestamp without writes")
manager.recordLastPlayedTrack(title: "Not Playing", artist: "Unknown", bundleIdentifier: nil)
precondition(Defaults.value == first && Defaults.writes == 1)
manager.recordLastPlayedTrack(title: "Song", artist: "Artist", bundleIdentifier: "app.two")
precondition(Defaults.value?.bundleIdentifier == "app.two" && Defaults.writes == 2)
manager.recordLastPlayedTrack(title: "Next", artist: "", bundleIdentifier: nil)
precondition(Defaults.value?.title == "Next" && Defaults.writes == 3)
print("PASS: placeholders, trimming, repeated events, source changes and next track")
'''
        with tempfile.TemporaryDirectory(prefix='eave-media-idle-') as directory:
            path = Path(directory) / 'check.swift'
            path.write_text(harness)
            subprocess.run(['swift', str(path)], check=True)


if __name__ == '__main__':
    unittest.main()
