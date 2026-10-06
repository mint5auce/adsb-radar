import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "github-release.py"


class GitHubReleaseTests(unittest.TestCase):
    def test_publication_refuses_a_tag_moved_after_preparation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "release.json").write_text(json.dumps({"version": "0.2.0", "build": 2}))
            gh = root / "gh"
            gh.write_text(
                f"#!{sys.executable}\n"
                "import json, sys\n"
                "if sys.argv[1:] == ['api', 'repos/example/radar/git/ref/tags/v0.2.0']:\n"
                "    print(json.dumps({'object': {'type': 'commit', 'sha': 'b' * 40}}))\n"
                "else:\n"
                "    sys.exit('Unexpected GitHub request')\n"
            )
            gh.chmod(0o755)
            environment = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"])
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "publish", "--repository", "example/radar",
                 "--directory", str(root), "--source-sha", "a" * 40],
                cwd=root, env=environment, capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("tag no longer", result.stderr)

    def run_preflight(self, releases, version="0.2.0", build=2):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "release.json").write_text(json.dumps({"version": version, "build": build}))
            (root / "api.json").write_text(json.dumps([releases]))
            gh = root / "gh"
            gh.write_text(
                f"#!{sys.executable}\n"
                "import pathlib, sys\n"
                "if sys.argv[1:5] != ['api', '--paginate', '--slurp', 'repos/example/radar/releases']:\n"
                "    sys.exit('Unexpected GitHub request')\n"
                "print(pathlib.Path('api.json').read_text())\n"
            )
            gh.chmod(0o755)
            environment = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"])
            return subprocess.run(
                [sys.executable, str(SCRIPT), "preflight", "--repository", "example/radar"],
                cwd=root, env=environment, capture_output=True, text=True,
            )

    def test_withdrawn_builds_cannot_be_reused(self):
        result = self.run_preflight([
            {"tag_name": "v0.1.0", "draft": False, "prerelease": False,
             "body": "<!-- phosphor-build:5 -->"},
        ])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("higher", result.stderr)

    def test_published_versions_cannot_be_replaced(self):
        result = self.run_preflight([
            {"tag_name": "v0.2.0", "draft": False, "prerelease": False,
             "body": "<!-- phosphor-build:2 -->"},
        ], build=3)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("newer", result.stderr)

    def test_published_release_without_a_build_record_blocks_preparation(self):
        result = self.run_preflight([
            {"tag_name": "v0.1.0", "draft": False, "prerelease": False, "body": "Legacy release"},
        ])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("build record", result.stderr)

    def test_matching_draft_does_not_block_preparation(self):
        result = self.run_preflight([
            {"tag_name": "v0.2.0", "draft": True, "prerelease": False, "body": ""},
        ])
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
