"""Run with python3 tests/test_eave_version.py; uses only temporary counters."""
from concurrent.futures import ProcessPoolExecutor
import contextlib
import io
from pathlib import Path
import plistlib
import sys
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from eave_version import archive, stamp


def build(root, channel, name):
    output = root / "derived" / f"{name}.plist"
    output.parent.mkdir(parents=True, exist_ok=True)
    if not output.exists():
        output.write_bytes((root / "DynamicIsland/Info.plist").read_bytes())
    with contextlib.redirect_stdout(io.StringIO()):
        stamp(root, output, channel, root / "counters")
    return plistlib.loads(output.read_bytes())


def rejected(action):
    try:
        action()
    except ValueError:
        return
    raise AssertionError("Invalid input was accepted")


def check():
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        (root / "DynamicIsland").mkdir()
        source = (ROOT / "DynamicIsland/Info.plist").read_bytes()
        (root / "DynamicIsland/Info.plist").write_bytes(source)
        (root / "VERSION").write_text("0.1.0\n")
        for channel, number in (("dev", "0001"), ("dev", "0002"), ("release", "0001")):
            info = build(root, channel, channel)
            assert info["EaveBuildNumber"] == number
            assert info["CFBundleShortVersionString"] == info["CFBundleVersion"] == "0.1.0"
            assert info["EaveBuildChannel"] == channel
            assert info["NSAudioCaptureUsageDescription"] == plistlib.loads(source)["NSAudioCaptureUsageDescription"]
        assert (root / "VERSION").read_text() == "0.1.0\n"
        assert (root / "DynamicIsland/Info.plist").read_bytes() == source
        # New output directory (like Clean Build Folder) must not reset counters.
        assert build(root, "dev", "after-clean")["EaveBuildNumber"] == "0003"
        rejected(lambda: build(root, "beta", "invalid"))
        (root / "VERSION").write_text("0.1.1\n")
        assert build(root, "dev", "new-version")["EaveBuildNumber"] == "0004"
        (root / "VERSION").write_text("0.1.1-beta.1\n")
        rejected(lambda: build(root, "dev", "invalid-version"))
        assert (root / "counters/dev").read_text() == "4\n"
        (root / "VERSION").write_text("0.1.1\n")
        with ProcessPoolExecutor(max_workers=4) as pool:
            jobs = [pool.submit(build, root, "dev", str(i)) for i in range(8)]
            assert sorted(int(job.result()["EaveBuildNumber"]) for job in jobs) == list(range(5, 13))
        (root / "counters/dev").write_text("9998\n")
        assert build(root, "dev", "four-digits")["EaveBuildNumber"] == "9999"
        assert build(root, "dev", "five-digits")["EaveBuildNumber"] == "10000"
        (root / "counters/dev").write_text("broken")
        rejected(lambda: build(root, "dev", "broken-counter"))
        assert (root / "counters/dev").read_text() == "broken"

        def fake_xcodebuild(command, **kwargs):
            assert command[:2] == ["xcodebuild", "archive"]
            assert command[command.index("-configuration") + 1] == "Release"
            assert command[-1] == "EAVE_CHANNEL=release"
            assert kwargs == {"cwd": root, "check": True}
            output = Path(command[command.index("-archivePath") + 1]) / "Products/Applications/Eave.app/Contents/Info.plist"
            output.parent.mkdir(parents=True)
            output.write_bytes(source)
            stamp(root, output, "release", root / "counters")

        with patch("eave_version.subprocess.check_output", return_value=""), \
                patch("eave_version.subprocess.run", side_effect=fake_xcodebuild) as run:
            rejected(lambda: archive(root, "0.1.0"))
            rejected(lambda: archive(root, "0.2.0-dev"))
            archive(root, "0.2.0")
            assert (root / "VERSION").read_text() == "0.2.0\n"
            assert (root / "counters/release").read_text() == "2\n"
            rejected(lambda: archive(root, "0.2.0"))  # Never overwrite an archive.
            assert run.call_count == 1
        with patch("eave_version.subprocess.check_output", return_value="v0.2.1\n"):
            rejected(lambda: archive(root, "0.2.1"))
            assert (root / "VERSION").read_text() == "0.2.0\n"
    print("Version, channel counters, concurrency and release archive checks passed.")


if __name__ == "__main__":
    check()
