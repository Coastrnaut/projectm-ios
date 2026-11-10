#!/usr/bin/env python3
"""Build the projectM engine as a dynamic `Build/ProjectM.xcframework` (task T065; RI-011; ADR-0004).

The engine is the `Vendor/projectM` submodule, pinned to the owner's fork on the `ios` branch
(ADR-0004). That branch lets the engine's own CMake build Apple framework bundles on iOS
(`ENABLE_MACOS_FRAMEWORK=ON` gives a shallow `projectM-4.framework` with flat headers, the iOS
Info.plist keys and the install name `@rpath/projectM-4.framework/projectM-4`); it is meant to go
upstream as a pull request (`docs/projectm-patches.md`). This script only configures, builds and
installs each slice and combines the slices with `xcodebuild -create-xcframework`.

Slices:
  iphoneos          arm64
  iphonesimulator   arm64 + x86_64

CMake flags (recorded in ADR-0004): CMAKE_SYSTEM_NAME=iOS, CMAKE_OSX_SYSROOT=<sdk>,
CMAKE_OSX_ARCHITECTURES=<archs>, CMAKE_OSX_DEPLOYMENT_TARGET=26.0, CMAKE_BUILD_TYPE=Release,
BUILD_SHARED_LIBS=ON, ENABLE_MACOS_FRAMEWORK=ON, ENABLE_GLES=ON, ENABLE_PLAYLIST=OFF,
ENABLE_SYSTEM_GLM=OFF, ENABLE_SYSTEM_PROJECTM_EVAL=OFF (its default is ON, which would pick up a
host copy), ENABLE_SDL_UI=OFF, BUILD_TESTING=OFF, BUILD_DOCS=OFF, ENABLE_INSTALL=ON.

Clients include `<projectM-4/projectM.h>` and link `projectM-4.framework`. The framework is not
signed here; Xcode signs it when the app embeds it. The LGPL-2.1 obligations (ADR-0005) are why the
engine stays a separate, replaceable dynamic framework.

`Build/ProjectM.xcframework.json` records the submodule commit, the flags and the tool versions.

Usage:
  python3 scripts/build_projectm_xcframework.py [--jobs N] [--keep-build]
Standard library only; needs macOS with Xcode and CMake (versions pinned in ADR-0002).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Vendor" / "projectM"
BUILD = ROOT / "Build"
OUTPUT = BUILD / "ProjectM.xcframework"
WORK = BUILD / "projectm"
FRAMEWORK = "projectM-4"   # the engine's PROJECTM_LIBRARY_BASE_OUTPUT_NAME
DEPLOYMENT_TARGET = "26.0"

SLICES = (
    {"name": "iphoneos", "sdk": "iphoneos", "archs": ("arm64",)},
    {"name": "iphonesimulator", "sdk": "iphonesimulator", "archs": ("arm64", "x86_64")},
)

def cmake_args(slice_: dict, source: Path, build_dir: Path, deployment_target: str = DEPLOYMENT_TARGET) -> list[str]:
    """The CMake configure command for one slice."""
    return [
        "cmake", "-S", str(source), "-B", str(build_dir), "-G", "Unix Makefiles",
        "-DCMAKE_SYSTEM_NAME=iOS",
        f"-DCMAKE_OSX_SYSROOT={slice_['sdk']}",
        f"-DCMAKE_OSX_ARCHITECTURES={';'.join(slice_['archs'])}",
        f"-DCMAKE_OSX_DEPLOYMENT_TARGET={deployment_target}",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DBUILD_SHARED_LIBS=ON",
        "-DENABLE_MACOS_FRAMEWORK=ON",
        "-DENABLE_GLES=ON",
        "-DENABLE_PLAYLIST=OFF",
        "-DENABLE_SYSTEM_GLM=OFF",
        "-DENABLE_SYSTEM_PROJECTM_EVAL=OFF",
        "-DENABLE_SDL_UI=OFF",
        "-DBUILD_TESTING=OFF",
        "-DBUILD_DOCS=OFF",
        "-DENABLE_INSTALL=ON",
    ]


def engine_version(source: Path) -> str:
    """The `project(libprojectM VERSION x.y.z)` value from the engine's CMakeLists.txt."""
    text = (source / "CMakeLists.txt").read_text(encoding="utf-8")
    m = re.search(r"project\(libprojectM[^)]*?VERSION\s+([0-9.]+)", text, re.S)
    if not m:
        raise SystemExit("cannot find the engine version in Vendor/projectM/CMakeLists.txt")
    return m.group(1)


def run(cmd: list[str], **kw) -> str:
    print("+", " ".join(cmd), flush=True)
    return subprocess.run(cmd, check=True, text=True, stdout=subprocess.PIPE if kw.pop("capture", False) else None, **kw).stdout or ""


def installed_framework(stage: Path) -> Path:
    """The framework the engine's `cmake --install` put in `<stage>/lib`."""
    fw = stage / "lib" / f"{FRAMEWORK}.framework"
    if not (fw / FRAMEWORK).is_file() or not (fw / "Headers" / "projectM.h").is_file():
        raise SystemExit(f"{fw} is missing or incomplete: is Vendor/projectM on the fork's ios branch?")
    return fw


def check_install_name(fw: Path) -> None:
    out = run(["otool", "-D", str(fw / FRAMEWORK)], capture=True).split()
    expected = f"@rpath/{FRAMEWORK}.framework/{FRAMEWORK}"
    if not out or out[-1] != expected:
        raise SystemExit(f"{fw}: install name {out[-1] if out else '?'}, expected {expected}")


def tool_version(cmd: list[str]) -> str:
    try:
        return subprocess.run(cmd, check=True, text=True, capture_output=True).stdout.strip().splitlines()[0]
    except (OSError, subprocess.CalledProcessError, IndexError):
        return "unknown"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    parser.add_argument("--keep-build", action="store_true", help="reuse existing CMake build directories")
    args = parser.parse_args(argv)

    if sys.platform != "darwin":
        print("build_projectm_xcframework: needs macOS with Xcode", file=sys.stderr)
        return 2
    if not (SOURCE / "CMakeLists.txt").exists():
        print("Vendor/projectM is empty: run `git submodule update --init --recursive`", file=sys.stderr)
        return 2

    version = engine_version(SOURCE)
    commit = run(["git", "-C", str(SOURCE), "rev-parse", "HEAD"], capture=True).strip()
    if not args.keep_build and WORK.exists():
        shutil.rmtree(WORK)
    frameworks = []
    for s in SLICES:
        build_dir, stage = WORK / s["name"] / "build", WORK / s["name"] / "stage"
        if stage.exists():
            shutil.rmtree(stage)
        run(cmake_args(s, SOURCE, build_dir))
        run(["cmake", "--build", str(build_dir), "--config", "Release", "-j", str(args.jobs)])
        run(["cmake", "--install", str(build_dir), "--prefix", str(stage)])
        fw = installed_framework(stage)
        check_install_name(fw)
        archs = run(["lipo", "-archs", str(fw / FRAMEWORK)], capture=True).split()
        if sorted(archs) != sorted(s["archs"]):
            raise SystemExit(f"{s['name']}: built {archs}, expected {list(s['archs'])}")
        frameworks.append(fw)

    if OUTPUT.exists():
        shutil.rmtree(OUTPUT)
    cmd = ["xcodebuild", "-create-xcframework"]
    for fw in frameworks:
        cmd += ["-framework", str(fw)]
    run(cmd + ["-output", str(OUTPUT)])

    info = {
        "engineCommit": commit,
        "engineVersion": version,
        "deploymentTarget": DEPLOYMENT_TARGET,
        "slices": {s["name"]: {"archs": list(s["archs"]), "cmake": cmake_args(s, Path("Vendor/projectM"), Path(f"Build/projectm/{s['name']}/build"))[7:]} for s in SLICES},
        "tools": {"xcodebuild": tool_version(["xcodebuild", "-version"]), "cmake": tool_version(["cmake", "--version"])},
    }
    (BUILD / "ProjectM.xcframework.json").write_text(json.dumps(info, indent=2) + "\n", encoding="utf-8")
    print(f"built {OUTPUT.relative_to(ROOT)} (projectM {version}, {commit[:12]})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
