import plistlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ENTITLEMENTS = ROOT / "DynamicIsland" / "DynamicIsland.entitlements"
PROJECT = ROOT / "DynamicIsland.xcodeproj" / "project.pbxproj"
CI_WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"


class PrivacyConfigurationTests(unittest.TestCase):
    def test_media_key_startup_checks_permission_without_prompting(self):
        interceptor = (ROOT / "DynamicIsland/managers/MediaKeyInterceptor.swift").read_text()
        prompt_sources = [
            path.relative_to(ROOT / "DynamicIsland").as_posix()
            for path in (ROOT / "DynamicIsland").rglob("*.swift")
            if "AXIsProcessTrustedWithOptions(" in path.read_text()
        ]
        self.assertEqual(prompt_sources, ["helpers/AccessibilityPermissionStore.swift"])
        install_tap = interceptor.split("private func installTap() -> Bool {", 1)[1]
        self.assertLess(
            install_tap.index("guard AXIsProcessTrusted() else { return false }"),
            install_tap.index("CGEvent.tapCreate("),
        )

    def test_camera_capture_is_explicitly_entitled(self):
        entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())

        self.assertTrue(entitlements.get("com.apple.security.device.camera"))

    def test_notes_sync_is_authorized_for_apple_events(self):
        project = PROJECT.read_text()
        entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())

        self.assertNotIn("AUTOMATION_APPLE_EVENTS = NO;", project)
        self.assertIn(
            "com.apple.Notes",
            entitlements["com.apple.security.temporary-exception.apple-events"],
        )

    def test_automation_usage_text_names_notes(self):
        project = PROJECT.read_text()

        self.assertEqual(
            2,
            project.count(
                'INFOPLIST_KEY_NSAppleEventsUsageDescription = "Eave uses AppleScripts to control Spotify, Apple Music, and Notes.";'
            ),
        )

    def test_full_access_reminder_api_has_matching_usage_text(self):
        project = PROJECT.read_text()

        self.assertEqual(
            2,
            project.count("INFOPLIST_KEY_NSRemindersFullAccessUsageDescription ="),
        )

    def test_ci_checks_the_privacy_configuration(self):
        workflow = CI_WORKFLOW.read_text()

        self.assertIn("python3 -m unittest tests.test_privacy_configuration", workflow)


if __name__ == "__main__":
    unittest.main()
