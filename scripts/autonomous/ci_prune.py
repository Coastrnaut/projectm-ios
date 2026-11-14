#!/usr/bin/env python3
"""Cancel superseded *queued* CI runs on main (2026-11-14).

Each push to main has its own concurrency group (so no push cancels a running run), but GitHub
runs only a few macOS jobs at a time, so a fast push cadence queued a dozen 50-90 minute runs.
A queued run whose commit is an ancestor of a newer queued or running run adds no coverage.

Rule: keep every run that is in progress, and the newest queued run; cancel every other queued
(or waiting/pending) run on main. Never touches completed or in-progress runs.

Usage: python3 scripts/autonomous/ci_prune.py [--dry-run]
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys

QUEUED = {"queued", "waiting", "pending", "requested"}


def plan(runs: list[dict]) -> list[dict]:
    """The runs to cancel. `runs` are newest first (as `gh run list` returns them)."""
    queued = [r for r in runs if r.get("status") in QUEUED]
    return queued[1:]   # keep the newest queued run


def started(run_id: int) -> bool:
    """True if any job of the run has started (in progress or completed)."""
    proc = subprocess.run(["gh", "run", "view", str(run_id), "--json", "jobs"],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        return True   # unknown: never cancel
    jobs = json.loads(proc.stdout).get("jobs", [])
    linux = ("docs-and-compliance", "host-tests-linux")   # minutes on Linux: cheap to repeat
    return any(j.get("status") in ("in_progress", "completed") for j in jobs
               if j.get("conclusion") not in ("skipped", "cancelled") and j.get("name") not in linux)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int, default=40)
    args = ap.parse_args(argv)
    out = subprocess.run(["gh", "run", "list", "--branch", "main", "--limit", str(args.limit),
                          "--json", "databaseId,headSha,status,createdAt"],
                         capture_output=True, text=True, check=True).stdout
    runs = json.loads(out)
    for run in plan(runs):
        # A run GitHub calls "queued" may already have started jobs (some jobs still wait for a
        # runner); cancelling it threw away work (2026-11-14, run 43620550181). Cancel only runs
        # none of whose jobs has started.
        if started(run["databaseId"]):
            print(f"keep run {run['databaseId']} ({run['headSha'][:7]}): jobs already started")
            continue
        line = f"cancel queued run {run['databaseId']} ({run['headSha'][:7]})"
        if args.dry_run:
            print("would " + line)
            continue
        proc = subprocess.run(["gh", "run", "cancel", str(run["databaseId"])], capture_output=True, text=True)
        print(line + ("" if proc.returncode == 0 else f": failed: {proc.stderr.strip()[:200]}"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
