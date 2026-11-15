#!/usr/bin/env python3
"""QA-012: the release evidence manifest.

`build` aggregates the evidence for one exact commit into `docs/release/evidence-manifest.json` (and a Markdown
summary): the roadmap and every feature's state with its recorded gate and post-merge evidence (from the
orchestrator's state), every committed test report, the privacy and licence documents, the QA-011 device run
records, and the gaps that keep the release open (missing device records, open `{device}`/`{owner}` tasks). Every
file is listed with its SHA-256, and the manifest carries its own hash over its canonical JSON.

`verify` recomputes every listed file's hash, checks the manifest hash and that the commit exists, and reports what
changed. A manifest is evidence of what was recorded, never of what was not run: device evidence counts only from a
QA-011 record whose own hash verifies and that says `evidence: true` (a physical device run).
"""
from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KIND = "projectM-iOS.qa012.evidenceManifest"
SCHEMA_VERSION = 1
DEFAULT_OUT = Path("docs/release/evidence-manifest.json")
DEVICES = ("D1", "D2", "D3")

# The evidence groups and the committed files each one hashes (globs relative to the repository root).
GROUPS: dict[str, tuple[str, ...]] = {
    "testReports": ("docs/test-reports/**/*.md", "docs/test-reports/**/*.json"),
    "performance": ("docs/performance/**/*.json", "docs/performance/**/*.md"),
    "privacy": ("docs/privacy-policy.md", "docs/release/app-privacy.md", "Apps/projectM-iOS/PrivacyInfo.xcprivacy",
                "docs/release/entitlements-review.md"),
    "licenses": ("docs/licenses/*", "Apps/projectM-iOS/Resources/Licenses/*", "docs/release/eula.md",
                 "docs/projectm-patches.md", "LICENSE*", "NOTICE*"),
    "autonomousRun": ("docs/FEATURE_ROADMAP_AUTONOMOUS.md", "docs/autonomous/STATUS.md",
                      "docs/autonomous/status.json", "docs/autonomous/AUDIT.md"),
}
# QA-011 run records live under the test reports too; they are read separately as device evidence.
DEVICE_RECORDS = "docs/test-reports/qa-011/runs/{device}/*/record.json"
INVENTORY = Path("docs/test-reports/qa-011/device-inventory.json")
EXCLUDED_PARTS = ("/runs/sim/",)       # simulator rehearsals: gitignored, never evidence


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def canonical(obj) -> str:
    return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def manifest_hash(manifest: dict) -> str:
    """SHA-256 of the canonical JSON without the `manifestSha256` field itself."""
    body = {k: v for k, v in manifest.items() if k != "manifestSha256"}
    return sha256_bytes(canonical(body).encode("utf-8"))


def git(root: Path, *args: str) -> str:
    return subprocess.run(["git", *args], cwd=root, capture_output=True, text=True, check=True).stdout.strip()


def tracked_files(root: Path) -> set[str]:
    out = subprocess.run(["git", "ls-files", "-z"], cwd=root, capture_output=True, check=True).stdout
    return {p for p in out.decode("utf-8").split("\0") if p}


def collect_group(root: Path, patterns: tuple[str, ...], tracked: set[str] | None) -> list[dict]:
    """Every committed file matching the patterns, sorted, with its size and hash."""
    seen: dict[str, dict] = {}
    for pattern in patterns:
        for path in sorted(root.glob(pattern)):
            if not path.is_file():
                continue
            rel = path.relative_to(root).as_posix()
            if any(part in "/" + rel for part in EXCLUDED_PARTS):
                continue
            if tracked is not None and rel not in tracked:
                continue
            seen[rel] = {"path": rel, "bytes": path.stat().st_size, "sha256": sha256_file(path)}
    return [seen[k] for k in sorted(seen)]


def record_self_hash(record: dict) -> str:
    """QA-011's own record hash (run_device_matrix.record_hash), so both scripts agree by construction."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import run_device_matrix  # noqa: E402  (imported late: it pulls in run_device_tests)
    return run_device_matrix.record_hash(record)


def device_evidence(root: Path, tracked: set[str] | None, record_hash=None) -> dict:
    """Per device: the newest committed QA-011 record that verifies and is a physical run, or why there is none."""
    record_hash = record_hash or record_self_hash
    out: dict[str, dict] = {}
    for device in DEVICES:
        candidates = sorted(root.glob(DEVICE_RECORDS.format(device=device)))
        chosen = None
        problems: list[str] = []
        for path in reversed(candidates):     # newest run id last in sort order
            rel = path.relative_to(root).as_posix()
            if tracked is not None and rel not in tracked:
                problems.append(f"{rel}: not committed")
                continue
            try:
                record = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, ValueError) as e:
                problems.append(f"{rel}: unreadable ({e})")
                continue
            if record.get("recordSha256") != record_hash(record):
                problems.append(f"{rel}: record hash does not verify")
                continue
            if record.get("evidence") is not True or record.get("dryRun"):
                problems.append(f"{rel}: not a physical device run")
                continue
            summary = record.get("summary") or {}
            chosen = {"status": "recorded", "record": rel, "sha256": sha256_file(path),
                      "recordSha256": record["recordSha256"], "runId": record.get("runId"),
                      "os": (record.get("target") or {}).get("osVersion"),
                      "build": (record.get("target") or {}).get("osBuild"),
                      "summary": summary}
            break
        out[device] = chosen or {"status": "missing", "problems": problems}
    return out


def feature_evidence(state: dict) -> list[dict]:
    """Each roadmap feature's state and recorded evidence (commands, exit codes, commits)."""
    rows = []
    for fid in sorted(state.get("features", {})):
        f = state["features"][fid]
        rows.append({
            "id": fid, "state": f.get("state"), "branchSha": f.get("branch_sha"),
            "integratedSha": f.get("integrated_sha"),
            "evidence": [{"command": e.get("command"), "exitCode": e.get("exit_code"), "sha": e.get("sha"),
                          "at": e.get("at")} for e in f.get("evidence", [])],
        })
    return rows


def open_device_tasks(root: Path) -> dict:
    path = root / INVENTORY
    if not path.exists():
        return {"inventory": None, "open": None}
    data = json.loads(path.read_text(encoding="utf-8"))
    tasks = data.get("tasks", [])
    by_cat: dict[str, int] = {}
    for t in tasks:
        by_cat[t.get("category", "?")] = by_cat.get(t.get("category", "?"), 0) + 1
    return {"inventory": INVENTORY.as_posix(), "inventorySha256": sha256_file(path), "open": len(tasks),
            "byCategory": dict(sorted(by_cat.items()))}


def gaps_for(features: list[dict], devices: dict, tasks: dict) -> list[str]:
    gaps = []
    for d, ev in devices.items():
        if ev["status"] != "recorded":
            gaps.append(f"{d}: no verified QA-011 physical device record")
        elif (ev.get("summary") or {}).get("fail"):
            gaps.append(f"{d}: QA-011 record has {ev['summary']['fail']} failing case(s)")
    if tasks.get("open"):
        gaps.append(f"{tasks['open']} open {{device}}/{{owner}} tasks (QA-011 inventory)")
    unfinished = [f["id"] for f in features if f["state"] not in
                  ("integrated", "skipped_existing", "accepted", "device_passed", "awaiting_final_device",
                   "implementation_complete")]
    if unfinished:
        gaps.append("features not finished: " + ", ".join(unfinished))
    waiting = [f["id"] for f in features if f["state"] == "awaiting_final_device"]
    if waiting:
        gaps.append("awaiting the final device stage: " + ", ".join(waiting))
    return gaps


def build(root: Path, state_path: Path | None, allow_dirty: bool = False, now: str | None = None,
          use_git: bool = True) -> dict:
    commit = git(root, "rev-parse", "HEAD") if use_git else "0" * 40
    dirty = bool(git(root, "status", "--porcelain", "--untracked-files=no")) if use_git else False
    if dirty and not allow_dirty:
        raise SystemExit("release_manifest: the tree has uncommitted changes; commit first (or --allow-dirty)")
    tracked = tracked_files(root) if use_git else None
    state = json.loads(state_path.read_text(encoding="utf-8")) if state_path and state_path.exists() else {}
    features = feature_evidence(state)
    devices = device_evidence(root, tracked)
    tasks = open_device_tasks(root)
    roadmap = root / "docs/FEATURE_ROADMAP_AUTONOMOUS.md"
    manifest = {
        "kind": KIND, "schemaVersion": SCHEMA_VERSION,
        "commit": commit, "dirtyTree": dirty,
        "generatedAt": now or _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "roadmapSha256": sha256_file(roadmap) if roadmap.exists() else None,
        "runId": state.get("run_id"),
        "featureCounts": count_states(features),
        "features": features,
        "groups": {name: collect_group(root, pats, tracked) for name, pats in GROUPS.items()},
        "deviceEvidence": devices,
        "openDeviceTasks": tasks,
    }
    manifest["gaps"] = gaps_for(features, devices, tasks)
    manifest["releaseReady"] = not manifest["gaps"]
    manifest["manifestSha256"] = manifest_hash(manifest)
    return manifest


def count_states(features: list[dict]) -> dict:
    counts: dict[str, int] = {}
    for f in features:
        counts[f["state"]] = counts.get(f["state"], 0) + 1
    return dict(sorted(counts.items()))


def verify(root: Path, manifest: dict, use_git: bool = True) -> list[str]:
    """Problems found; an empty list means every hash and the commit check out."""
    problems = []
    if manifest.get("kind") != KIND:
        problems.append(f"kind is {manifest.get('kind')!r}, not {KIND}")
    if manifest.get("manifestSha256") != manifest_hash(manifest):
        problems.append("manifestSha256 does not match the manifest's content")
    if use_git:
        try:
            git(root, "cat-file", "-e", f"{manifest.get('commit')}^{{commit}}")
        except subprocess.CalledProcessError:
            problems.append(f"commit {manifest.get('commit')} is not in this repository")
    for name, files in (manifest.get("groups") or {}).items():
        for f in files:
            path = root / f["path"]
            if not path.is_file():
                problems.append(f"{name}: {f['path']} is missing")
            elif sha256_file(path) != f["sha256"]:
                problems.append(f"{name}: {f['path']} changed since the manifest")
    for device, ev in (manifest.get("deviceEvidence") or {}).items():
        if ev.get("status") == "recorded":
            path = root / ev["record"]
            if not path.is_file() or sha256_file(path) != ev["sha256"]:
                problems.append(f"{device}: record {ev['record']} is missing or changed")
    return problems


def render_markdown(m: dict) -> str:
    lines = [
        "# Release evidence manifest (QA-012)", "",
        f"Generated by `python3 scripts/release_manifest.py build` at {m['generatedAt']} for commit "
        f"`{m['commit']}`. Verify with `python3 scripts/release_manifest.py verify`.", "",
        f"- Manifest SHA-256: `{m['manifestSha256']}`",
        f"- Roadmap SHA-256: `{m['roadmapSha256']}`",
        f"- Release ready: **{'yes' if m['releaseReady'] else 'no'}**", "",
        "## Features", "",
        "| State | Count |", "|---|---|",
        *[f"| {k} | {v} |" for k, v in m["featureCounts"].items()], "",
        "## Evidence files", "",
        "| Group | Files |", "|---|---|",
        *[f"| {k} | {len(v)} |" for k, v in m["groups"].items()], "",
        "## Device evidence (QA-011)", "",
        "| Device | Status | Record | Summary |", "|---|---|---|---|",
    ]
    for d, ev in m["deviceEvidence"].items():
        if ev["status"] == "recorded":
            lines.append(f"| {d} | recorded | `{ev['record']}` | {ev.get('summary')} |")
        else:
            lines.append(f"| {d} | missing | — | {'; '.join(ev.get('problems') or []) or 'no record'} |")
    lines += ["", "## Gaps", ""]
    lines += [f"- {g}" for g in m["gaps"]] or ["- none"]
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build", help="write the manifest for HEAD")
    b.add_argument("--state", default=str(ROOT / ".autonomous" / "state.json"),
                   help="the orchestrator's state (feature evidence)")
    b.add_argument("--out", default=str(ROOT / DEFAULT_OUT))
    b.add_argument("--allow-dirty", action="store_true")
    v = sub.add_parser("verify", help="recompute every hash")
    v.add_argument("manifest", nargs="?", default=str(ROOT / DEFAULT_OUT))
    args = p.parse_args(argv)
    if args.cmd == "build":
        m = build(ROOT, Path(args.state), allow_dirty=args.allow_dirty)
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(m, indent=1, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
        out.with_suffix(".md").write_text(render_markdown(m), encoding="utf-8")
        print(f"release_manifest: {out.relative_to(ROOT) if out.is_relative_to(ROOT) else out} "
              f"({sum(len(v) for v in m['groups'].values())} files, {len(m['gaps'])} gap(s), "
              f"release ready: {'yes' if m['releaseReady'] else 'no'})")
        return 0
    m = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
    problems = verify(ROOT, m)
    for problem in problems:
        print("release_manifest:", problem)
    print(f"release_manifest verify: {'OK' if not problems else f'{len(problems)} problem(s)'}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
