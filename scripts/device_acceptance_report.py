#!/usr/bin/env python3
"""QA-011 device acceptance: turn a DeviceAcceptance run's log into a committed record.

The on-device UI tests (Apps/projectM-iOS/DeviceUITests) print one `DEVICE-ACCEPT {json}` line per measurement and
XCTest prints each test's result. This writes `docs/test-reports/qa-011/acceptance/<device>-<session>.json` (every
measurement, every test's result, the log's SHA-256) and a Markdown summary next to it.

    python3 scripts/device_acceptance_report.py --log <xcodebuild log> --device D1 --session B01 [--xcresult <path>]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "test-reports" / "qa-011" / "acceptance"
CASE = re.compile(r"Test Case '-\[\S+?\.(\w+) (\w+)\]' (passed|failed) \(([\d.]+) seconds\)")


def parse(text: str) -> tuple[list[dict], list[dict]]:
    measurements, tests = [], []
    for line in text.splitlines():
        if "DEVICE-ACCEPT " in line:
            try:
                measurements.append(json.loads(line.split("DEVICE-ACCEPT ", 1)[1]))
            except ValueError:
                pass
        m = CASE.search(line)
        if m:
            tests.append({"class": m.group(1), "test": m.group(2), "result": m.group(3), "seconds": float(m.group(4))})
    return measurements, tests


def summarize(measurements: list[dict]) -> dict[str, dict]:
    by_task: dict[str, dict] = defaultdict(lambda: {"steps": 0, "fpsMedians": [], "fpsMin": None, "checks": {}})
    for m in measurements:
        t = by_task[m["task"]]
        if "fpsMedian" in m:
            t["steps"] += 1
            t["fpsMedians"].append(m["fpsMedian"])
            t["fpsMin"] = m["fpsMin"] if t["fpsMin"] is None else min(t["fpsMin"], m["fpsMin"])
        for key in ("changeFromOff", "motion", "change", "normal", "reduceMotion", "vary", "gradedSaturation",
                    "middleLuma", "edgeLuma", "farCornerLuma"):
            if key in m:
                t["checks"][f"{m['step']}: {key}"] = m[key]
    return dict(sorted(by_task.items()))


def render(record: dict) -> str:
    lines = [f"# QA-011 device acceptance: {record['device']} session {record['session']}", "",
             f"Automated owner-session steps on the device (Apps/projectM-iOS/DeviceUITests). Log SHA-256 "
             f"`{record['logSha256']}`; {record['passed']} of {len(record['tests'])} tests passed.", "",
             "| Task | Frame-rate steps | Median fps | Lowest 1 s fps |", "|---|---|---|---|"]
    for task, t in record["tasks"].items():
        meds = t["fpsMedians"]
        span = f"{min(meds):.0f}–{max(meds):.0f}" if meds else "—"
        lines.append(f"| {task} | {t['steps']} | {span} | {t['fpsMin'] if t['fpsMin'] is not None else '—'} |")
    lines += ["", "| Test | Result | Seconds |", "|---|---|---|"]
    lines += [f"| {t['class']}.{t['test']} | {t['result']} | {t['seconds']:.1f} |" for t in record["tests"]]
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--log", required=True)
    p.add_argument("--device", required=True)
    p.add_argument("--session", required=True)
    p.add_argument("--xcresult")
    args = p.parse_args(argv)
    raw = Path(args.log).read_bytes()
    measurements, tests = parse(raw.decode("utf-8", "replace"))
    record = {"kind": "projectM-iOS.qa011.deviceAcceptance", "schemaVersion": 1, "device": args.device,
              "session": args.session, "logSha256": hashlib.sha256(raw).hexdigest(),
              "xcresult": args.xcresult, "tests": tests, "passed": sum(t["result"] == "passed" for t in tests),
              "tasks": summarize(measurements), "measurements": measurements}
    OUT.mkdir(parents=True, exist_ok=True)
    base = OUT / f"{args.device}-{args.session}"
    base.with_suffix(".json").write_text(json.dumps(record, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    base.with_suffix(".md").write_text(render(record), encoding="utf-8")
    print(f"device_acceptance_report: {base.with_suffix('.json').relative_to(ROOT)} "
          f"({record['passed']}/{len(tests)} passed, {len(record['tasks'])} tasks)")
    return 0 if record["passed"] == len(tests) and tests else 1


if __name__ == "__main__":
    raise SystemExit(main())
