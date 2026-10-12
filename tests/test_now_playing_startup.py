"""Run the production update handler without launching the media observer."""
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class NowPlayingStartupTests(unittest.TestCase):
    def test_startup_and_pause_resume_anchors(self):
        source = (ROOT / "DynamicIsland/MediaControllers/NowPlayingController.swift").read_text()
        handler = source[source.index("    private func handleAdapterUpdate"):source.index("\nstruct NowPlayingUpdate:")]
        payload = source[source.index("struct NowPlayingUpdate:"):source.index("actor JSONLinesPipeHandler")]
        window = next(line for line in source.splitlines() if "private static let currentSampleWindow:" in line)
        harness = """
import Foundation
final class NowPlayingController {
    var playbackState = PlaybackState(bundleIdentifier: "com.apple.Music")
    func receive(_ json: String) async throws {
        await handleAdapterUpdate(try JSONDecoder().decode(NowPlayingUpdate.self, from: Data(json.utf8)))
    }
""" + window + "\n" + handler + payload + r'''
@main struct Check {
    static func main() async throws {
        let anchor = Date().addingTimeInterval(-120)
        let snapshot = #"{"payload":{"title":"Song","artist":"Artist","album":"Album","bundleIdentifier":"com.tencent.QQMusicMac","playing":true,"elapsedTimeMicros":0,"timestampEpochMicros":\#(anchor.timeIntervalSince1970 * 1_000_000)}}"#
        let controller = NowPlayingController()
        // Also cover an empty initial snapshot and a paused different source.
        for initial in [nil, #"{"payload":{}}"#, #"{"payload":{"title":"Other","bundleIdentifier":"com.apple.Music","playing":false,"elapsedTime":40}}"#] as [String?] {
            let fresh = NowPlayingController()
            if let initial { try await fresh.receive(initial) }
            try await fresh.receive(snapshot)
            precondition(abs(fresh.playbackState.lastUpdated.timeIntervalSince(anchor)) < 0.001)
            let position = fresh.playbackState.currentTime + Date().timeIntervalSince(fresh.playbackState.lastUpdated)
            precondition(abs(position - 120) < 2, "Startup lost the player's anchor")
        }
        try await controller.receive(snapshot)
        try await controller.receive(#"{"diff":true,"payload":{"playing":false}}"#)
        let paused = controller.playbackState.currentTime
        precondition(abs(paused - 120) < 2, "Pause must freeze the estimated position")
        controller.playbackState.lastUpdated = Date().addingTimeInterval(-60)
        try await controller.receive(snapshot)
        precondition(controller.playbackState.currentTime == paused, "Resume must exclude paused time")
        precondition(abs(controller.playbackState.lastUpdated.timeIntervalSinceNow) < 2)
        try await controller.receive(#"{"diff":true,"payload":{"playing":false}}"#)
        // A fresh seek sample takes precedence over the frozen position.
        try await controller.receive(#"{"diff":true,"payload":{"playing":true,"elapsedTime":75,"timestampEpochMicros":\#(Date().timeIntervalSince1970 * 1_000_000)}}"#)
        precondition(controller.playbackState.currentTime == 75)
        try await controller.receive(#"{"diff":true,"payload":{"playing":false}}"#)
        try await controller.receive(snapshot.replacingOccurrences(of: "Song", with: "Next song"))
        precondition(abs(controller.playbackState.lastUpdated.timeIntervalSince(anchor)) < 0.001)
        print("PASS: mid-track startup, empty snapshot, source/track changes, pause/resume, fresh seek")
    }
}
'''
        with tempfile.TemporaryDirectory(prefix="eave-now-playing-") as directory:
            swift = Path(directory) / "Check.swift"
            swift.write_text(harness)
            binary = Path(directory) / "check"
            subprocess.run(["xcrun", "swiftc", "-parse-as-library",
                            str(ROOT / "DynamicIsland/models/PlaybackState.swift"),
                            str(swift), "-o", str(binary)], check=True)
            subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    unittest.main()
