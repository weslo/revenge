"""Tests for check_package.py, using zips built the way the packager should build them.

Run: python -I -m unittest discover -s tools -p "test_*.py"
"""

from __future__ import annotations

import io
import json
import tempfile
import unittest
import zipfile
from contextlib import redirect_stdout
from pathlib import Path

import check_package

ROOT = Path(__file__).resolve().parent.parent
ZIP_NAME = "Revenge-v0.1.0-forever.zip"
MODULE_TOC = "RevengeTracker_OtherAddons/RevengeTracker_OtherAddons.toc"


def addon_files(version: str = "v0.1.0") -> dict[str, bytes]:
    """The real addon folders, with the TOCs' version filled in as the packager does."""
    files = {}
    for folder in ("RevengeTracker", "RevengeTracker_OtherAddons"):
        for path in (ROOT / folder).rglob("*"):
            if path.is_file():
                data = path.read_bytes()
                if path.suffix == ".toc":
                    data = data.replace(b"@project-version@", version.encode())
                files[folder + "/" + path.relative_to(ROOT / folder).as_posix()] = data
    return files


def release_json(flavor: str = "forever", interface: int = 16001, filename: str = ZIP_NAME) -> dict:
    return {"releases": [{"name": "Revenge", "version": "v0.1.0", "filename": filename, "nolib": False,
                          "metadata": [{"flavor": flavor, "interface": interface}]}]}


class CheckPackage(unittest.TestCase):
    def build(self, files: dict[str, bytes], metadata: dict | None = None) -> Path:
        folder = Path(self.enterContext(tempfile.TemporaryDirectory()))
        with zipfile.ZipFile(folder / ZIP_NAME, "w") as archive:
            for name, data in files.items():
                archive.writestr(name, data)
        if metadata is not None:
            (folder / "release.json").write_text(json.dumps(metadata), encoding="utf-8")
        return folder

    def run_check(self, folder: Path, *flags: str) -> tuple[int, str]:
        out = io.StringIO()
        with redirect_stdout(out):
            code = check_package.main([*flags, str(folder)])
        return code, out.getvalue()

    def test_the_addon_folder_as_packaged_passes(self):
        code, out = self.run_check(self.build(addon_files(), release_json()), "--release-json")
        self.assertEqual(code, 0, out)
        self.assertIn("RevengeTracker/Core.lua", out)

    def test_the_toc_lists_every_file_in_the_addon_folder(self):
        problems = check_package.check_zip(self.build(addon_files()) / ZIP_NAME)
        self.assertEqual(problems, [])

    def test_a_leftover_folder_beside_the_addon_fails(self):
        files = addon_files() | {"Revenge/CHANGELOG.md": b"# changes"}
        code, out = self.run_check(self.build(files))
        self.assertEqual(code, 1)
        self.assertIn("files outside RevengeTracker/ and RevengeTracker_OtherAddons/: Revenge", out)

    def test_an_unfilled_version_fails(self):
        code, out = self.run_check(self.build(addon_files("@project-version@")))
        self.assertEqual(code, 1)
        self.assertIn("wasn't filled in", out)

    def test_textures_in_media_need_no_toc_entry(self):
        files = addon_files()
        self.assertIn("RevengeTracker/Media/Skull.tga", files, "the real texture is packaged")
        self.assertEqual(check_package.check_zip(self.build(files) / ZIP_NAME), [])
        files["RevengeTracker/Media/notes.txt"] = b"not a texture"
        problems = check_package.check_zip(self.build(files) / ZIP_NAME)
        self.assertEqual(len(problems), 1)
        self.assertIn("Media/notes.txt", problems[0])

    def test_a_missing_or_unlisted_file_fails(self):
        files = addon_files()
        del files["RevengeTracker/Merge.lua"]
        files["RevengeTracker/Notes.txt"] = b"stray"
        code, out = self.run_check(self.build(files))
        self.assertEqual(code, 1)
        self.assertIn("missing: RevengeTracker/Merge.lua", out)
        self.assertIn("not listed in the TOC: RevengeTracker/Notes.txt", out)

    def test_the_optional_module_is_packaged_load_on_demand(self):
        files = addon_files()
        self.assertIn("RevengeTracker_OtherAddons/Adapters/RevengeBook.lua", files)
        files[MODULE_TOC] = files[MODULE_TOC].replace(b"## LoadOnDemand: 1", b"## LoadOnDemand: 0")
        problems = check_package.check_zip(self.build(files) / ZIP_NAME)
        self.assertEqual(len(problems), 1, problems)
        self.assertIn("must be load-on-demand", problems[0])
        files = addon_files()
        del files[MODULE_TOC]
        problems = check_package.check_zip(self.build(files) / ZIP_NAME)
        self.assertIn(f"no {MODULE_TOC}", problems)

    def test_a_non_forever_interface_fails(self):
        files = addon_files()
        toc = "RevengeTracker/RevengeTracker.toc"
        files[toc] = files[toc].replace(b"## Interface: 16001", b"## Interface: 11508")
        code, out = self.run_check(self.build(files))
        self.assertEqual(code, 1)
        self.assertIn("isn't Forever's", out)

    def test_release_json_must_name_the_zip_as_the_forever_build(self):
        for metadata in (release_json(flavor="classic"), release_json(interface=11508),
                         release_json(filename="Other.zip")):
            with self.subTest(metadata=metadata["releases"][0]):
                code, out = self.run_check(self.build(addon_files(), metadata), "--release-json")
                self.assertEqual(code, 1, out)
        code, out = self.run_check(self.build(addon_files()), "--release-json")
        self.assertIn("no release.json", out)

    def test_no_zip_or_two_zips_fails(self):
        empty = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.assertEqual(self.run_check(empty)[0], 1)
        folder = self.build(addon_files())
        (folder / "Revenge-v0.1.1-forever.zip").write_bytes((folder / ZIP_NAME).read_bytes())
        self.assertEqual(self.run_check(folder)[0], 1)


if __name__ == "__main__":
    unittest.main()
