#!/usr/bin/env python3
"""Prepare a fresh checkout on a new Mac (SETUP.md). Safe to run again: it skips finished steps.

It checks the pinned tools, fetches the submodules, restores the machine-local files that git does
not carry (the Spec Kit feature pointer, Claude's memory files), gets the engine and ANGLE
xcframeworks, and generates the Xcode projects. It never installs software and never touches
signing: `Configs/Signing.local.xcconfig` is the owner's to create (CLAUDE.md, "Signing is manual").

    python3 scripts/setup_mac.py                 # everything except ANGLE
    python3 scripts/setup_mac.py --angle ci      # ANGLE xcframeworks from the newest green CI run
    python3 scripts/setup_mac.py --angle build   # ANGLE from source (about 12 GB of dependencies)
    python3 scripts/setup_mac.py --dry-run       # print the commands only
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "Build"
ENGINE = BUILD / "ProjectM.xcframework"
ANGLE = BUILD / "ANGLEFrameworks"
ANGLE_LIBRARIES = ("libEGL.xcframework", "libGLESv2.xcframework")
SIGNING = ROOT / "Configs" / "Signing.local.xcconfig"
FEATURE_POINTER = ROOT / ".specify" / "feature.json"
MEMORY_EXPORT = ROOT / "docs" / "claude-memory"
PRESET_PACKS = ("cream-of-the-crop", "projectm-classic", "milkdrop-original", "en-d",
                "milkdrop-texture-pack")
PROJECT_SPECS = ("project.yml", "RendererLab.yml")
# command -> how to get it when it is missing
TOOLS = {
    "xcodebuild": "install Xcode (the build pinned in ADR-0002) and run it once",
    "xcodegen": "brew install xcodegen (the version pinned in ADR-0002)",
    "cmake": "brew install cmake (the version pinned in ADR-0002)",
    "gh": "brew install gh, then `gh auth login`",
    "git": "xcode-select --install",
}


def memory_dir(checkout: Path, home: Path) -> Path:
    """Claude Code's memory folder for a checkout: the absolute path with "/" and "." as "-"."""
    slug = re.sub(r"[^A-Za-z0-9]", "-", str(checkout))
    return home / ".claude" / "projects" / slug / "memory"


def latest_feature(specs: Path) -> str | None:
    """The newest `specs/NNN-name` folder, as a repo-relative path."""
    names = sorted(p.name for p in specs.iterdir() if p.is_dir() and re.match(r"\d{3}-", p.name)) \
        if specs.is_dir() else []
    return f"specs/{names[-1]}" if names else None


def angle_ready(folder: Path = ANGLE) -> bool:
    return all((folder / lib).is_dir() for lib in ANGLE_LIBRARIES)


def missing_tools(which=shutil.which) -> list[str]:
    return [f"{name}: {hint}" for name, hint in TOOLS.items() if which(name) is None]


class Runner:
    def __init__(self, dry_run: bool) -> None:
        self.dry_run = dry_run
        self.notes: list[str] = []

    def run(self, cmd: list[str], check: bool = True) -> int:
        print("+ " + " ".join(cmd), flush=True)
        if self.dry_run:
            return 0
        code = subprocess.run(cmd, cwd=ROOT).returncode
        if code and check:
            raise SystemExit(f"setup_mac: `{' '.join(cmd)}` failed with exit code {code}")
        return code

    def note(self, text: str) -> None:
        self.notes.append(text)


def fetch_submodules(r: Runner) -> None:
    r.run(["git", "submodule", "update", "--init", "--recursive", "Vendor/projectM"])
    r.run(["git", "submodule", "update", "--init", "--depth", "1",
           *[f"Vendor/presets/{name}" for name in PRESET_PACKS]])


def restore_feature_pointer(r: Runner) -> None:
    if FEATURE_POINTER.exists():
        return
    feature = latest_feature(ROOT / "specs")
    if feature is None:
        return
    print(f"write {FEATURE_POINTER.relative_to(ROOT)} -> {feature}")
    if not r.dry_run:
        FEATURE_POINTER.write_text(json.dumps({"feature_directory": feature}, indent=2) + "\n",
                                   encoding="utf-8")


def restore_memory(r: Runner, home: Path) -> None:
    target = memory_dir(ROOT, home)
    for source in sorted(MEMORY_EXPORT.glob("*.md")):
        if source.name == "README.md" or (target / source.name).exists():
            continue
        print(f"copy {source.relative_to(ROOT)} -> {target / source.name}")
        if not r.dry_run:
            target.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target / source.name)


def get_engine(r: Runner) -> None:
    if ENGINE.is_dir():
        print("Build/ProjectM.xcframework: present")
        return
    r.run([sys.executable, "scripts/build_projectm_xcframework.py"])


def green_run_with_angle() -> str | None:
    """The newest successful CI run on main that still has the ANGLEFrameworks artifact."""
    listing = subprocess.run(
        ["gh", "run", "list", "--workflow", "ios-ci.yml", "--branch", "main", "--status", "success",
         "--limit", "20", "--json", "databaseId"], cwd=ROOT, capture_output=True, text=True)
    if listing.returncode:
        return None
    for run in json.loads(listing.stdout or "[]"):
        run_id = str(run["databaseId"])
        artifacts = subprocess.run(
            ["gh", "api", f"repos/{{owner}}/{{repo}}/actions/runs/{run_id}/artifacts",
             "--jq", '.artifacts[] | select(.name == "ANGLEFrameworks" and .expired == false) | .name'],
            cwd=ROOT, capture_output=True, text=True)
        if artifacts.returncode == 0 and artifacts.stdout.strip():
            return run_id
    return None


def get_angle(r: Runner, mode: str) -> None:
    if angle_ready():
        print("Build/ANGLEFrameworks: present")
        return
    if mode == "build":
        r.run([sys.executable, "scripts/build_angle_xcframework.py"])
    elif mode == "ci":
        run_id = "<run id>" if r.dry_run else green_run_with_angle()
        if run_id is None:
            r.note("ANGLE: no green CI run with an unexpired ANGLEFrameworks artifact was found "
                   "(is `gh auth login` done?). Copy Build/ANGLEFrameworks from the old Mac or use "
                   "--angle build.")
            return
        r.run(["gh", "run", "download", run_id, "--name", "ANGLEFrameworks", "--dir", str(ANGLE)])
        r.note(f"ANGLE came from CI run {run_id} (built with CI's Xcode). Rebuild it here with "
               "--angle build before an App Store upload.")
    else:
        r.note("ANGLE: Build/ANGLEFrameworks is missing, so projectM-iOS and RendererLab will not "
               "link. Copy it from the old Mac, or rerun with --angle ci or --angle build.")


def generate_projects(r: Runner) -> None:
    for spec in PROJECT_SPECS:
        r.run(["xcodegen", "generate", "--spec", spec])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--angle", choices=("skip", "ci", "build"), default="skip",
                        help="where Build/ANGLEFrameworks comes from when it is missing")
    parser.add_argument("--no-memory", action="store_true", help="leave Claude's memory folder alone")
    parser.add_argument("--dry-run", action="store_true", help="print the commands, change nothing")
    args = parser.parse_args(argv)
    if sys.platform != "darwin":
        print("setup_mac: needs macOS with Xcode", file=sys.stderr)
        return 2

    missing = missing_tools()
    if missing:
        print("Missing tools (install them, then run this again):\n  " + "\n  ".join(missing),
              file=sys.stderr)
        return 1

    r = Runner(args.dry_run)
    fetch_submodules(r)
    restore_feature_pointer(r)
    if not args.no_memory:
        restore_memory(r, Path.home())
    get_engine(r)
    get_angle(r, args.angle)
    generate_projects(r)
    if r.run([sys.executable, "scripts/verify_environment.py"], check=False):
        r.note("Toolchain: scripts/verify_environment.py reported a version that differs from the "
               "ADR-0002 pins (see its output above).")
    if not SIGNING.exists():
        r.note("Signing: create Configs/Signing.local.xcconfig yourself with "
               "`DEVELOPMENT_TEAM = <team ID>` (SETUP.md step 6). Simulator builds work without it.")

    print("\nsetup_mac: done." + ("" if r.notes else " Nothing left to do."))
    for text in r.notes:
        print(f"  - {text}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
