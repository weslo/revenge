"""Check the zip the BigWigs packager built, before and after it's released.

Usage: python -I tools/check_package.py [--release-json] [RELEASE_DIR]

RELEASE_DIR defaults to .release, where the packager writes. Exit code 1 if:
- there isn't exactly one zip;
- the zip holds anything outside the RevengeTracker folder (the plan, tests or tools, or a
  leftover "Revenge" folder from a packaging mistake);
- the TOC is missing, its interface isn't Forever's (16000-19999), or its version is still
  the @project-version@ placeholder;
- a file the TOC lists is missing, or there's a file the TOC doesn't list;
- with --release-json: release.json doesn't list the zip with flavor "forever" and a Forever
  interface. That entry is how instawow picks this build.
"""

from __future__ import annotations

import json
import sys
import zipfile
from pathlib import Path

FOLDER = "RevengeTracker"
TOC = f"{FOLDER}/{FOLDER}.toc"
FOREVER = range(16000, 20000)


def read_toc(text: str) -> tuple[dict[str, str], list[str]]:
    """Return the TOC's ## fields and the files it lists, with forward slashes."""
    fields: dict[str, str] = {}
    files: list[str] = []
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("##"):
            key, _, value = line[2:].partition(":")
            fields[key.strip()] = value.strip()
        elif line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return fields, files


def check_zip(path: Path) -> list[str]:
    problems: list[str] = []
    with zipfile.ZipFile(path) as archive:
        names = [n for n in archive.namelist() if not n.endswith("/")]
        outside = sorted({n.split("/", 1)[0] for n in names if not n.startswith(FOLDER + "/")})
        if outside:
            problems.append(f"files outside {FOLDER}/: {', '.join(outside)}")
        if TOC not in names:
            problems.append(f"no {TOC}")
            return problems
        fields, listed = read_toc(archive.read(TOC).decode("utf-8-sig"))

    interfaces = [part.strip() for part in fields.get("Interface", "").split(",")]
    if not all(part.isdigit() and int(part) in FOREVER for part in interfaces):
        problems.append(f"interface {fields.get('Interface')!r} isn't Forever's (16000-19999)")
    version = fields.get("Version", "")
    if not version or "@" in version:
        problems.append(f"version {version!r} wasn't filled in by the packager")

    expected = {f"{FOLDER}/{name}" for name in listed} | {TOC}
    inside = {n for n in names if n.startswith(FOLDER + "/")}
    missing = sorted(expected - inside)
    extra = sorted(inside - expected)
    if missing:
        problems.append(f"listed in the TOC but missing: {', '.join(missing)}")
    if extra:
        problems.append(f"not listed in the TOC: {', '.join(extra)}")
    return problems


def check_release_json(release_dir: Path, zip_name: str) -> list[str]:
    path = release_dir / "release.json"
    if not path.is_file():
        return ["no release.json"]
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except ValueError as error:
        return [f"release.json isn't valid JSON: {error}"]
    entries = [r for r in data.get("releases", []) if r.get("filename") == zip_name and not r.get("nolib")]
    if not entries:
        return [f"release.json has no entry for {zip_name}"]
    for meta in entries[0].get("metadata", []):
        if meta.get("flavor") == "forever" and meta.get("interface") in FOREVER:
            return []
    return [f"release.json lists {zip_name} without flavor 'forever' and a Forever interface"]


def main(argv: list[str]) -> int:
    want_json = "--release-json" in argv
    args = [a for a in argv if a != "--release-json"]
    release_dir = Path(args[0] if args else ".release")
    zips = sorted(p for p in release_dir.glob("*.zip") if not p.stem.endswith("-nolib"))
    if len(zips) != 1:
        print(f"Expected one zip in {release_dir}, found {len(zips)}: {[z.name for z in zips]}")
        return 1
    package = zips[0]
    with zipfile.ZipFile(package) as archive:
        print(f"{package.name}:")
        for info in archive.infolist():
            if not info.is_dir():
                print(f"  {info.file_size:>8}  {info.filename}")
    problems = check_zip(package)
    if want_json:
        problems += check_release_json(release_dir, package.name)
    for problem in problems:
        print(f"PROBLEM: {problem}")
    if not problems:
        print("Package looks right." + (" release.json names it as the Forever build." if want_json else ""))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
