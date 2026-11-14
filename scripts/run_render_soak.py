#!/usr/bin/env python3
"""QA-006: run the on-demand render soak (specs/155-qa-006-render-soak, research QA-006-D8).

The normal test suites run a short soak (60 s simulated). This script runs a long one:

    python3 scripts/run_render_soak.py --seconds 600                       # scene soak on the macOS host
    python3 scripts/run_render_soak.py --seconds 600 --simulator <udid>    # scene soak on a simulator
    python3 scripts/run_render_soak.py --seconds 600 --simulator <udid> --angle   # + projectM preset soak

It sets QA006_SOAK_SECONDS and QA006_REPORT_DIR (passed to simulator tests as TEST_RUNNER_*), runs the
tests, then reads every JSON report in the report folder and prints its verdict. Exit status: 0 when every
report passed, 1 when any failed or none was written, 2 for bad arguments. `--dry-run` prints the commands.
Simulator and host results are not device evidence; the device run is QA-006-T13 {device}.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCENE_TEST = "RenderSoakTests/testOnDemandLongSoak"
ANGLE_TEST = "ProjectMPresetSoakTests"


def parse(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--seconds", type=float, required=True, help="simulated seconds (> 0)")
    p.add_argument("--simulator", metavar="UDID", help="run on this simulator instead of the macOS host")
    p.add_argument("--angle", action="store_true", help="also run the projectM preset soak (needs --simulator)")
    p.add_argument("--report-dir", type=Path, help="where reports go (default: a new temporary folder)")
    p.add_argument("--derived-data", type=Path, help="xcodebuild -derivedDataPath (simulator runs)")
    p.add_argument("--dry-run", action="store_true", help="print the commands without running them")
    args = p.parse_args(argv)
    if not args.seconds > 0:
        p.error("--seconds must be > 0")
    if args.angle and not args.simulator:
        p.error("--angle needs --simulator (ANGLE has no macOS host build)")
    return args


def environment(seconds: float, report_dir: Path, simulator: bool) -> dict[str, str]:
    """The variables the soak tests read; xcodebuild forwards TEST_RUNNER_<name> to the test process."""
    values = {"QA006_SOAK_SECONDS": f"{seconds:g}", "QA006_REPORT_DIR": str(report_dir)}
    if simulator:
        return {f"TEST_RUNNER_{k}": v for k, v in values.items()}
    return values


def commands(args: argparse.Namespace) -> list[tuple[list[str], Path]]:
    """(command, working directory) pairs to run, in order."""
    out: list[tuple[list[str], Path]] = []
    goldens = ROOT / "Packages" / "RenderGoldens"
    if not args.simulator:
        out.append((["swift", "test", "--filter", SCENE_TEST], goldens))
        return out
    common = ["-destination", f"id={args.simulator}", "CODE_SIGNING_ALLOWED=NO", "-test-timeouts-enabled", "YES",
              "-default-test-execution-time-allowance", str(max(180, int(args.seconds * 2)))]
    if args.derived_data:
        common += ["-derivedDataPath", str(args.derived_data)]
    out.append((["xcodebuild", "test", "-scheme", "RenderGoldens", f"-only-testing:RenderGoldensTests/{SCENE_TEST}"] + common,
                goldens))
    if args.angle:
        out.append((["xcodebuild", "test", "-scheme", "ANGLERendering", f"-only-testing:ANGLERenderingTests/{ANGLE_TEST}"] + common,
                    ROOT / "Packages" / "ANGLERendering"))
    return out


def summarize(report_dir: Path) -> tuple[bool, list[str]]:
    """(all passed, one line per report). No report counts as a failure."""
    lines: list[str] = []
    ok = True
    reports = sorted(report_dir.glob("*.json"))
    if not reports:
        return False, [f"no soak report in {report_dir}"]
    for path in reports:
        try:
            report = json.loads(path.read_text())
            verdict = report["verdict"]
        except (OSError, ValueError, KeyError) as error:
            ok = False
            lines.append(f"{path.name}: unreadable report ({error})")
            continue
        outcome = verdict.get("outcome", "?")
        ok = ok and outcome == "pass"
        rules = ", ".join(verdict.get("failedRules", []))
        lines.append(f"{report.get('name', path.stem)} [{report.get('platform', '?')}]: {outcome}"
                     + (f" [{rules}]" if rules else "")
                     + f"; {report.get('simulatedSeconds', 0):g} s simulated, {report.get('cycles', 0)} cycles,"
                     + f" slope {verdict.get('slopeBytesPerCycle', 0):.0f} B/cycle (limit {verdict.get('slopeLimitBytesPerCycle', 0):.0f}),"
                     + f" errors {verdict.get('errorCount', 0)}; {path}")
    return ok, lines


def main(argv: list[str] | None = None) -> int:
    try:
        args = parse(sys.argv[1:] if argv is None else argv)
    except SystemExit as exit_:
        return 2 if exit_.code else 0
    report_dir = args.report_dir or Path(tempfile.mkdtemp(prefix="qa006-soak-"))
    env_extra = environment(args.seconds, report_dir.resolve(), bool(args.simulator))
    plan = commands(args)
    for command, cwd in plan:
        print(f"(cd {cwd} && {' '.join(f'{k}={v}' for k, v in env_extra.items())} {' '.join(command)})")
    if args.dry_run:
        return 0
    report_dir.mkdir(parents=True, exist_ok=True)
    failed_run = False
    for command, cwd in plan:
        result = subprocess.run(command, cwd=cwd, env={**os.environ, **env_extra})
        failed_run = failed_run or result.returncode != 0
    ok, lines = summarize(report_dir)
    for line in lines:
        print(line)
    if failed_run:
        print("a test command failed (see its output above)")
    return 0 if ok and not failed_run else 1


if __name__ == "__main__":
    sys.exit(main())
