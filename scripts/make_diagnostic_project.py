#!/usr/bin/env python3
"""Generate a temporary diagnostic CaptureLab project (owner review 2026-11-08, ADR-0001 ruling 12).

The owner approved temporary diagnostic builds for T041 and T113. They must never enter the
committed `project.yml`. This script copies `project.yml` with one change into `Build/diagnostic/<variant>/` (gitignored) and generates
`CaptureLab-<variant>.xcodeproj` (gitignored) next to the normal project, which stays untouched.

Variants (the screen-capture-mode variant, build 9001, was retired on 2026-11-09 when ADR-0001
ruling 17 put that background mode into the normal build):
  no-usage-key         CaptureLab has no NSScreenCaptureUsageDescription (T040/T113: does iOS 27
                       require the key?). Build 9002.

Each variant has its own build number (shown as "app build" in every export) and display name, so
its exports are never mistaken for the normal build. Diagnostic exports are never FR-031
compatibility evidence.

Usage:
  python3 scripts/make_diagnostic_project.py no-usage-key
  open CaptureLab-no-usage-key.xcodeproj
Standard library only; needs XcodeGen (macOS).
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = ROOT / "project.yml"
OUT_ROOT = ROOT / "Build" / "diagnostic"

# variant -> (build number, display-name suffix)
VARIANTS: dict[str, tuple[str, str]] = {
    "no-usage-key": ("9002", "no key"),
}

USAGE_KEY_LINE = "        NSScreenCaptureUsageDescription:"


# Stage 2 entries a CaptureLab diagnostic project leaves out: they need the engine and ANGLE
# binaries and have nothing to do with the capture question a variant answers.
STAGE2_PACKAGES = ("ProjectMBridge", "Rendering", "ANGLERendering")
STAGE2_TARGETS = ("ProjectMiOS", "ProjectMiOSTests", "ProjectMiOSUITests")


def remove_block(text: str, section: str, name: str) -> str:
    """Removes `  name:` and its indented body from the top-level `section:` of the spec."""
    lines = text.split("\n")
    try:
        sec = lines.index(f"{section}:")
    except ValueError:
        return text
    out, i = lines[:sec + 1], sec + 1
    while i < len(lines):
        line = lines[i]
        if line and not line.startswith(" ") and not line.startswith("#"):
            out.extend(lines[i:])   # next top-level section
            break
        if line == f"  {name}:":
            i += 1
            while i < len(lines) and (lines[i].startswith("   ") or lines[i] == ""
                                      or (lines[i].startswith("  #") and not lines[i].startswith("  # "))):
                i += 1
            continue
        out.append(line)
        i += 1
    return "\n".join(out)


def variant_spec(text: str, variant: str) -> str:
    """The committed spec with the variant's change; raises if the spec no longer matches."""
    build, suffix = VARIANTS[variant]
    out = text.replace("name: ProjectM-iOS\n", f"name: CaptureLab-{variant}\n", 1)
    for name in STAGE2_PACKAGES:
        out = remove_block(out, "packages", name)
    for name in STAGE2_TARGETS:
        out = remove_block(out, "targets", name)
    out = remove_block(out, "schemes", "ProjectMiOS")
    out = "\n".join(l for l in out.split("\n")
                    if not (l.startswith("  # ") and ("ProjectMiOS" in l or "Build/ANGLEFrameworks" in l
                                                       or "engine-xcframework" in l)))
    # The normal Info.plist sits in the source folder; keep it out of this variant's resources.
    out = out.replace('          - "UITests/**"\n', '          - "UITests/**"\n          - "Info.plist"\n', 1)
    out = out.replace("      path: Apps/CaptureLab/Info.plist\n",
                      f"      path: Build/diagnostic/{variant}/Info.plist\n", 1)
    out = out.replace("        CFBundleDisplayName: CaptureLab\n",
                      f"        CFBundleDisplayName: \"CaptureLab {suffix}\"\n"
                      f"        CFBundleVersion: \"{build}\"\n", 1)
    if variant == "no-usage-key":
        # Only CaptureLab's own key: other app targets (ProjectMiOS) declare it too.
        lines = out.split("\n")
        try:
            start = lines.index("  CaptureLab:")
        except ValueError:
            raise ValueError("CaptureLab target not found") from None
        end = next((i for i in range(start + 1, len(lines))
                    if lines[i].startswith("  ") and not lines[i].startswith("   ") and lines[i].endswith(":")), len(lines))
        hits = [i for i in range(start, end) if lines[i].startswith(USAGE_KEY_LINE)]
        if len(hits) != 1:
            raise ValueError("NSScreenCaptureUsageDescription line not found exactly once in the CaptureLab target")
        del lines[hits[0]]
        out = "\n".join(lines)
    for marker in ('- "Info.plist"', f"CaptureLab-{variant}", f"CFBundleVersion: \"{build}\"",
                   f"Build/diagnostic/{variant}/Info.plist", f"CaptureLab {suffix}"):
        if marker not in out:
            raise ValueError(f"project.yml changed; could not apply {marker!r}")
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("variant", choices=sorted(VARIANTS))
    parser.add_argument("--no-generate", action="store_true", help="write the spec only (tests)")
    args = parser.parse_args(argv)

    out_dir = OUT_ROOT / args.variant
    out_dir.mkdir(parents=True, exist_ok=True)
    spec = out_dir / "project.yml"
    spec.write_text(variant_spec(SPEC.read_text(encoding="utf-8"), args.variant), encoding="utf-8")
    print(f"spec: {spec.relative_to(ROOT)}")
    if args.no_generate:
        return 0
    if shutil.which("xcodegen") is None:
        print("error: xcodegen not found", file=sys.stderr)
        return 2
    # The .xcodeproj goes to the repository root (gitignored, like the normal project), because
    # Xcode resolves INFOPLIST_FILE relative to the project's folder.
    subprocess.run(["xcodegen", "generate", "--quiet", "--spec", str(spec), "--project", str(ROOT),
                    "--project-root", str(ROOT)], check=True)
    print(f"project: CaptureLab-{args.variant}.xcodeproj")
    print(f"Build {VARIANTS[args.variant][0]}: diagnostic only, never FR-031 evidence. "
          "Set the signing team by hand.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
