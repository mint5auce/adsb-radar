import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "release-metadata.py"


class ReleaseMetadataTests(unittest.TestCase):
    def test_release_tag_and_feed_prevent_reusing_or_decreasing_versions(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "release.json"
            output = Path(directory) / "Info.plist"
            feed = Path(directory) / "appcast.xml"
            manifest.write_text(json.dumps({"version": "0.2.0", "build": 2}))
            feed.write_text('<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>2</sparkle:version></item></channel></rss>')
            for arguments, message in [
                (["--tag", "v0.3.0"], "tag"),
                (["--tag", "v0.2.0", "--previous-appcast", str(feed)], "higher"),
            ]:
                with self.subTest(arguments=arguments):
                    result = subprocess.run(
                        [sys.executable, str(SCRIPT), "--manifest", str(manifest),
                         "--configuration", "release", "--output", str(output), *arguments],
                        capture_output=True, text=True,
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(message, result.stderr)
                    self.assertFalse(output.exists())

    def test_invalid_release_inputs_leave_no_bundle_metadata(self):
        cases = [
            ({"version": "0.2.0", "build": 2}, ["--distribution"], "HTTPS"),
            ({"version": "0.2.0", "build": 2}, ["--distribution", "--feed-url", "http://example.com/appcast.xml"], "HTTPS"),
            ({"version": "0.2.0", "build": 2}, ["--distribution", "--feed-url", "https://example.com/appcast.xml"], "public key"),
            ({"version": "0.2.0", "build": 2}, ["--distribution", "--feed-url", "https://example.com/appcast.xml", "--public-key", "invalid"], "public key"),
            ({"version": "0.2.0", "build": 2}, ["--distribution", "--feed-url", "https://example.com/appcast.xml", "--public-key", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", "--configuration", "debug"], "release configuration"),
            ({"version": "v0.2.0", "build": 2}, [], "version"),
            ({"version": "0.2.0", "build": True}, [], "build"),
            ({"version": "0.2.0", "build": 0}, [], "build"),
        ]
        for release, arguments, message in cases:
            with self.subTest(release=release, arguments=arguments), tempfile.TemporaryDirectory() as directory:
                manifest = Path(directory) / "release.json"
                output = Path(directory) / "Info.plist"
                manifest.write_text(json.dumps(release))
                result = subprocess.run(
                    [sys.executable, str(SCRIPT), "--manifest", str(manifest),
                     "--configuration", "release", "--output", str(output), *arguments],
                    capture_output=True, text=True,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)
                self.assertFalse(output.exists())

    def test_distribution_requires_update_verification_and_disables_profiling(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "release.json"
            output = Path(directory) / "Info.plist"
            manifest.write_text(json.dumps({"version": "0.2.0", "build": 2}))
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--manifest", str(manifest),
                 "--configuration", "release", "--distribution", "--output", str(output),
                 "--feed-url", "https://mint5auce.github.io/adsb-radar/appcast.xml",
                 "--public-key", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            info = plistlib.loads(output.read_bytes())
            self.assertTrue(info["ADSBUpdatesEnabled"])
            self.assertTrue(info["SUVerifyUpdateBeforeExtraction"])
            self.assertTrue(info["SURequireSignedFeed"])
            self.assertFalse(info["SUEnableSystemProfiling"])
            self.assertFalse(info["SUAutomaticallyUpdate"])
            self.assertEqual(info["SUScheduledCheckInterval"], 86400)
            self.assertNotIn("SUEnableAutomaticChecks", info)

    def test_development_bundle_uses_release_version_without_enabling_updates(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "release.json"
            output = Path(directory) / "Info.plist"
            manifest.write_text(json.dumps({"version": "0.2.0", "build": 2}))
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--manifest", str(manifest),
                 "--configuration", "debug", "--output", str(output)],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            info = plistlib.loads(output.read_bytes())
            self.assertEqual(info["CFBundleShortVersionString"], "0.2.0")
            self.assertEqual(info["CFBundleVersion"], "2")
            self.assertFalse(info["ADSBUpdatesEnabled"])
            self.assertNotIn("SUFeedURL", info)
            self.assertNotIn("SUPublicEDKey", info)


if __name__ == "__main__":
    unittest.main()
