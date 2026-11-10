#!/usr/bin/env python3
"""Build ANGLE (Metal backend) as iOS xcframeworks from a pinned source (task T076; ADR-0003 Option B;
ADR-0004).

ANGLE ships two libraries, so the output is two xcframeworks:
  Build/ANGLEFrameworks/libEGL.xcframework      (libEGL.framework: device arm64; simulator arm64 + x86_64)
  Build/ANGLEFrameworks/libGLESv2.xcframework   (libGLESv2.framework, same slices)
plus Build/ANGLEFrameworks/licenses/ (ANGLE's LICENSE and those of the third-party code compiled into
the frameworks) and Build/ANGLEFrameworks/ANGLE.json (commits, GN arguments, tool versions).
(Not "Build/ANGLE": macOS volumes are usually case-insensitive, and that name once matched an ANGLE
checkout in Build/angle, which the output cleanup then deleted.)

Source: the Vendor/angle submodule, the owner's fork https://github.com/Coastrnaut/angle (branch
`ios`, a mirror of https://chromium.googlesource.com/angle/angle), pinned at ANGLE_COMMIT (ADR-0004).
Its third-party dependencies come from `gclient sync` (about 12 GB, all gitignored inside the
checkout), with Chromium's depot_tools at DEPOT_TOOLS_COMMIT in Build/depot_tools. The build uses the
`gn` and `ninja` that the ANGLE checkout itself pins (buildtools/mac/gn, third_party/ninja/ninja).

GN arguments (every slice): target_os="ios", is_debug=false, is_component_build=false,
symbol_level=0, angle_enable_metal=true, and every other backend off (gl, vulkan, swiftshader,
null, wgpu), angle_build_tests=false, ios_enable_code_signing=false (Xcode signs on embed),
ios_deployment_target="26.0", treat_warnings_as_errors=false; target_environment and target_cpu
per slice.

Usage:
  python3 scripts/build_angle_xcframework.py [--skip-sync] [--jobs N]
Standard library only; needs macOS with Xcode and network access for the first sync.
"""
from __future__ import annotations

import argparse
import json
import plistlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Vendor" / "angle"
DEPOT_TOOLS = ROOT / "Build" / "depot_tools"
OUTPUT = ROOT / "Build" / "ANGLEFrameworks"
STAGING = ROOT / "Build" / "ANGLEFrameworks-staging"

ANGLE_COMMIT = "29d18232e8031430f1257b7509ceca20d195114d"   # chromium/8153
DEPOT_TOOLS_URL = "https://chromium.googlesource.com/chromium/tools/depot_tools.git"
DEPOT_TOOLS_COMMIT = "c4cdaeebba9b9ed92d041997317ffdbd042158ac"
DEPLOYMENT_TARGET = "26.0"
# CFBundleShortVersionString for the ANGLE frameworks (App Store Connect requires one).
BUNDLE_SHORT_VERSION = "1.0"
LIBRARIES = ("libEGL", "libGLESv2")

SLICES = (
    {"name": "ios-arm64", "environment": "device", "cpu": "arm64"},
    {"name": "ios-sim-arm64", "environment": "simulator", "cpu": "arm64"},
    {"name": "ios-sim-x64", "environment": "simulator", "cpu": "x64"},
)

# Third-party code compiled into the frameworks (`gn desc ... deps --all`), with its license file.
LICENSE_FILES = {
    "ANGLE": "LICENSE",
    "libc++": "third_party/libc++/src/LICENSE.TXT",
    "libc++abi": "third_party/libc++abi/src/LICENSE.TXT",
    "abseil-cpp": "third_party/abseil-cpp/LICENSE",
    "astc-encoder": "third_party/astc-encoder/src/LICENSE.txt",
    "llvm-libc": "third_party/llvm-libc/src/LICENSE.TXT",
    "perfetto": "third_party/perfetto/LICENSE",
    "protobuf": "third_party/protobuf/LICENSE",
    "vulkan-headers": "third_party/vulkan-headers/LICENSE.txt",
    "zlib": "third_party/zlib/LICENSE",
}


def gn_args(slice_: dict) -> str:
    """The GN arguments for one slice."""
    args = {
        "target_os": '"ios"',
        "target_environment": f'"{slice_["environment"]}"',
        "target_cpu": f'"{slice_["cpu"]}"',
        "is_debug": "false",
        "is_component_build": "false",
        "symbol_level": "0",
        "angle_enable_metal": "true",
        "angle_enable_gl": "false",
        "angle_enable_vulkan": "false",
        "angle_enable_swiftshader": "false",
        "angle_enable_null": "false",
        "angle_enable_wgpu": "false",
        "angle_build_tests": "false",
        "ios_enable_code_signing": "false",
        "ios_deployment_target": f'"{DEPLOYMENT_TARGET}"',
        "treat_warnings_as_errors": "false",
    }
    return " ".join(f"{k}={v}" for k, v in args.items())


def run(cmd: list[str], cwd: Path | None = None, capture: bool = False, env: dict | None = None) -> str:
    print("+", " ".join(cmd), flush=True)
    result = subprocess.run(cmd, cwd=cwd, check=True, text=True, env=env,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout or ""


def tool_env() -> dict:
    env = dict(os.environ)
    env["PATH"] = f"{DEPOT_TOOLS}{os.pathsep}{env.get('PATH', '')}"
    env["DEPOT_TOOLS_UPDATE"] = "0"
    env["DEPOT_TOOLS_METRICS"] = "0"
    return env


def head(repo: Path) -> str:
    return run(["git", "-C", str(repo), "rev-parse", "HEAD"], capture=True).strip()


def remove_tree(path: Path) -> None:
    """Deletes `path`, but never a folder that is, or contains, the ANGLE source or depot_tools."""
    if not path.exists():
        return
    for keep in (SOURCE, DEPOT_TOOLS):
        if keep.exists() and (os.path.samefile(path, keep) or
                              str(keep.resolve()).lower().startswith(str(path.resolve()).lower() + os.sep)):
            raise SystemExit(f"refusing to delete {path}: it holds {keep}")
    shutil.rmtree(path)


def ensure_source(skip_sync: bool) -> None:
    if not (DEPOT_TOOLS / ".git").exists():
        DEPOT_TOOLS.parent.mkdir(parents=True, exist_ok=True)
        run(["git", "clone", "--filter=blob:none", DEPOT_TOOLS_URL, str(DEPOT_TOOLS)])
    if head(DEPOT_TOOLS) != DEPOT_TOOLS_COMMIT:
        run(["git", "-C", str(DEPOT_TOOLS), "fetch", "origin", DEPOT_TOOLS_COMMIT])
        run(["git", "-C", str(DEPOT_TOOLS), "checkout", "-q", DEPOT_TOOLS_COMMIT])
    fresh = not (SOURCE / ".git").exists()
    if fresh:
        run(["git", "-C", str(ROOT), "submodule", "update", "--init", "--depth", "1", "Vendor/angle"])
    moved = head(SOURCE) != ANGLE_COMMIT
    if moved:
        raise SystemExit(f"Vendor/angle is at {head(SOURCE)}, but the pin is {ANGLE_COMMIT}: "
                         "run `git submodule update Vendor/angle` (or move the pin in ADR-0004)")
    gclient = SOURCE / ".gclient"
    if not gclient.exists():
        run([sys.executable, "scripts/bootstrap.py"], cwd=SOURCE, env=tool_env())
    text = gclient.read_text(encoding="utf-8")
    if "target_os = ['ios']" not in text:
        lines = [line for line in text.splitlines() if not line.startswith("target_os")]
        gclient.write_text("\n".join(lines + ["target_os = ['ios']", ""]), encoding="utf-8")
    if fresh or moved or not skip_sync:
        run(["gclient", "sync", "--no-history", "--shallow", "-D", "--jobs", "16"], cwd=SOURCE, env=tool_env())


def build_slice(slice_: dict, jobs: int) -> Path:
    out = SOURCE / "out" / slice_["name"]
    run([str(SOURCE / "buildtools/mac/gn"), "gen", str(out), f"--args={gn_args(slice_)}"], cwd=SOURCE)
    run([str(SOURCE / "third_party/ninja/ninja"), "-C", str(out), "-j", str(jobs), *LIBRARIES], cwd=SOURCE)
    return out


def check_framework(fw: Path, library: str, archs: set[str]) -> None:
    binary = fw / library
    found = set(run(["lipo", "-archs", str(binary)], capture=True).split())
    if found != archs:
        raise SystemExit(f"{binary}: architectures {sorted(found)}, expected {sorted(archs)}")
    install_name = run(["otool", "-D", str(binary)], capture=True).split()[-1]
    if install_name != f"@rpath/{library}.framework/{library}":
        raise SystemExit(f"{binary}: install name {install_name}")


def complete_info_plist(fw: Path) -> None:
    """GN's framework Info.plist lacks keys App Store Connect requires of every embedded framework
    (error 90057: CFBundleShortVersionString); add them, plus MinimumOSVersion."""
    path = fw / "Info.plist"
    info = plistlib.loads(path.read_bytes())
    info.setdefault("CFBundleShortVersionString", BUNDLE_SHORT_VERSION)
    info.setdefault("MinimumOSVersion", DEPLOYMENT_TARGET)
    path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_XML))


def tool_version(cmd: list[str]) -> str:
    try:
        return subprocess.run(cmd, check=True, text=True, capture_output=True).stdout.strip().splitlines()[0]
    except (OSError, subprocess.CalledProcessError, IndexError):
        return "unknown"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--skip-sync", action="store_true", help="skip gclient sync when the checkout is already at the pin")
    parser.add_argument("--jobs", type=int, default=os.cpu_count() or 8)
    args = parser.parse_args(argv)
    if sys.platform != "darwin":
        print("build_angle_xcframework: needs macOS with Xcode", file=sys.stderr)
        return 2

    ensure_source(args.skip_sync)
    outs = {s["name"]: build_slice(s, args.jobs) for s in SLICES}

    remove_tree(OUTPUT)
    remove_tree(STAGING)
    staging = STAGING
    for library in LIBRARIES:
        device = staging / "device" / f"{library}.framework"
        shutil.copytree(outs["ios-arm64"] / f"{library}.framework", device, symlinks=True)
        check_framework(device, library, {"arm64"})
        complete_info_plist(device)
        # One simulator framework with both architectures.
        sim = staging / "simulator" / f"{library}.framework"
        shutil.copytree(outs["ios-sim-arm64"] / f"{library}.framework", sim, symlinks=True)
        run(["lipo", "-create",
             str(outs["ios-sim-arm64"] / f"{library}.framework" / library),
             str(outs["ios-sim-x64"] / f"{library}.framework" / library),
             "-output", str(sim / library)])
        check_framework(sim, library, {"arm64", "x86_64"})
        complete_info_plist(sim)
        run(["xcodebuild", "-create-xcframework", "-framework", str(device), "-framework", str(sim),
             "-output", str(OUTPUT / f"{library}.xcframework")])

    licenses = OUTPUT / "licenses"
    licenses.mkdir(parents=True)
    for name, rel in LICENSE_FILES.items():
        shutil.copy2(SOURCE / rel, licenses / f"{name}.txt")

    info = {
        "angleCommit": head(SOURCE),
        "depotToolsCommit": head(DEPOT_TOOLS),
        "deploymentTarget": DEPLOYMENT_TARGET,
        "slices": {s["name"]: gn_args(s) for s in SLICES},
        "tools": {"xcodebuild": tool_version(["xcodebuild", "-version"])},
    }
    if info["angleCommit"] != ANGLE_COMMIT:
        raise SystemExit(f"ANGLE checkout is at {info['angleCommit']}, expected {ANGLE_COMMIT}")
    (OUTPUT / "ANGLE.json").write_text(json.dumps(info, indent=2) + "\n", encoding="utf-8")
    print(f"built {OUTPUT.relative_to(ROOT)} (ANGLE {ANGLE_COMMIT[:12]})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
