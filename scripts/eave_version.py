#!/usr/bin/env python3
"""Stamp each app build; explicitly prepare and archive an official release."""
import argparse
import fcntl
import os
from pathlib import Path
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def version_parts(version):
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
        raise ValueError("Version must be major.minor.patch, for example 0.1.0")
    return tuple(map(int, version.split(".")))


def stamp(root, output, channel, counter_dir):
    if channel not in ("dev", "release"):
        raise ValueError(f"Unsupported channel: {channel}")
    version = (root / "VERSION").read_text().strip()
    version_parts(version)
    # Xcode has already merged its generated metadata. Stamp before code signing.
    info = plistlib.loads(output.read_bytes())
    counter_dir.mkdir(parents=True, exist_ok=True)
    counter = counter_dir / channel
    # Separate lock survives the atomic replacement of the counter file.
    with (counter_dir / f"{channel}.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        previous = counter.read_text().strip() if counter.exists() else "0"
        if not re.fullmatch(r"0|[1-9][0-9]*", previous):
            raise ValueError(f"Invalid build counter: {counter}")
        number = int(previous) + 1
        temporary = counter.with_suffix(".tmp")
        temporary.write_text(f"{number}\n")
        temporary.replace(counter)
    info.update(CFBundleShortVersionString=version, CFBundleVersion=str(number),
                EaveBuildChannel=channel)
    output.write_bytes(plistlib.dumps(info))
    print(f"Eave {version} · {channel} ({number})")


def archive(root, version):
    requested = version_parts(version)
    current = version_parts((root / "VERSION").read_text().strip())
    if requested < current:
        raise ValueError("A release version cannot go backwards")
    tag = f"v{version}"
    if subprocess.check_output(["git", "tag", "--list", tag], cwd=root, text=True).strip():
        raise ValueError(f"{tag} already exists; choose a new release version")
    archive_path = root / "build" / f"Eave-{version}.xcarchive"
    if archive_path.exists():
        raise ValueError(f"Archive already exists: {archive_path}; move it before retrying")
    (root / "VERSION").write_text(f"{version}\n")
    subprocess.run([
        "xcodebuild", "archive", "-project", "DynamicIsland.xcodeproj",
        "-scheme", "DynamicIsland", "-configuration", "Release",
        "-destination", "generic/platform=macOS", "-archivePath", str(archive_path),
        "EAVE_CHANNEL=release",
    ], cwd=root, check=True)
    info = plistlib.loads((archive_path / "Products/Applications/Eave.app/Contents/Info.plist").read_bytes())
    if info.get("CFBundleShortVersionString") != version or info.get("EaveBuildChannel") != "release":
        raise ValueError("Archive version/channel does not match the requested release")
    print(f"Archive ready: {archive_path} (build {info['CFBundleVersion']})")
    print(f"After verification, commit VERSION and release notes, then tag that commit {tag}.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("build")
    commands.add_parser("archive").add_argument("version")
    args = parser.parse_args()
    try:
        if args.command == "archive":
            archive(ROOT, args.version)
        else:
            counter_dir = Path(os.environ.get("EAVE_BUILD_COUNTER_DIR", str(
                Path.home() / "Library/Application Support/Eave/BuildNumbers")))
            stamp(ROOT, Path(os.environ["SCRIPT_INPUT_FILE_0"]),
                  os.environ.get("EAVE_CHANNEL", "dev"), counter_dir)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"error: {error}\n")


if __name__ == "__main__":
    main()
