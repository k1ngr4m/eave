"""Run with python3 tests/test_settings_permissions.py."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="eave-permissions-") as directory:
    binary = str(Path(directory) / "checks")
    subprocess.run([
        "xcrun", "swiftc",
        str(root / "Packages/EaveStatus/Sources/EaveStatus/UI/SettingsPermissionRow.swift"),
        str(root / "tests/SettingsPermissionChecks.swift"), "-o", binary,
    ], check=True)
    subprocess.run([binary], check=True)
