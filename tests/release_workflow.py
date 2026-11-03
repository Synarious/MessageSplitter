"""Version policy and runtime-only release staging (no publishing)."""

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("addon_release", ROOT / ".github/scripts/release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def test_version_channels_and_integer_increment(self):
        cases = [
            ("121.10", "main", "121.11", "v121.11"),
            ("121.10b", "dev", "121.11b", "v121.11-beta"),
            ("12.100", "master", "12.101", "v12.101"),
            ("12.999", "main", "12.1000", "v12.1000"),
            ("12.009", "master", "12.010", "v12.010"),
            ("12.100", "dev", "12.101a", "v12.101-alpha"),
            ("12.100b", "dev", "12.101b", "v12.101-beta"),
            ("12.100a", "master", "12.101a", "v12.101-alpha"),
            ("12.100-beta2", "dev", "12.101b2", "v12.101-beta2"),
        ]
        for current, branch, expected, tag in cases:
            with self.subTest(current=current, branch=branch):
                self.assertEqual(release.next_version(current, branch), expected)
                self.assertEqual(release.tag_for(expected), tag)
        for invalid in ["12.1junk", "12", "12.100ab", "12.100\nextra"]:
            with self.assertRaises(ValueError):
                release.parse_version(invalid)

    def test_real_addon_stage_contains_runtime_and_license_only(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "MessageSplitter"
            release.stage(ROOT, destination)
            files = {p.relative_to(destination).as_posix() for p in destination.rglob("*") if p.is_file()}
            self.assertIn("LICENSE", files)
            self.assertIn("Core.lua", files)
            self.assertIn("Splitter.lua", files)
            self.assertIn("Composer.lua", files)
            self.assertIn("Settings.lua", files)
            self.assertIn("Style.lua", files)
            self.assertIn("Media/Send.tga", files)
            for name in files - {"LICENSE"}:
                self.assertIn(Path(name).suffix.lower(), {".lua", ".xml", ".toc", ".tga"})
            self.assertEqual((destination / release.TOC).read_bytes(), (ROOT / release.TOC).read_bytes())

    def test_tag_build_does_not_bump_and_mismatch_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / release.TOC).write_bytes(b"## Version: 12.101b\r\n")
            (root / "LICENSE").write_text("license")
            env = {"GITHUB_REF": "refs/tags/v12.101-beta", "GITHUB_REF_NAME": "v12.101-beta",
                   "GITHUB_OUTPUT": str(root / "output")}
            with patch.object(release, "ROOT", root), patch.dict(release.os.environ, env):
                release.main()
                self.assertIn("bumped=false", (root / "output").read_text())
                self.assertEqual((root / release.TOC).read_bytes(), b"## Version: 12.101b\r\n")
                with patch.dict(release.os.environ, {"GITHUB_REF_NAME": "v12.999"}):
                    with self.assertRaisesRegex(ValueError, "Tag must match"):
                        release.main()

    def test_missing_loaded_file_fails_packaging(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / release.TOC).write_text("## Version: 12.100\nMissing.lua\n")
            (root / "LICENSE").write_text("license")
            with self.assertRaisesRegex(ValueError, "Missing or unsafe"):
                release.runtime_files(root)

    def test_branch_bump_preserves_toc_and_rejects_stale_or_duplicate_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            toc = root / release.TOC
            original = b"## Interface: 120105\r\n## Version: 12.100\r\n## Title: Example\r\n"
            toc.write_bytes(original)
            (root / "LICENSE").write_text("license")
            env = {"GITHUB_REF": "refs/heads/master", "GITHUB_REF_NAME": "master",
                   "GITHUB_OUTPUT": str(root / "output")}
            with patch.object(release, "ROOT", root), patch.dict(release.os.environ, env):
                with patch.object(release.subprocess, "check_output", side_effect=["new refs/heads/master", "old"]):
                    with self.assertRaisesRegex(ValueError, "Branch has moved"):
                        release.main()
                self.assertEqual(toc.read_bytes(), original)
                with patch.object(release.subprocess, "check_output", side_effect=["same refs/heads/master", "same"]):
                    with patch.object(release.subprocess, "run", return_value=release.subprocess.CompletedProcess([], 0)):
                        with self.assertRaisesRegex(ValueError, "Release tag already exists"):
                            release.main()
                self.assertEqual(toc.read_bytes(), original)
                with patch.object(release.subprocess, "check_output", side_effect=["same refs/heads/master", "same"]):
                    with patch.object(release.subprocess, "run", return_value=release.subprocess.CompletedProcess([], 1)):
                        release.main()
                self.assertEqual(toc.read_bytes(), original.replace(b"12.100", b"12.101"))
                self.assertIn("tag=v12.101\nversion=12.101\nbumped=true\n", (root / "output").read_text())
                self.assertEqual((root / ".release/MessageSplitter" / release.TOC).read_bytes(), toc.read_bytes())


if __name__ == "__main__":
    unittest.main()
