#!/usr/bin/env python3
"""Local autonomous roadmap orchestrator: command line for scripts/autonomous/.

  preflight            toolchain, git, Spec Kit and Claude CLI checks
  init                 freeze the roadmap SHA and create .autonomous/state.json
  next                 what the scheduler would start now
  set ID STATE ...     record a transition (audit result, blocker, branch, spec dir)
  evidence ID ...      record a command, its exit code and log
  worktree ID          create or reuse the feature's branch and worktree
  gate [ID]            run the gates for a feature worktree or the integration checkout
  integrate ID         merge a gated feature branch into the integration branch
  run                  unattended loop through a logged-in Claude CLI (bounded by --budget-*)
  device-gate          may the final physical-device suite start?
  report               write docs/autonomous/STATUS.md and status.json

Two ways to execute features share the same state, gates and reports: `run` drives a
logged-in Claude CLI, and a Claude session can do the work itself, recording each step with
`set`, `evidence`, `gate` and `integrate`. Nothing here pushes or changes signing.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from functools import partial
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import agent_driver  # noqa: E402
import device_gate  # noqa: E402
import gates as gates_mod  # noqa: E402
import report  # noqa: E402
import spec_driver  # noqa: E402
from roadmap_parser import DEFAULT_ROADMAP, Roadmap, RoadmapError, parse_roadmap  # noqa: E402
from scheduler import DONE_STATES, Scheduler  # noqa: E402
from state import DEFAULT_STATE, StateError, StateStore  # noqa: E402
from worktrees import GitError, Worktrees, branch_name  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent.parent
LOG_DIR = ROOT / ".autonomous" / "logs"
INTEGRATION_BRANCH = "autonomous/integration"


def sh(cmd: list[str], timeout: float = 120) -> tuple[int, str]:
    try:
        proc = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True,
                              timeout=timeout)
        return proc.returncode, (proc.stdout + proc.stderr).strip()
    except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
        return 127, str(exc)


def preflight() -> dict:
    checks: dict[str, dict] = {}

    def add(name: str, ok: bool, detail: str, required: bool = True) -> None:
        checks[name] = {"ok": ok, "required": required, "detail": detail[:400]}

    code, out = sh(["git", "status", "--porcelain"])
    add("git_clean", code == 0 and not out, out or "clean")
    code, out = sh(["git", "rev-parse", "--abbrev-ref", "HEAD"])
    add("git_branch", code == 0, out)
    code, out = sh(["python3", "scripts/verify_environment.py"])
    add("toolchain_pins", code == 0, out.replace("\n", "; "))
    code, out = sh(["python3", "scripts/check_compliance.py"])
    add("compliance", code == 0, out.splitlines()[-1] if out else "")
    code, out = sh(["xcrun", "simctl", "list", "runtimes"])
    add("simulators", code == 0 and "iOS" in out,
        "; ".join(line.strip() for line in out.splitlines() if "iOS" in line))
    skills = sorted(p.parent.name for p in (ROOT / ".claude" / "skills").glob("speckit-*/SKILL.md"))
    missing = [s for s in spec_driver.SKILL_SEQUENCE if s not in skills]
    add("speckit_skills", not missing, "missing: " + ", ".join(missing) if missing
        else f"{len(skills)} installed")
    code, out = sh(["specify", "--version"])
    add("specify_cli", code == 0, out.splitlines()[-1] if out else "", required=False)
    binary = agent_driver.find_claude()
    add("claude_cli", bool(binary), binary or "not found", required=False)
    if binary:
        result = agent_driver.run_claude("Reply with exactly: OK", ROOT, timeout=120,
                                         binary=binary, max_turns=1, allowed_tools=("Read",))
        add("claude_cli_logged_in", result.ok, result.reason or "ok", required=False)
    add("engine_binaries", (ROOT / "Build" / "ProjectM.xcframework").exists(),
        "Build/ProjectM.xcframework", required=False)
    add("angle_binaries", (ROOT / "Build" / "ANGLEFrameworks").exists(),
        "Build/ANGLEFrameworks", required=False)
    devices = device_gate.list_devices()
    add("devices", len(devices) == 3, ", ".join(
        f"{a} {d.get('os')}" for a, d in sorted(devices.items())) or "none", required=False)
    free = shutil.disk_usage(str(ROOT)).free // 1024 ** 3
    add("disk", free >= 20, f"{free} GB free")
    try:
        roadmap = parse_roadmap()
        add("roadmap_dag", True, f"{len(roadmap.features)} features, sha256 {roadmap.sha256}")
    except RoadmapError as exc:
        add("roadmap_dag", False, "; ".join(exc.problems))
    return {"ok": all(c["ok"] for c in checks.values() if c["required"]), "checks": checks}


def load(args) -> tuple[Roadmap, StateStore]:
    roadmap = parse_roadmap(Path(args.roadmap))
    store = StateStore(Path(args.state_file)).load(expect_roadmap_sha=roadmap.sha256)
    return roadmap, store


def write_report(roadmap: Roadmap, store: StateStore) -> None:
    verdict = device_gate.decide(store.states())
    report.write_reports(store.data, {f.id: f.title for f in roadmap.features.values()}, verdict)


def cmd_preflight(args) -> int:
    result = preflight()
    print(json.dumps(result, indent=1))
    return 0 if result["ok"] else 1


def cmd_init(args) -> int:
    roadmap = parse_roadmap(Path(args.roadmap))
    store = StateStore(Path(args.state_file))
    wt = Worktrees(ROOT, args.integration_branch)
    store.init(roadmap.sha256, wt.head(), [
        {"id": f.id, "priority": f.priority, "depends_on": list(f.depends_on)}
        for f in roadmap.features.values()], args.base_branch, args.integration_branch)
    write_report(roadmap, store)
    print(f"run {store.data['run_id']}: {len(roadmap.features)} features, roadmap frozen at "
          f"{roadmap.sha256[:12]}")
    return 0


def cmd_next(args) -> int:
    roadmap, store = load(args)
    scheduler = Scheduler(roadmap, args.concurrency)
    states = store.states()
    running = {fid for fid in store.in_flight()}
    selection = scheduler.select(states, running)
    print(json.dumps({
        "running": sorted(running), "start": selection.start,
        "waiting_on_lock": selection.waiting_on_lock[:20],
        "waiting_on_slot": selection.waiting_on_slot[:20],
        "blocked_by_dependency": selection.blocked_by_dependency,
        "finished": scheduler.finished(states)}, indent=1))
    return 0


def cmd_set(args) -> int:
    roadmap, store = load(args)
    fields: dict = {}
    for key in ("blocker", "branch", "worktree", "spec_dir"):
        if getattr(args, key):
            fields[key] = getattr(args, key)
    if args.category:
        fields["error_category"] = args.category
    if args.branch_sha:
        fields["branch_sha"] = args.branch_sha
    if args.integrated_sha:
        fields["integrated_sha"] = args.integrated_sha
    if args.code_path or args.test_evidence or args.audit_note:
        fields["audit"] = {"code_paths": args.code_path or [],
                           "test_evidence": args.test_evidence or [],
                           "note": args.audit_note, "verdict": args.state}
    for fid in args.ids:
        store.set_state(fid, args.state, note=args.note, **fields)
    write_report(roadmap, store)
    return 0


def cmd_requeue(args) -> int:
    roadmap, store = load(args)
    for fid in args.ids:
        store.requeue(fid, args.note)
    write_report(roadmap, store)
    return 0


def cmd_evidence(args) -> int:
    roadmap, store = load(args)
    store.add_evidence(args.id, args.command, args.exit_code, args.log, args.sha)
    write_report(roadmap, store)
    return 0


def cmd_worktree(args) -> int:
    roadmap, store = load(args)
    wt = Worktrees(ROOT, store.data["integration_branch"])
    path = wt.create(args.id)
    build = ROOT / "Build"
    if build.exists() and not (path / "Build").exists():
        (path / "Build").symlink_to(build)   # gitignored; lets engine packages resolve
        exclude = ROOT / ".git" / "info" / "exclude"   # `Build/` in .gitignore skips a symlink
        if exclude.parent.is_dir() and "/Build\n" not in (
                exclude.read_text() if exclude.exists() else ""):
            with exclude.open("a") as f:
                f.write("/Build\n")
    engine = path / "Vendor" / "projectM"
    if not (engine / "CMakeLists.txt").exists() and (ROOT / "Vendor" / "projectM" / "CMakeLists.txt").exists():
        # The ANGLE and Rendering tests load test presets from the engine sources; a gate that runs
        # them in a worktree without the submodule fails on every preset load (ANL-016, 2026-11-13).
        subprocess.run(["git", "-c", "protocol.file.allow=always", "submodule", "update", "--init",
                        "--depth", "1", "--reference", str(ROOT / "Vendor" / "projectM"),
                        "Vendor/projectM"], cwd=str(path), capture_output=True, text=True, timeout=600)
    store.set_state(args.id, store.feature(args.id)["state"], worktree=str(path),
                    branch=branch_name(args.id), note="worktree ready")
    print(path)
    return 0


def gate_feature(roadmap: Roadmap, store: StateStore, feature_id: str | None,
                 simulator: str | None) -> bool:
    wt = Worktrees(ROOT, store.data["integration_branch"])
    if feature_id:
        checkout = wt.path(feature_id)
        if not wt.is_clean(checkout):
            raise GitError(["status"], 1, f"{checkout} has uncommitted or unmerged files; "
                           "gates run only on a clean checkout")
        changed = wt.changed_files(feature_id)
        frozen = DEFAULT_ROADMAP.relative_to(ROOT).as_posix()
        if frozen in changed:
            # The run froze the roadmap (its SHA-256 is in the state); status lives in the state and
            # docs/autonomous/STATUS.md. A branch that edits it would stop the scheduler (2026-11-14).
            print(f"FAIL frozen-roadmap: {feature_id} changes {frozen}; revert that file on its branch")
            store.record_attempt(feature_id, "policy", f"branch edits the frozen {frozen}")
            return False
        plan = gates_mod.plan_gates(checkout, changed, in_worktree=True,
                                    simulator_udid=simulator or gates_mod.default_simulator())
    else:
        checkout = ROOT
        base = store.data["repo_head_at_start"]
        code, out = sh(["git", "diff", "--name-only", f"{base}...HEAD"])
        changed = out.splitlines() if code == 0 else []
        plan = gates_mod.plan_gates(ROOT, changed, simulator_udid=simulator)
    log_dir = LOG_DIR / (feature_id or "integration") / time.strftime("%Y%m%dT%H%M%S")
    results = gates_mod.run_gates(plan, checkout, log_dir)
    sha = wt.head(cwd=checkout)
    for r in results:
        print(f"{'PASS' if r.ok else 'FAIL'} {r.gate.name} ({r.seconds:.0f} s) {r.log_path}")
        if feature_id:
            store.add_evidence(feature_id, r.command_line(), r.exit_code, r.log_path, sha)
    ok = gates_mod.all_passed(plan, results)
    if feature_id and ok:
        store.set_state(feature_id, "unit_passed", branch_sha=sha, note="worktree gates passed")
    elif feature_id:
        failed = results[-1]
        store.record_attempt(feature_id, failed.category or "test",
                             f"{failed.gate.name} failed; see {failed.log_path}")
    return ok


def cmd_gate(args) -> int:
    roadmap, store = load(args)
    ok = gate_feature(roadmap, store, args.id, args.simulator)
    write_report(roadmap, store)
    return 0 if ok else 1


def cmd_integrate(args) -> int:
    roadmap, store = load(args)
    rec = store.feature(args.id)
    wt = Worktrees(ROOT, store.data["integration_branch"])
    passed = rec["state"] in ("unit_passed", "simulator_passed", "integrated")
    result = wt.integrate(args.id, gates_passed=passed)
    if not result.ok:
        print(f"not integrated: {result.reason} {' '.join(result.conflicts)}", file=sys.stderr)
        if result.conflicts:
            store.record_attempt(args.id, "conflict",
                                 "merge conflict in " + ", ".join(result.conflicts))
        write_report(roadmap, store)
        return 1
    store.set_state(args.id, "integrated", integrated_sha=result.sha,
                    note="already merged" if result.already_merged else "merged")
    write_report(roadmap, store)
    print(result.sha)
    return 0


def cmd_run(args) -> int:
    """Unattended loop. Sequential by default; each feature runs the six skills in its own
    worktree, is gated, merged, and the integration checkout is gated again."""
    roadmap, store = load(args)
    budget = agent_driver.Budget(max_concurrency=args.concurrency,
                                 max_wall_seconds=args.budget_hours * 3600,
                                 max_spend_usd=args.budget_usd)
    scheduler = Scheduler(roadmap, args.concurrency)
    wt = Worktrees(ROOT, store.data["integration_branch"])
    started = time.monotonic()
    done = 0
    while not scheduler.finished(store.states()):
        try:
            budget.check(spent_usd=store.data["budget"]["spent_usd"],
                         wall_seconds=time.monotonic() - started, running=0, disk_path=ROOT)
        except agent_driver.BudgetExceeded as exc:
            print(f"stopping: {exc}; state is checkpointed, rerun to resume", file=sys.stderr)
            write_report(roadmap, store)
            return 3
        selection = scheduler.select(store.states(), set())
        if not selection.start:
            break
        fid = selection.start[0]
        feature = roadmap.features[fid]
        rec = store.feature(fid)
        path = wt.create(fid)
        spec_dir = Path(rec["spec_dir"]) if rec["spec_dir"] else path / "specs" / \
            spec_driver.spec_dir_name(feature, args.first_spec_number + done)
        store.set_state(fid, rec["state"], worktree=str(path), branch=branch_name(fid),
                        spec_dir=str(spec_dir.relative_to(path)), note="starting")
        turn = partial(_turn, timeout=args.turn_timeout, per_turn_usd=args.turn_usd)

        def on_step(result, state, fid=fid):
            store.add_cost(fid, result.cost_usd, result.seconds)
            store.add_evidence(fid, result.skill, 0 if result.ok else 1, result.log_path)
            if state:
                store.set_state(fid, state, command=result.skill)

        results = spec_driver.run_feature(feature, path, spec_dir, turn,
                                          log_dir=LOG_DIR / fid, on_step=on_step)
        failed = next((r for r in results if not r.ok), None)
        if failed:
            category = "prerequisite" if "logged in" in (failed.reason or "") else "toolchain"
            if category == "prerequisite":
                store.set_state(fid, store.feature(fid)["state"], note=failed.reason)
                print(f"stopping: {failed.reason}", file=sys.stderr)
                write_report(roadmap, store)
                return 4
            store.record_attempt(fid, category, f"{failed.skill}: {failed.reason}")
        elif gate_feature(roadmap, store, fid, None):
            merged = wt.integrate(fid, gates_passed=True)
            if merged.ok and gate_feature(roadmap, store, None, args.simulator):
                store.set_state(fid, "integrated", integrated_sha=merged.sha)
                done += 1
            elif merged.ok:
                store.record_attempt(fid, "test", "integration gates failed after the merge")
            else:
                store.record_attempt(fid, "conflict", merged.reason or "merge failed")
        write_report(roadmap, store)
    write_report(roadmap, store)
    return 0 if scheduler.finished(store.states()) else 2


def _turn(prompt, cwd, log_path, *, timeout, per_turn_usd):
    return agent_driver.run_claude(prompt, cwd, timeout=timeout, log_path=log_path,
                                   max_budget_usd=per_turn_usd)


def cmd_device_gate(args) -> int:
    roadmap, store = load(args)
    verdict = device_gate.decide(store.states(), device_gate.list_devices())
    print(json.dumps(verdict, indent=1))
    if verdict["phase"] != store.data["phase"]:
        store.data["phase"] = verdict["phase"]
        store.save()
    report.write_reports(store.data, {f.id: f.title for f in roadmap.features.values()}, verdict)
    return 0 if verdict["phase"] == "final_device" else 1


def cmd_report(args) -> int:
    roadmap, store = load(args)
    write_report(roadmap, store)
    print(json.dumps(report.summarize(store.data)["by_state"]))
    return 0


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--roadmap", default=str(DEFAULT_ROADMAP))
    ap.add_argument("--state-file", default=str(DEFAULT_STATE))
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("preflight").set_defaults(fn=cmd_preflight)
    p = sub.add_parser("init")
    p.add_argument("--base-branch", default="main")
    p.add_argument("--integration-branch", default=INTEGRATION_BRANCH)
    p.set_defaults(fn=cmd_init)
    p = sub.add_parser("next")
    p.add_argument("--concurrency", type=int, default=2)
    p.set_defaults(fn=cmd_next)
    p = sub.add_parser("set")
    p.add_argument("state")
    p.add_argument("ids", nargs="+")
    for name in ("note", "blocker", "category", "branch", "worktree", "spec-dir",
                 "branch-sha", "integrated-sha", "audit-note"):
        p.add_argument(f"--{name}")
    p.add_argument("--code-path", action="append")
    p.add_argument("--test-evidence", action="append")
    p.set_defaults(fn=cmd_set)
    p = sub.add_parser("requeue")
    p.add_argument("ids", nargs="+")
    p.add_argument("--note", required=True)
    p.set_defaults(fn=cmd_requeue)
    p = sub.add_parser("evidence")
    p.add_argument("id")
    p.add_argument("--command", required=True)
    p.add_argument("--exit-code", type=int, required=True)
    p.add_argument("--log")
    p.add_argument("--sha")
    p.set_defaults(fn=cmd_evidence)
    p = sub.add_parser("worktree")
    p.add_argument("id")
    p.set_defaults(fn=cmd_worktree)
    p = sub.add_parser("gate")
    p.add_argument("id", nargs="?")
    p.add_argument("--simulator")
    p.set_defaults(fn=cmd_gate)
    p = sub.add_parser("integrate")
    p.add_argument("id")
    p.set_defaults(fn=cmd_integrate)
    p = sub.add_parser("run")
    p.add_argument("--concurrency", type=int, default=2)
    p.add_argument("--budget-hours", type=float, default=8)
    p.add_argument("--budget-usd", type=float, default=200)
    p.add_argument("--turn-timeout", type=float, default=3600)
    p.add_argument("--turn-usd", type=float, default=15)
    p.add_argument("--first-spec-number", type=int, default=3)
    p.add_argument("--simulator")
    p.set_defaults(fn=cmd_run)
    sub.add_parser("device-gate").set_defaults(fn=cmd_device_gate)
    sub.add_parser("report").set_defaults(fn=cmd_report)
    return ap


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.fn(args)
    except (RoadmapError, StateError, GitError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
