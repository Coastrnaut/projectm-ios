"""Instruments from the command line for the QA-011 device matrix (PERF-004-T16, PERF-008-T16, PERF-011-T21).

Builds `xcrun xctrace` commands and reads what `xctrace export` writes; the matrix runner
(scripts/run_device_matrix.py, kind "xctrace") runs them. Everything here except `record`/`export` is pure and tested
in scripts/test_scripts.py with synthetic XML.

    xcrun xctrace record --template <name> --device <UDID> --time-limit <N>s --output x.trace --no-prompt \
        [--instrument os_signpost] [--env KEY=VALUE ...] --launch -- <bundle id>
    xcrun xctrace export --input x.trace --toc
    xcrun xctrace export --input x.trace --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"]'

Lessons (docs/autotester.md): never wrap `record` in a short timeout (saving a long trace takes minutes and a killed
save leaves an unreadable trace); launch the app through xctrace (`--attach` did not find it on D3); Allocations
exports no allocation table, so memory comes from the app's own report instead.
"""
from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from pathlib import Path

SIGNPOST_SCHEMA = "os-signpost"
GPU_SCHEMA = "metal-gpu-intervals"
ALLOCATION_SIGNPOST = "PERF-004 texture allocation"
POWER_SCHEMA_RE = re.compile(r"(?i)power|energy|battery")


def record_command(device: str, template: str, seconds: int, output: Path, bundle: str, *,
                   env: dict[str, str] | None = None, instruments: list[str] | tuple[str, ...] = (),
                   arguments: list[str] | tuple[str, ...] = ()) -> list[str]:
    cmd = ["xcrun", "xctrace", "record", "--template", template, "--device", device, "--time-limit", f"{seconds}s",
           "--output", str(output), "--no-prompt"]
    for name in instruments:
        cmd += ["--instrument", name]
    for key, value in (env or {}).items():
        cmd += ["--env", f"{key}={value}"]
    return cmd + ["--launch", "--", bundle, *arguments]


def toc_command(trace: Path) -> list[str]:
    return ["xcrun", "xctrace", "export", "--input", str(trace), "--toc"]


def table_xpath(schema: str, run: int = 1) -> str:
    return f'/trace-toc/run[@number="{run}"]/data/table[@schema="{schema}"]'


def export_command(trace: Path, schema: str, output: Path, run: int = 1) -> list[str]:
    return ["xcrun", "xctrace", "export", "--input", str(trace), "--xpath", table_xpath(schema, run), "--output", str(output)]


def parse_toc(text: str) -> list[dict]:
    """The tables of every run: [{"run": 1, "schema": "os-signpost"}, ...] (duplicates kept once)."""
    root = ET.fromstring(text)
    out, seen = [], set()
    for run in root.iter("run"):
        number = int(run.get("number", "1"))
        for table in run.iter("table"):
            schema = table.get("schema")
            if schema and (number, schema) not in seen:
                seen.add((number, schema))
                out.append({"run": number, "schema": schema})
    return out


def _value(el: ET.Element, by_id: dict[str, tuple[str, str]]) -> tuple[str, str]:
    """(raw text, display text) of one cell, following `ref` to the element with that `id`."""
    ref = el.get("ref")
    if ref is not None:
        return by_id.get(ref, ("", ""))
    raw = (el.text or "").strip()
    if not raw:   # a compound value (a thread or process): its display text, else its children's text
        raw = " ".join((c.text or "").strip() for c in el.iter() if c is not el and (c.text or "").strip())
    return raw, el.get("fmt") or raw


def parse_table(text: str) -> list[dict[str, dict[str, str]]]:
    """Rows of one exported table as {column mnemonic: {"raw": ..., "fmt": ...}}, in schema column order.

    xctrace writes each value once with an `id` and later repeats it as `<tag ref="id"/>`; `<sentinel/>` is empty."""
    root = ET.fromstring(text)
    by_id: dict[str, tuple[str, str]] = {}
    for el in root.iter():
        if el.get("id") is not None and el.get("ref") is None:
            by_id[el.get("id")] = _value(el, by_id)
    schema = next(root.iter("schema"), None)
    columns = [((c.findtext("mnemonic") or c.findtext("name") or f"col{i}").strip())
               for i, c in enumerate(schema.findall("col"))] if schema is not None else []
    rows = []
    for row in root.iter("row"):
        cells = {}
        for i, el in enumerate(list(row)):
            name = columns[i] if i < len(columns) else el.tag
            raw, fmt = ("", "") if el.tag == "sentinel" else _value(el, by_id)
            cells[name] = {"raw": raw, "fmt": fmt, "tag": el.tag}
        rows.append(cells)
    return rows


def _time_seconds(cells: dict[str, dict[str, str]]) -> float | None:
    """The row's time in seconds (xctrace times are nanoseconds since the trace started)."""
    for key in ("time", "start", "timestamp"):
        if key in cells and re.fullmatch(r"\d+", cells[key]["raw"] or ""):
            return int(cells[key]["raw"]) / 1e9
    for key, cell in cells.items():
        if ("time" in key or cell.get("tag") in ("event-time", "start-time")) and re.fullmatch(r"\d+", cell["raw"] or ""):
            return int(cell["raw"]) / 1e9
    return None


def signpost_events(rows: list[dict[str, dict[str, str]]]) -> list[tuple[float, str]]:
    """(seconds, signpost name) of each os-signpost row, sorted by time."""
    out = []
    for cells in rows:
        t = _time_seconds(cells)
        name = (cells.get("name") or cells.get("signpost-name") or {}).get("fmt", "")
        if t is not None and name:
            out.append((t, name))
    return sorted(out)


def marker_times(events: list[tuple[float, str]], prefix: str = "QA-011 ") -> dict[str, float]:
    """The first time of each automation marker ("QA-011 rotate" -> "rotate")."""
    out: dict[str, float] = {}
    for t, name in events:
        if name.startswith(prefix):
            out.setdefault(name[len(prefix):], t)
    return out


def perf004_verdict(events: list[tuple[float, str]], window: float = 3.0, start_window: float = 5.0) -> dict:
    """PERF-004-T16: texture allocations only at the first cycle (before "start" + start_window) and within `window` s of a
    size change ("rotate", "rotate back"). Fails without markers or without any allocation (nothing measured)."""
    marks = marker_times(events)
    allocations = [t for t, name in events if name == ALLOCATION_SIGNPOST]
    verdict = {"allocations": len(allocations), "markers": marks, "windowSeconds": window}
    if "start" not in marks:
        return {**verdict, "pass": False, "detail": "no QA-011 start marker in the trace (was perf004 the launched mode?)"}
    if not allocations:
        return {**verdict, "pass": False, "detail": "no PERF-004 texture allocation signposts: the visual used no pooled "
                "texture (PROJECTM_VISUAL must be a compositor visual: text, photo, video or camera)"}
    allowed = [(float("-inf"), marks["start"] + start_window)]
    allowed += [(marks[k], marks[k] + window) for k in ("rotate", "rotate back") if k in marks]
    stray = [round(t, 3) for t in allocations if not any(lo <= t <= hi for lo, hi in allowed)]
    at_sizes = sum(1 for t in allocations if any(lo <= t <= hi for lo, hi in allowed[1:]))
    verdict.update({"stray": stray, "atStart": len(allocations) - at_sizes - len(stray), "atSizeChanges": at_sizes,
                    "pass": not stray})
    verdict["detail"] = (f"{len(allocations)} allocations: {verdict['atStart']} at start, {at_sizes} at size changes"
                         + (f", {len(stray)} elsewhere (at {stray[:5]} s)" if stray else ""))
    return verdict


def rows_in_window(rows: list[dict[str, dict[str, str]]], start: float, end: float, contains: str | None = None) -> int:
    """Rows whose time is in [start, end] and (if given) that mention `contains` in any cell (a process name)."""
    n = 0
    for cells in rows:
        t = _time_seconds(cells)
        if t is None or not start <= t <= end:
            continue
        if contains and not any(contains in (c["raw"] + " " + c["fmt"]) for c in cells.values()):
            continue
        n += 1
    return n


# The app's process as Instruments names it: the executable ("projectM-iOS") or, in Metal System Trace's GPU intervals,
# the display name ("projectM (2164)" on D1, 2026-11-23). Matched on the name before " (pid)", never as a substring.
APP_PROCESS_NAMES = ("projectM-iOS", "projectM")


def process_name(cells: dict[str, dict[str, str]]) -> str:
    """A row's process name without its " (pid)" suffix ("" without a process cell)."""
    cell = cells.get("process")
    if not cell:
        return ""
    return re.sub(r"\s*\(\d+\)\s*$", "", cell.get("fmt") or cell.get("raw") or "").strip()


def app_rows_in_window(rows: list[dict[str, dict[str, str]]], start: float, end: float,
                       names: tuple[str, ...] = APP_PROCESS_NAMES) -> tuple[int, int]:
    """(rows of the app's process in [start, end], rows of the app's process in the whole table)."""
    inside = total = 0
    for cells in rows:
        if process_name(cells) not in names:
            continue
        total += 1
        t = _time_seconds(cells)
        if t is not None and start <= t <= end:
            inside += 1
    return inside, total


def perf011_verdict(report: dict, gpu_rows: list | None = None, events: list[tuple[float, str]] | None = None,
                    names: tuple[str, ...] = APP_PROCESS_NAMES) -> dict:
    """PERF-011-T21 from the app's perf011 report (and the Metal System Trace GPU intervals when exported):
    no frames from 10 s after backgrounding until the return, a lower footprint then than before, and the first frame
    within 2 s of the return.

    "The return" is UIKit's willEnterForeground (report `returnedAt`, trace marker "QA-011 return"): PERF-011 gates
    drawing from didEnterBackground until willEnterForeground, so the app draws again a few ms before didBecomeActive
    (`activeAgainAt`, marker "QA-011 foreground"); 16 ms on D1, 2026-11-23. Only samples taken in the background count
    (a sample taken after the return also holds the return's first frames), plus the frames between the last of them
    and the return (`framesAtReturn` minus that sample's running `total`). Reports and traces from before 2026-11-23
    have no return time: the window then ends at didBecomeActive."""
    samples = report.get("samples") or []
    bg, fg = report.get("backgroundedAt", -1), report.get("activeAgainAt", -1)
    out: dict = {"backgroundedAt": bg, "activeAgainAt": fg, "firstFrameAfterReturnSeconds": report.get("firstFrameAfterReturnSeconds")}
    if bg is None or bg < 0 or fg is None or fg < 0:
        return {**out, "pass": False, "detail": "the app was not backgrounded and brought back during the run"}
    ret = report.get("returnedAt", -1)
    ret = ret if ret is not None and 0 <= ret <= fg else fg
    out["returnedAt"] = ret
    before = [s["footprintMB"] for s in samples if s["t"] < bg and s.get("footprintMB", -1) > 0]
    away = [s for s in samples if bg + 10 <= s["t"] <= ret and s.get("state", 2) == 2]
    away_mb = [s["footprintMB"] for s in away if s.get("footprintMB", -1) > 0]
    frames_away = sum(s.get("frames", 0) for s in away)
    at_return = report.get("framesAtReturn", -1)
    if away and at_return is not None and at_return >= 0 and "total" in away[-1]:
        tail = max(int(at_return - away[-1]["total"]), 0)
        out["framesBeforeReturn"] = tail
        frames_away += tail

    def median(values: list[float]) -> float:
        return sorted(values)[len(values) // 2] if values else -1

    out.update({"awaySamples": len(away), "framesAway": frames_away, "footprintBeforeMB": round(median(before), 1),
                "footprintAwayMB": round(median(away_mb), 1)})
    first = report.get("firstFrameAfterReturnSeconds", -1)
    checks = {"no frames while away": len(away) > 0 and frames_away == 0,
              "less memory while away": bool(before) and bool(away_mb) and median(away_mb) < median(before),
              "frames within 2 s of the return": first is not None and 0 <= first <= 2}
    if gpu_rows is not None and events is not None:
        marks = marker_times(events)
        if "background" in marks and "foreground" in marks:
            end = marks.get("return", marks["foreground"])
            n, total = app_rows_in_window(gpu_rows, marks["background"] + 10, end, names)
            out.update({"gpuIntervalsAway": n, "gpuIntervalsApp": total})
            # Without any of the app's intervals the process match failed and nothing was checked (2026-11-23).
            checks["no GPU intervals while away"] = total > 0 and n == 0
            if total == 0:
                out["gpuProcessesSeen"] = sorted({process_name(c) for c in gpu_rows} - {""})[:5]
    out["checks"] = checks
    out["pass"] = all(checks.values())
    failed = [k for k, ok in checks.items() if not ok]
    out["detail"] = ("all pass: " if not failed else "failed: " + ", ".join(failed) + "; ") + (
        f"{frames_away} frames away, footprint {out['footprintBeforeMB']} -> {out['footprintAwayMB']} MB, "
        f"first frame {first} s after the return") + (
        f"; no GPU intervals of {'/'.join(names)} in the trace (processes: {', '.join(out['gpuProcessesSeen'])})"
        if "gpuProcessesSeen" in out else "")
    return out


def numeric(cell: dict[str, str] | None) -> float | None:
    if not cell:
        return None
    try:
        return float(cell["raw"])
    except (TypeError, ValueError):
        return None


def per_minute(rows: list[dict[str, dict[str, str]]], column_re: str = r"(?i)power|energy|impact") -> dict:
    """Best effort for the Power Profiler tables (their schemas are not documented): the mean of the first numeric
    column whose mnemonic matches `column_re`, per minute of trace time."""
    column = None
    for cells in rows:
        for key, cell in cells.items():
            if re.search(column_re, key) and numeric(cell) is not None:
                column = key
                break
        if column:
            break
    if not column:
        return {"column": None, "minutes": []}
    buckets: dict[int, list[float]] = {}
    for cells in rows:
        t, v = _time_seconds(cells), numeric(cells.get(column))
        if t is not None and v is not None:
            buckets.setdefault(int(t // 60) + 1, []).append(v)
    return {"column": column, "minutes": [{"minute": m, "mean": round(sum(v) / len(v), 3), "rows": len(v)}
                                          for m, v in sorted(buckets.items())]}
