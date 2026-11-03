"""Prepare a versioned, runtime-only directory for BigWigsMods/packager -c."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
ADDON = "MessageSplitter"
TOC = f"{ADDON}.toc"
VERSION_LINE = re.compile(rb"(?m)^(## Version:[ \t]*)([^\r\n]+)")
VERSION = re.compile(
    r"(?P<base>\d+(?:\.\d+)+)(?:-?(?P<channel>alpha|beta|a|b)(?P<serial>\d*))?",
    re.IGNORECASE,
)


def parse_version(value):
    match = VERSION.fullmatch(value)
    if not match:
        raise ValueError(f"Unsupported TOC version: {value!r}; use 121.10, 121.10a or 121.10b")
    base, channel, serial = match.group("base", "channel", "serial")
    channel = {"a": "alpha", "b": "beta"}.get((channel or "").lower(), (channel or "").lower())
    return base, channel, serial or ""


def tag_for(version):
    base, channel, serial = parse_version(version)
    return f"v{base}" + (f"-{channel}{serial}" if channel else "")


def next_version(version, branch):
    base, channel, serial = parse_version(version)
    prefix, counter = base.rsplit(".", 1)
    base = f"{prefix}.{int(counter) + 1:0{len(counter)}d}"
    if branch == "dev" and not channel:
        channel = "alpha"
    suffix = {"alpha": "a", "beta": "b"}.get(channel, "")
    return base + suffix + serial


def runtime_files(root):
    """Follow the TOC/XML load tree, then include runtime media, never source tools."""
    files = {"LICENSE"}

    def visit(relative):
        path = (root / relative.replace("\\", "/")).resolve()
        if not path.is_relative_to(root.resolve()) or not path.is_file():
            raise ValueError(f"Missing or unsafe addon file: {relative}")
        name = path.relative_to(root.resolve()).as_posix()
        if name in files:
            return
        files.add(name)
        if path.suffix.lower() == ".toc":
            for line in path.read_text(encoding="utf-8-sig").splitlines():
                if line.strip() and not line.lstrip().startswith("#"):
                    visit((path.parent / line.strip()).relative_to(root).as_posix())
        elif path.suffix.lower() == ".xml":
            for element in ET.parse(path).iter():
                if element.tag.rsplit("}", 1)[-1] in {"Script", "Include"} and "file" in element.attrib:
                    target = path.parent / element.attrib["file"].replace("\\", "/")
                    visit(target.relative_to(root).as_posix())

    visit(TOC)
    media_extensions = {".tga", ".blp", ".png", ".jpg", ".jpeg", ".ogg", ".mp3", ".wav", ".ttf", ".otf"}
    for path in (root / "Media").rglob("*"):
        if path.is_file() and path.suffix.lower() in media_extensions:
            visit(path.relative_to(root).as_posix())
    if not (root / "LICENSE").is_file():
        raise ValueError("LICENSE is required")
    return sorted(files)


def stage(root, destination):
    if destination.exists():
        raise ValueError(f"Staging directory already exists: {destination}")
    for name in runtime_files(root):
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / name, target)


def main():
    ref = os.environ["GITHUB_REF"]
    branch = os.environ["GITHUB_REF_NAME"]
    toc = ROOT / TOC
    content = toc.read_bytes()
    matches = list(VERSION_LINE.finditer(content))
    if len(matches) != 1:
        raise ValueError("Expected exactly one ## Version line in the TOC")
    current = matches[0].group(2).decode("utf-8").strip()
    bumped = not ref.startswith("refs/tags/")
    if bumped and branch not in {"master", "main", "dev"}:
        raise ValueError(f"Releases are not enabled for branch {branch!r}")
    version = next_version(current, branch) if bumped else current
    tag = tag_for(version)
    if not bumped and branch != tag:
        raise ValueError(f"Tag must match TOC version {current}: expected {tag!r}")
    if bumped:
        # Reject stale runs before committing; the atomic push also catches later races.
        remote_head = subprocess.check_output(
            ["git", "ls-remote", "origin", f"refs/heads/{branch}"], cwd=ROOT, text=True
        ).split()[0]
        local_head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        if remote_head != local_head:
            raise ValueError("Branch has moved; release the newest commit instead")
        existing = subprocess.run(["git", "show-ref", "--verify", "--quiet", f"refs/tags/{tag}"], cwd=ROOT)
        if existing.returncode == 0:
            raise ValueError(f"Release tag already exists: {tag}; update the TOC version first")
        if existing.returncode != 1:
            raise RuntimeError("Could not check existing tags")
        content = VERSION_LINE.sub(lambda m: m.group(1) + version.encode(), content, count=1)
        toc.write_bytes(content)
    stage(ROOT, ROOT / ".release" / ADDON)
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        output.write(f"tag={tag}\nversion={version}\nbumped={str(bumped).lower()}\n")
    print(f"Prepared {tag} (TOC {version})")


if __name__ == "__main__":
    main()
