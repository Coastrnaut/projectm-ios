#!/usr/bin/env python3
"""Progress dashboard (AUTO-012): Markdown and JSON summaries of the run state.

Counts come straight from the state file. The report holds feature IDs, states, commit SHAs,
commands and log paths only; values that look like secrets are masked.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

try:
    from .state import STATES, atomic_write_json
except ImportError:
    from state import STATES, atomic_write_json

ROOT = Path(__file__).resolve().parent.parent.parent
REPORT_DIR = ROOT / "docs" / "autonomous"
SECRET = re.compile(r"(sk-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9]{20,}|"
                    r"(?i:(?:api[_-]?key|token|password|secret)\s*[=:]\s*)\S+)")


def redact(text: str) -> str:
    return SECRET.sub("[redacted]", text)


def summarize(state: dict, priorities: dict[str, str] | None = None) -> dict:
    features = state["features"]
    by_state = {s: 0 for s in STATES}
    for rec in features.values():
        by_state[rec["state"]] += 1
    by_priority: dict[str, dict[str, int]] = {}
    for fid, rec in features.items():
        row = by_priority.setdefault((priorities or {}).get(fid, rec["priority"]), {})
        row[rec["state"]] = row.get(rec["state"], 0) + 1
    return {
        "run_id": state["run_id"], "updated": state["updated"],
        "roadmap_sha256": state["roadmap_sha256"],
        "repo_head_at_start": state["repo_head_at_start"],
        "integration_branch": state["integration_branch"], "phase": state["phase"],
        "total": len(features),
        "by_state": {s: n for s, n in by_state.items() if n},
        "by_priority": {p: by_priority[p] for p in sorted(by_priority)},
        "budget": state["budget"],
        "blocked": [{"id": fid, "category": rec["error_category"],
                     "reason": redact(rec["blocker"] or "")}
                    for fid, rec in sorted(features.items())
                    if rec["state"] in ("blocked", "infeasible")],
        "integrated": [{"id": fid, "sha": rec["integrated_sha"], "branch": rec["branch"]}
                       for fid, rec in sorted(features.items())
                       if rec["state"] == "integrated"],
        "skipped_existing": [{"id": fid, "audit": rec["audit"]}
                             for fid, rec in sorted(features.items())
                             if rec["state"] == "skipped_existing"],
    }


def render_markdown(state: dict, titles: dict[str, str] | None = None,
                    device_verdict: dict | None = None) -> str:
    titles = titles or {}
    s = summarize(state)
    lines = [
        "# Autonomous roadmap run: status", "",
        f"- Run `{s['run_id']}`, updated {s['updated']}; phase: **{s['phase']}**",
        f"- Roadmap SHA-256 `{s['roadmap_sha256']}` (frozen)",
        f"- Started from `{s['repo_head_at_start']}`; integration branch "
        f"`{s['integration_branch']}` (local only, never pushed)",
        f"- Features: {s['total']}", "",
        "## Counts by state", "", "| State | Features |", "|---|---|",
    ]
    lines += [f"| {name} | {count} |" for name, count in s["by_state"].items()]
    lines += ["", "## Counts by priority", "", "| Priority | " +
              " | ".join(s["by_state"]) + " |", "|---|" + "---|" * len(s["by_state"])]
    for priority, row in s["by_priority"].items():
        lines.append(f"| {priority} | " +
                     " | ".join(str(row.get(name, 0)) for name in s["by_state"]) + " |")
    if device_verdict is not None:
        lines += ["", "## Final device gate", ""]
        if device_verdict["implementation_complete"]:
            lines.append("Implementation is complete. " + (
                "Device prerequisites:" if device_verdict["device_prerequisites"]
                else "All of D1-D3 are available."))
            lines += [f"- {item}" for item in device_verdict["device_prerequisites"]]
        else:
            lines.append("The physical-device suite may **not** start:")
            lines += [f"- {reason}" for reason in device_verdict["reasons"]]
    lines += ["", "## Integrated", ""]
    if s["integrated"]:
        lines += ["| ID | Feature | Merge commit | Branch |", "|---|---|---|---|"]
        lines += [f"| {r['id']} | {titles.get(r['id'], '')} | `{(r['sha'] or '')[:12]}` | "
                  f"`{r['branch']}` |" for r in s["integrated"]]
    else:
        lines.append("None yet.")
    lines += ["", "## Proved already implemented", ""]
    if s["skipped_existing"]:
        for r in s["skipped_existing"]:
            audit = r["audit"] or {}
            lines.append(f"- **{r['id']}** {titles.get(r['id'], '')}: code "
                         f"{', '.join(audit.get('code_paths', []))}; tests "
                         f"{', '.join(audit.get('test_evidence', []))}")
    else:
        lines.append("None.")
    lines += ["", "## Blocked or infeasible", ""]
    if s["blocked"]:
        lines += ["| ID | Feature | Category | Reason |", "|---|---|---|---|"]
        lines += [f"| {r['id']} | {titles.get(r['id'], '')} | {r['category'] or ''} | "
                  f"{r['reason'].replace('|', '/')} |" for r in s["blocked"]]
    else:
        lines.append("None.")
    lines += ["", "## Evidence by feature", ""]
    for fid, rec in sorted(state["features"].items()):
        if not rec["evidence"]:
            continue
        lines.append(f"### {fid} {titles.get(fid, '')} ({rec['state']})")
        for ev in rec["evidence"]:
            mark = "pass" if ev["exit_code"] == 0 else f"exit {ev['exit_code']}"
            sha = f" at `{ev['sha'][:12]}`" if ev.get("sha") else ""
            log = f" (log `{ev['log']}`)" if ev.get("log") else ""
            lines.append(f"- `{redact(ev['command'])}`: {mark}{sha}{log}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def write_reports(state: dict, titles: dict[str, str] | None = None,
                  device_verdict: dict | None = None, out_dir: Path = REPORT_DIR
                  ) -> tuple[Path, Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    md, js = out_dir / "STATUS.md", out_dir / "status.json"
    md.write_text(render_markdown(state, titles, device_verdict), encoding="utf-8")
    summary = summarize(state)
    summary["device_gate"] = device_verdict
    summary["features"] = {fid: {k: rec[k] for k in ("state", "priority", "branch",
                                                     "branch_sha", "integrated_sha", "spec_dir",
                                                     "attempts", "error_category")}
                           for fid, rec in sorted(state["features"].items())}
    atomic_write_json(js, json.loads(redact(json.dumps(summary))))
    return md, js
