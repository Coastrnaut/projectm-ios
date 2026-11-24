"""Instruments from the command line for the QA-011 device matrix (PERF-004-T16, PERF-008-T16, PERF-011-T21).

Builds `xcrun xctrace` commands and reads what `xctrace export` writes; the matrix runner
(scripts/run_device_matrix.py, kind "xctrace") runs them. Everything here except `record`/`export` is pure and tested
in scripts/test_scripts.py with synthetic XML.

    xcrun xctrace record --template <name> --device <UDID> --time-limit <N>s --output x.trace --no-prompt \
        [--instrument os_signpost] [--env KEY=VALUE ...] --launch -- <bundle id>
    xcrun xctrace export --input x.trace --toc
    xcrun xctrace export --input x.trace --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"]'

Lessons (docs/autotester.md): never wrap `record` in a short timeout (saving a long trace takes minutes and a killed
save leaves an unreadable trace), and never read an unchanged bundle right after the recording as a hang: on D1 the
Logging template wrote nothing for 3-5 minutes after the app exited, then saved by itself (2026-11-24); `record()`
stops it only after that allowance (`SAVE_QUIET`) or a hard limit; launch the app through xctrace (`--attach` did not find
it on D3), and time anything done to the app from the moment its process appears, not from the start of the command
(Metal System Trace took about 18 s to launch it on D1); Allocations exports no allocation table, so memory comes
from the app's own report instead.
"""
from __future__ import annotations

import os
import re
import signal
import subprocess
import time
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


def trace_signature(trace: Path) -> tuple[int, float]:
    """(total bytes, newest modification time) of a trace bundle; (0, 0) while it does not exist."""
    if not trace.exists():
        return (0, 0.0)
    paths = [trace, *trace.rglob("*")] if trace.is_dir() else [trace]
    size, newest = 0, 0.0
    for path in paths:
        try:
            st = path.stat()
        except OSError:
            continue
        newest = max(newest, st.st_mtime)
        if path.is_file():
            size += st.st_size
    return (size, newest)


APP_EXITED = "Target app exited"

# Seconds xctrace may stay silent after the recording ended before it is stopped (`stop_reason`). D1 (iPhone 15,
# iOS 27.0.1), Logging template, perf004: after "Target app exited, ending recording..." xctrace wrote the raw
# `trace-data.atrc` within about a second and then changed nothing on disk (neither the bundle nor $TMPDIR) for 196 s
# (matrix 20261123T190422Z) and 307 s (20261123T200159Z) before it saved the whole trace by itself. The idle stops of
# 2026-11-23/24 (180 s, then 60 s) killed exactly that phase, and SIGINT does not shorten it ("Stopping recording..."
# and still running 180 s later), so each stop destroyed the trace. 420 s is the slowest save seen plus a third.
SAVE_QUIET = 420


def stop_reason(elapsed: float, idle: float, seconds: float, *, startup: float, save: float, ended: float | None = None,
                quiet: float = SAVE_QUIET, stall: float = 60) -> str | None:
    """Why a running `xctrace record` should be stopped now, or None to let it run.

    `elapsed`: seconds since the command started; `idle`: seconds since the trace bundle last changed; `ended`: seconds
    since xctrace printed "Target app exited" (None before). The recording may take `startup` (Metal System Trace took
    about 18 s to launch the app on D1) plus `seconds`; a recording whose app never exited counts as ended then.

    After the recording has ended, xctrace collects and saves the trace with nothing to watch on disk for minutes
    (`SAVE_QUIET`), so an idle bundle is no sign of a hang before `quiet` seconds have passed; after that, a bundle
    unchanged for `stall` seconds is a hung save (a trace still being written, like the 1.98 GB Metal System Trace on
    D1, 2026-11-23, keeps changing and is left alone). `startup + seconds + save` is the hard limit either way."""
    limit = startup + seconds + save
    if elapsed > limit:
        return f"still running {int(elapsed)} s after it started (limit {int(limit)} s)"
    if ended is None and elapsed > startup + seconds:
        ended = elapsed - (startup + seconds)
    if ended is not None and ended > quiet and idle > stall:
        return (f"no saved trace {int(ended)} s after the recording ended (bundle unchanged for {int(idle)} s; "
                f"allowance {int(quiet)} s)")
    return None


def trace_complete(trace: Path) -> bool:
    """Whether a trace bundle was saved whole: xctrace writes `form.template` when it finishes saving. A recording
    stopped during "ending recording..." leaves only `Trace1.run` with the raw `trace-data.atrc` (D1 2026-11-23,
    perf004): `export --toc` fails on it, and `xctrace import` of that .atrc gives a Logging trace whose os-signpost
    table is empty (the log stream arrives with the save), so nothing can be salvaged from it."""
    return (trace / "form.template").is_file()


def parse_cpu_time(text: str) -> float | None:
    """Seconds from `ps -o time=` output ("[[dd-]hh:]mm:ss.cc"); None for empty output (the process is gone)."""
    text = text.strip()
    if not text:
        return None
    days, _, rest = text.rpartition("-")
    total = 0.0
    try:
        for part in rest.split(":"):
            total = total * 60 + float(part)
        return total + (float(days) * 86400 if days else 0)
    except ValueError:
        return None


def cpu_seconds(pid: int) -> float | None:
    """CPU time of a process, None when it is gone or `ps` fails."""
    try:
        out = subprocess.run(["ps", "-o", "time=", "-p", str(pid)], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    return parse_cpu_time(out)


def record(cmd: list[str], trace: Path, log: Path, seconds: float, *, startup: float = 60, save: float = 480,
           quiet: float = SAVE_QUIET, stall: float = 60, grace: float = 60, poll: float = 5,
           heartbeat: float = 60) -> dict:
    """Runs `xctrace record` with its output in `log`, and stops it if it never ends (`stop_reason`): SIGINT first
    (xctrace's own Ctrl-C, which ends the recording and saves what it has), then SIGTERM after `grace` seconds and
    SIGKILL a quarter of that later. While xctrace saves, a line every `heartbeat` seconds records the bundle's size,
    how long it has been unchanged and xctrace's CPU time, so a slow save shows what it was doing.

    Returns {"exit", "text", "stopped": reason or None, "seconds", "appExited", "complete", "saveSeconds"}:
    `appExited` when xctrace said the app had exited (the recording window was whole), `complete` when the bundle was
    saved whole (`trace_complete`), `saveSeconds` from "Target app exited" to xctrace's end (None without it)."""
    log.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    signature, changed = trace_signature(trace), started
    stopped, exited_at, beat = None, None, started
    with open(log, "w") as out:
        proc = subprocess.Popen(cmd, stdout=out, stderr=subprocess.STDOUT, text=True, start_new_session=True)
        while True:
            try:
                proc.wait(timeout=poll)
                break
            except subprocess.TimeoutExpired:
                pass
            now = time.monotonic()
            current = trace_signature(trace)
            if current != signature:
                signature, changed = current, now
            if exited_at is None:
                out.flush()
                if APP_EXITED in log.read_text(errors="replace"):
                    exited_at = beat = now
            ended = None if exited_at is None else now - exited_at
            if ended is not None and now - beat >= heartbeat:
                beat = now
                cpu = cpu_seconds(proc.pid)
                out.write(f"[run_device_matrix] {int(ended)} s after the app exited: bundle {signature[0]} bytes, "
                          f"unchanged for {int(now - changed)} s, xctrace CPU {'?' if cpu is None else f'{cpu:.1f}'} s\n")
                out.flush()
            reason = stop_reason(now - started, now - changed, seconds, startup=startup, save=save, ended=ended,
                                 quiet=quiet, stall=stall)
            if not reason:
                continue
            stopped = reason
            out.write(f"\n[run_device_matrix] {reason}: sending SIGINT\n")
            out.flush()
            for sig, wait in ((signal.SIGINT, grace), (signal.SIGTERM, grace / 4), (signal.SIGKILL, grace / 4)):
                try:
                    os.killpg(proc.pid, sig)
                except ProcessLookupError:
                    break
                try:
                    proc.wait(timeout=wait)
                    break
                except subprocess.TimeoutExpired:
                    out.write(f"[run_device_matrix] still running {int(wait)} s after {sig.name}\n")
                    out.flush()
            break
    proc.wait()
    finished = time.monotonic()
    text = log.read_text(errors="replace")
    return {"exit": proc.returncode, "text": text, "stopped": stopped, "seconds": round(finished - started, 1),
            "appExited": APP_EXITED in text, "complete": trace_complete(trace),
            "saveSeconds": None if exited_at is None else round(finished - exited_at, 1)}


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


def perf004_verdict(events: list[tuple[float, str]], window: float = 3.0, start_window: float = 5.0,
                    ready: float | None = None) -> dict:
    """PERF-004-T16: texture allocations only at the first cycle (before the visual is up + start_window) and within
    `window` s of a size change ("rotate", "rotate back"). Fails without markers or without any allocation.

    "The visual is up" is the "QA-011 ready" marker (perf004 emits it when starting In-App Playback has returned), else
    `ready` (trace seconds, inferred by the caller for older traces), else "QA-011 start". D1 matrix 20261123T200159Z:
    starting playback on the Text visual held the main thread 5.0 s (hangtracer "HangInterval" 3.652-8.653 s), so the
    first cycle's 14 allocations came at 8.911 and 8.976 s, 5.3 s after "start", and counted as stray although nothing
    was allocated between them and the rotations."""
    marks = marker_times(events)
    allocations = [t for t, name in events if name == ALLOCATION_SIGNPOST]
    verdict = {"allocations": len(allocations), "markers": marks, "windowSeconds": window}
    if "start" not in marks:
        return {**verdict, "pass": False, "detail": "no QA-011 start marker in the trace (was perf004 the launched mode?)"}
    if not allocations:
        return {**verdict, "pass": False, "detail": "no PERF-004 texture allocation signposts: the visual used no pooled "
                "texture (PROJECTM_VISUAL must be a compositor visual: text, photo, video or camera)"}
    up = marks.get("ready", ready if ready is not None else marks["start"])
    up = max(up, marks["start"])
    if "rotate" in marks:   # the first size change ends the first cycle whatever `ready` says
        up = min(up, marks["rotate"] - start_window)
        up = max(up, marks["start"])
    verdict["readySeconds"] = round(up - marks["start"], 3)
    allowed = [(float("-inf"), up + start_window)]
    allowed += [(marks[k], marks[k] + window) for k in ("rotate", "rotate back") if k in marks]
    stray = [round(t, 3) for t in allocations if not any(lo <= t <= hi for lo, hi in allowed)]
    at_sizes = sum(1 for t in allocations if any(lo <= t <= hi for lo, hi in allowed[1:]))
    verdict.update({"stray": stray, "atStart": len(allocations) - at_sizes - len(stray), "atSizeChanges": at_sizes,
                    "pass": not stray})
    verdict["detail"] = (f"{len(allocations)} allocations: {verdict['atStart']} at start, {at_sizes} at size changes"
                         + (f", {len(stray)} elsewhere (at {stray[:5]} s)" if stray else "")
                         + (f"; the visual was up {verdict['readySeconds']:.1f} s after the start marker"
                            if verdict["readySeconds"] >= 1 else ""))
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
        detail = "the app was not backgrounded and brought back during the run"
        # D1, 2026-11-23: Settings opened before xctrace had launched the app, so the app started in the background
        # (state 2 for its first 15 samples) and the "return" only brought it to the front once.
        early = [s.get("state") for s in samples[:3]]
        if early and all(state == 2 for state in early):
            detail += "; it started in the background (was Settings opened before the app had launched?)"
        return {**out, "pass": False, "detail": detail}
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
