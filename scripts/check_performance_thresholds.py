#!/usr/bin/env python3
"""QA-010: judge performance measurements against the versioned budgets in docs/performance/thresholds.json.

specs/223-qa-010-performance-thresholds (contract contracts/performance-thresholds.md).

    python3 scripts/check_performance_thresholds.py REPORT [REPORT...] [--device D1] [--simulator]
        [--thresholds FILE] [--thresholds-version N] [--out verdict.json] [--json]

REPORT is a PERF-012 performance report, an AutomationRunner perf001 report or an sc015 launch-sample list. Every
metric the device's class declares reads pass, fail or "not measured" (never pass). Exit status: 0 pass, 1 fail or
incomplete, 2 error. Same inputs, same bytes: sorted keys, input base names only, no timestamps. Simulator and host
results are never evidence. Standard library only.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
THRESHOLDS = ROOT / "docs/performance/thresholds.json"
SCHEMA_VERSION = 1
REPORT_KIND = "projectM-iOS.performanceReport"
VERDICT_KIND = "projectM-iOS.performanceVerdict"
# The fixed catalogue, in output order, with each metric's direction (data-model.md).
CATALOGUE = {
    "fps1sP5": "min",
    "frameIntervalP50Ms": "max",
    "frameIntervalP95Ms": "max",
    "droppedFramePercent": "max",
    "peakMemoryMB": "max",
    "audioAgeP95Ms": "max",
    "coldLaunchMs": "max",
}
DEVICES = {"D1": "iPhone15,4", "D2": "iPad17,3", "D3": "iPad15,7"}   # docs/test-reports/devices.md
SIMULATOR_CLASS = "simulator"


class CheckError(Exception):
    """A reason to judge nothing (contract C2)."""


# MARK: - Thresholds

def load_thresholds(path: Path, pinned: int | None = None) -> dict:
    try:
        doc = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise CheckError(f"invalid thresholds: {Path(path).name}: {error}") from None
    if not isinstance(doc, dict) or doc.get("schemaVersion") != SCHEMA_VERSION:
        found = doc.get("schemaVersion") if isinstance(doc, dict) else None
        raise CheckError(f"unsupported thresholds schemaVersion {found!r} (this checker reads {SCHEMA_VERSION})")
    problems = thresholds_problems(doc)
    if problems:
        raise CheckError("invalid thresholds: " + "; ".join(problems))
    if pinned is not None and doc["thresholdsVersion"] != pinned:
        raise CheckError(f"thresholds version mismatch: file has {doc['thresholdsVersion']}, caller pinned {pinned}")
    return doc


def thresholds_problems(doc: dict) -> list[str]:
    """Structural checks matching docs/performance/thresholds.schema.json."""
    problems = []
    version = doc.get("thresholdsVersion")
    if not isinstance(version, int) or isinstance(version, bool) or version < 1:
        problems.append("thresholdsVersion must be an integer >= 1")
    if not isinstance(doc.get("updated"), str):
        problems.append("updated missing")
    metrics = doc.get("metrics")
    if not isinstance(metrics, dict) or set(metrics) != set(CATALOGUE):
        problems.append(f"metrics must be exactly {sorted(CATALOGUE)}")
    else:
        for name, direction in CATALOGUE.items():
            if not isinstance(metrics[name], dict) or metrics[name].get("direction") != direction:
                problems.append(f"metric {name} must have direction {direction}")
    classes = doc.get("classes")
    if not isinstance(classes, list) or not classes:
        return problems + ["classes must be a non-empty list"]
    ids, models = set(), set()
    for entry in classes:
        if not isinstance(entry, dict):
            problems.append("class must be an object")
            continue
        cid = entry.get("id")
        if not isinstance(cid, str) or cid in ids:
            problems.append(f"class id {cid!r} missing or repeated")
        ids.add(cid)
        if not isinstance(entry.get("evidence"), bool):
            problems.append(f"class {cid}: evidence must be true or false")
        for model in entry.get("models") or []:
            if model in models:
                problems.append(f"model {model} in two classes")
            models.add(model)
        if not entry.get("models"):
            problems.append(f"class {cid}: models missing")
        targets = entry.get("targets")
        if not isinstance(targets, dict) or set(targets) != set(CATALOGUE):
            problems.append(f"class {cid}: targets must cover exactly the catalogue")
            continue
        for name, target in targets.items():
            limit = target.get("limit") if isinstance(target, dict) else None
            if not is_number(limit) or limit < 0 or not str(target.get("basis") or "").strip():
                problems.append(f"class {cid}: {name} needs a limit >= 0 and a basis")
    return problems


def is_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


# MARK: - Inputs

def read_input(path: Path) -> tuple[str, object]:
    """(kind, document) where kind is perf012, perf001 or sc015 (contract C1)."""
    try:
        doc = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        raise CheckError(f"unrecognised input: {Path(path).name} is not readable JSON") from None
    if isinstance(doc, list):
        return "sc015", doc
    if isinstance(doc, dict) and doc.get("kind") == REPORT_KIND:
        if doc.get("schemaVersion") != 1:
            raise CheckError(f"unsupported report: {Path(path).name} schemaVersion {doc.get('schemaVersion')!r}")
        return "perf012", doc
    if isinstance(doc, dict) and "fpsTimerOff" in doc:
        return "perf001", doc
    raise CheckError(f"unrecognised input: {Path(path).name}")


def nearest_rank(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    return ordered[max(1, math.ceil(fraction * len(ordered))) - 1]


def dropped_percent(frame_drops) -> object:
    """100 x skipped / (submitted + skipped) on the device output; None when unavailable."""
    outputs = frame_drops.get("outputs") if isinstance(frame_drops, dict) else None
    for row in outputs or []:
        if isinstance(row, dict) and row.get("output") == "device":
            submitted, skipped = row.get("submitted"), row.get("skipped")
            if submitted is None or skipped is None:
                return None
            if not (is_number(submitted) and is_number(skipped)) or submitted < 0 or skipped < 0:
                return "invalid"
            slots = submitted + skipped
            return None if slots == 0 else 100.0 * skipped / slots
    return None


def extract(kind: str, doc) -> tuple[str | None, dict[str, object]]:
    """(model or None, metric -> raw value) for one input; a value of "invalid" marks an unusable figure."""
    values: dict[str, object] = {}

    def put(name: str, value) -> None:
        if value is None:
            return
        values[name] = value if (is_number(value) and value >= 0) else "invalid"

    if kind == "sc015":
        if doc:
            ok = all(is_number(v) and v >= 0 for v in doc)
            put("coldLaunchMs", max(doc) * 1000.0 if ok else "invalid")
        return None, values
    if kind == "perf012":
        frames = doc.get("frames") or {}
        put("frameIntervalP50Ms", frames.get("p50Ms"))
        put("frameIntervalP95Ms", frames.get("p95Ms"))
        put("droppedFramePercent", dropped_percent(doc.get("frameDrops")))
        peak = ((doc.get("resources") or {}).get("memory") or {}).get("peakFootprintBytes")
        put("peakMemoryMB", peak / 1_000_000 if is_number(peak) else peak)
        return (doc.get("device") or {}).get("model"), values
    samples = doc.get("fpsTimerOff") or []
    if samples:
        ok = all(is_number(v) and v >= 0 for v in samples)
        put("fps1sP5", nearest_rank(samples, 0.05) if ok else "invalid")
    put("droppedFramePercent", dropped_percent(doc.get("frameDrops")))
    put("audioAgeP95Ms", doc.get("audioAgeP95Ms"))
    return doc.get("device"), values


def measure(paths: list[Path]) -> tuple[str | None, dict[str, dict]]:
    """Merges every input: one model; a metric from two inputs keeps the worse value (contract C3)."""
    models: set[str] = set()
    merged: dict[str, dict] = {}
    for path in paths:
        kind, doc = read_input(path)
        model, values = extract(kind, doc)
        if model:
            models.add(str(model))
        for name, value in values.items():
            entry = {"value": value, "source": Path(path).name}
            old = merged.get(name)
            if old is None or value == "invalid":   # an unusable figure anywhere is the worst case
                merged[name] = entry if old is None or old["value"] != "invalid" else old
            elif old["value"] != "invalid":
                worse = value > old["value"] if CATALOGUE[name] == "max" else value < old["value"]
                if worse:
                    merged[name] = entry
    if len(models) > 1:
        raise CheckError(f"mixed device models: {', '.join(sorted(models))}")
    return (models.pop() if models else None), merged


# MARK: - Verdict

def resolve_class(thresholds: dict, model: str | None, simulator: bool) -> dict:
    if simulator:
        for entry in thresholds["classes"]:
            if entry["id"] == SIMULATOR_CLASS:
                return entry
        raise CheckError("unknown device class: the thresholds declare no simulator class")
    if not model:
        raise CheckError("no device model: name one with --device or --model")
    for entry in thresholds["classes"]:
        if model in entry["models"]:
            return entry
    raise CheckError(f"unknown device class: model {model} is in no class of thresholds version {thresholds['thresholdsVersion']}")


def evaluate(thresholds: dict, model: str | None, measured: dict[str, dict], *, simulator: bool = False,
             inputs: list[str] | None = None) -> dict:
    entry = resolve_class(thresholds, model, simulator)
    rows = []
    for name, direction in CATALOGUE.items():
        limit = entry["targets"][name]["limit"]
        row = {"metric": name, "direction": direction, "limit": limit}
        got = measured.get(name)
        if got is None:
            row.update(verdict="not measured", reason="no input provides it")
        elif got["value"] == "invalid":
            row.update(verdict="not measured", reason="invalid value", source=got["source"])
        else:
            value = round(float(got["value"]), 3)
            ok = value <= limit if direction == "max" else value >= limit
            row.update(verdict="pass" if ok else "fail", value=value, source=got["source"])
        rows.append(row)
    verdicts = {row["verdict"] for row in rows}
    overall = "fail" if "fail" in verdicts else ("incomplete" if "not measured" in verdicts else "pass")
    return {
        "kind": VERDICT_KIND, "verdictSchemaVersion": 1,
        "thresholdsVersion": thresholds["thresholdsVersion"], "thresholdsSchemaVersion": thresholds["schemaVersion"],
        "model": model if model else None, "deviceClass": entry["id"], "evidence": entry["evidence"],
        "overall": overall, "metrics": rows, "inputs": sorted(inputs or []),
    }


def error_verdict(reason: str, thresholds: dict | None, inputs: list[str]) -> dict:
    verdict = {"kind": VERDICT_KIND, "verdictSchemaVersion": 1, "overall": "error", "error": reason,
               "inputs": sorted(inputs)}
    if thresholds:
        verdict["thresholdsVersion"] = thresholds["thresholdsVersion"]
        verdict["thresholdsSchemaVersion"] = thresholds["schemaVersion"]
    return verdict


def check(paths: list[Path], *, thresholds_path: Path = THRESHOLDS, pinned: int | None = None,
          model: str | None = None, simulator: bool = False) -> dict:
    """The whole check (contract C1-C4); never raises for a bad input, returns an error verdict instead."""
    names = [Path(p).name for p in paths]
    thresholds = None
    try:
        thresholds = load_thresholds(thresholds_path, pinned)
        found, measured = measure(paths)
        if model and found and model != found:
            raise CheckError(f"mixed device models: {', '.join(sorted({model, found}))}")
        return evaluate(thresholds, found or model, measured, simulator=simulator, inputs=names)
    except CheckError as error:
        return error_verdict(str(error), thresholds, names)


def render_json(verdict: dict) -> str:
    return json.dumps(verdict, indent=2, sort_keys=True) + "\n"


def render_text(verdict: dict) -> str:
    if verdict["overall"] == "error":
        return f"overall: error — {verdict['error']}\n"
    lines = [f"thresholds version {verdict['thresholdsVersion']}, class {verdict['deviceClass']}"
             f" ({verdict['model'] or 'no model'})" + ("" if verdict["evidence"] else ", not evidence")]
    for row in verdict["metrics"]:
        bound = "<=" if row["direction"] == "max" else ">="
        shown = row.get("value", row.get("reason"))
        lines.append(f"{row['metric']}: {row['verdict']} ({shown} vs {bound} {row['limit']})")
    lines.append(f"overall: {verdict['overall']}" + ("" if verdict["evidence"] else " (not evidence)"))
    return "\n".join(lines) + "\n"


def exit_code(verdict: dict) -> int:
    return {"pass": 0, "fail": 1, "incomplete": 1}.get(verdict["overall"], 2)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("reports", nargs="+", type=Path)
    parser.add_argument("--thresholds", type=Path, default=THRESHOLDS)
    parser.add_argument("--thresholds-version", type=int)
    who = parser.add_mutually_exclusive_group()
    who.add_argument("--device", choices=sorted(DEVICES))
    who.add_argument("--model")
    parser.add_argument("--simulator", action="store_true", help="force the not-evidence simulator class")
    parser.add_argument("--out", type=Path)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    model = DEVICES.get(args.device) if args.device else args.model
    verdict = check(args.reports, thresholds_path=args.thresholds, pinned=args.thresholds_version,
                    model=model, simulator=args.simulator)
    if args.out:
        args.out.write_text(render_json(verdict), encoding="utf-8")
    sys.stdout.write(render_json(verdict) if args.json else render_text(verdict))
    return exit_code(verdict)


if __name__ == "__main__":
    sys.exit(main())
