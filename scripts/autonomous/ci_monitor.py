#!/usr/bin/env python3
"""Watch one GitHub Actions run in the background and exit when it is complete (owner rule 6).

Work goes on while CI runs: start this with the shell's background mode, keep working, and act
on its result when it exits. It reads the run every `--interval` seconds with ONE `gh` call
(about 12 calls an hour; `gh run watch` polls every few seconds and exhausted the 5,000/hour
API limit on 2026-11-13). It also prints each job as soon as that job finishes, so an early
failure (the Linux job finishes in about 5 minutes) can be acted on before the run ends.

  python3 scripts/autonomous/ci_monitor.py --sha 81f5c65 [--interval 300] [--max-hours 3]

Exit status: 0 all jobs succeeded, 1 some job failed or was cancelled, 2 timed out or gh error,
3 superseded: the run was cancelled before any job started because a newer push replaced it in
the queue (expected with cancel-in-progress false; the newer run covers this commit).
The final JSON summary goes to stdout and to `.autonomous/logs/ci-<run id>.json`.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
OK = {"success", "skipped", "neutral"}


def gh_json(args: list[str], runner=subprocess.run) -> object | None:
    proc = runner(["gh", *args], cwd=str(ROOT), capture_output=True, text=True, timeout=120)
    if proc.returncode != 0:
        print(f"gh error: {proc.stderr.strip()[:300]}", flush=True)
        return None
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None


def find_run(sha: str, runner=subprocess.run) -> dict | None:
    runs = gh_json(["run", "list", "--limit", "20", "--json",
                    "databaseId,headSha,status,conclusion,event,createdAt"], runner)
    for run in runs or []:
        if run["headSha"].startswith(sha):
            return run
    return None


def summarize(run: dict) -> dict:
    jobs = [{"name": j["name"], "status": j["status"], "conclusion": j.get("conclusion") or "",
             "id": j.get("databaseId")} for j in run.get("jobs", [])]
    failed = [j for j in jobs if j["status"] == "completed" and j["conclusion"] not in OK]
    return {"id": run.get("databaseId"), "sha": run.get("headSha", "")[:7],
            "status": run.get("status"), "conclusion": run.get("conclusion") or "",
            "jobs": jobs, "failed": [j["name"] for j in failed]}


def main(argv: list[str] | None = None, runner=subprocess.run, sleep=time.sleep) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--sha", required=True)
    ap.add_argument("--interval", type=float, default=300)
    ap.add_argument("--max-hours", type=float, default=3)
    args = ap.parse_args(argv)
    deadline = time.monotonic() + args.max_hours * 3600
    run_id = None
    reported: set[str] = set()
    while time.monotonic() < deadline:
        if run_id is None:
            found = find_run(args.sha, runner)
            run_id = found and found["databaseId"]
            if run_id is None:
                sleep(min(args.interval, 60))
                continue
            print(f"run {run_id} for {args.sha}", flush=True)
        run = gh_json(["run", "view", str(run_id), "--json",
                       "databaseId,headSha,status,conclusion,jobs"], runner)
        if run is None:
            sleep(args.interval)
            continue
        summary = summarize(run)
        for job in summary["jobs"]:
            if job["status"] == "completed" and job["name"] not in reported:
                reported.add(job["name"])
                print(f"job {job['name']}: {job['conclusion']}", flush=True)
        if summary["status"] == "completed":
            out = ROOT / ".autonomous" / "logs" / f"ci-{run_id}.json"
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(json.dumps(summary, indent=1), encoding="utf-8")
            print(json.dumps(summary), flush=True)
            if summary["conclusion"] == "cancelled" and not summary["jobs"]:
                print("superseded: cancelled before any job started (a newer run covers it)", flush=True)
                return 3
            return 0 if not summary["failed"] and summary["conclusion"] == "success" else 1
        sleep(args.interval)
    print(f"timed out after {args.max_hours} h", flush=True)
    return 2


if __name__ == "__main__":
    sys.exit(main())
