#!/usr/bin/env python3
"""Tests for scripts/autonomous/. Run: python3 scripts/autonomous/tests/test_autonomous.py"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import agent_driver  # noqa: E402
import device_gate  # noqa: E402
import gates  # noqa: E402
import report  # noqa: E402
import roadmap_parser as rp  # noqa: E402
import scheduler as sched  # noqa: E402
import spec_driver  # noqa: E402
import state as st  # noqa: E402
import worktrees as wtm  # noqa: E402

HEADER = ("| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | "
          "Acceptance criterion | Tech / test |\n|---|---|---|---|---|---|---|---|---|\n")


def row(fid, deps="—", priority="P1", effort="M", acceptance="It passes.", title=None):
    return (f"| **{fid}** | {title or 'Feature ' + fid} | Does a thing. | Gap candidate | "
            f"{priority} | {deps} | {effort} | {acceptance} | unit |\n")


def roadmap_from(rows: str) -> rp.Roadmap:
    features, problems = rp.parse_text(HEADER + rows)
    problems += rp.validate(features)
    if problems:
        raise rp.RoadmapError(problems)
    return rp.Roadmap("0" * 64, {f.id: f for f in features})


class RoadmapParserTests(unittest.TestCase):
    def test_repository_roadmap_parses_to_326_features(self):
        roadmap = rp.parse_roadmap()
        self.assertEqual(len(roadmap.features), 326)
        self.assertEqual(len(roadmap.sha256), 64)
        self.assertEqual(roadmap.features["MOD-013"].depends_on, ("MOD-001", "SCN-001"))
        self.assertEqual(roadmap.features["AUD-001"].depends_on, ())
        self.assertTrue(roadmap.features["AUD-014"].is_extension)
        self.assertEqual({f.area for f in roadmap.features.values()} >= {"AUD", "AUTO", "QA"},
                         True)

    def test_duplicate_id_fails(self):
        with self.assertRaises(rp.RoadmapError) as ctx:
            roadmap_from(row("AAA-001") + row("AAA-001"))
        self.assertTrue(any("duplicate ID AAA-001" in p for p in ctx.exception.problems))

    def test_unresolved_dependency_fails(self):
        with self.assertRaises(rp.RoadmapError) as ctx:
            roadmap_from(row("AAA-001", deps="ZZZ-009"))
        self.assertIn("AAA-001: unresolved dependency ZZZ-009", ctx.exception.problems)

    def test_cycle_fails_with_readable_path(self):
        with self.assertRaises(rp.RoadmapError) as ctx:
            roadmap_from(row("AAA-001", deps="AAA-003") + row("AAA-002", deps="AAA-001")
                         + row("AAA-003", deps="AAA-002"))
        cycle = next(p for p in ctx.exception.problems if p.startswith("dependency cycle"))
        self.assertIn("AAA-001 -> AAA-003 -> AAA-002 -> AAA-001", cycle)

    def test_illegal_priority_effort_and_missing_acceptance_fail(self):
        with self.assertRaises(rp.RoadmapError) as ctx:
            roadmap_from(row("AAA-001", priority="P7") + row("AAA-002", effort="XXL")
                         + row("AAA-003", acceptance=""))
        text = " ".join(ctx.exception.problems)
        self.assertIn("illegal priority 'P7'", text)
        self.assertIn("illegal effort 'XXL'", text)
        self.assertIn("AAA-003: missing acceptance check", text)

    def test_wrong_column_count_fails(self):
        features, problems = rp.parse_text("| **AAA-001** | only | three |\n")
        self.assertEqual(features, [])
        self.assertIn("expected 9", problems[0])

    def test_main_exit_codes(self):
        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp) / "bad.md"
            bad.write_text(HEADER + row("AAA-001", deps="AAA-001"), encoding="utf-8")
            self.assertEqual(rp.main([str(bad)]), 1)
        self.assertEqual(rp.main([]), 0)


class SchedulerTests(unittest.TestCase):
    def setUp(self):
        self.roadmap = roadmap_from(
            row("AAA-001", priority="P1") + row("AAA-002", deps="AAA-001", priority="P0")
            + row("BBB-001", priority="P0") + row("BBB-002", deps="BBB-001", priority="P3")
            + row("CCC-001", priority="P2") + row("CCC-002", deps="AAA-002,CCC-001",
                                                  priority="P2"))

    def test_order_respects_dependencies(self):
        order = sched.topological_order(self.roadmap)
        for f in self.roadmap.features.values():
            for dep in f.depends_on:
                self.assertLess(order.index(dep), order.index(f.id))

    def test_prerequisite_inherits_dependents_priority(self):
        eff = sched.effective_priorities(self.roadmap)
        self.assertEqual(eff["AAA-001"], "P0")       # needed by a P0 feature
        self.assertEqual(eff["BBB-002"], "P3")
        order = sched.topological_order(self.roadmap)
        self.assertEqual(order[:3], ["AAA-001", "AAA-002", "BBB-001"])
        self.assertEqual(order[-1], "BBB-002")

    def test_real_roadmap_schedules_everything_once(self):
        roadmap = rp.parse_roadmap()
        order = sched.topological_order(roadmap)
        self.assertEqual(sorted(order), sorted(roadmap.features))
        eff = sched.effective_priorities(roadmap)
        self.assertEqual(eff["FX-001"], "P0")        # CMP-001 (P0) depends on it

    def test_independent_work_runs_concurrently_within_limit(self):
        s = sched.Scheduler(self.roadmap, max_concurrency=2)
        selection = s.select({}, set())
        self.assertEqual(selection.start, ("AAA-001", "BBB-001"))
        self.assertEqual(selection.waiting_on_slot, ("CCC-001",))

    def test_shared_lock_serializes(self):
        s = sched.Scheduler(self.roadmap, max_concurrency=3,
                            lock_overrides={"AAA-001": ("x",), "BBB-001": ("x",)})
        selection = s.select({}, set())
        self.assertEqual(selection.start, ("AAA-001", "CCC-001"))
        self.assertEqual(selection.waiting_on_lock, ("BBB-001",))
        self.assertEqual(s.select({}, {"AAA-001"}).waiting_on_lock, ("BBB-001",))

    def test_dependency_must_be_done_and_blocked_propagates(self):
        s = sched.Scheduler(self.roadmap, max_concurrency=10)
        states = {"AAA-001": "blocked", "BBB-001": "integrated", "CCC-001": "skipped_existing"}
        selection = s.select(states, set())
        self.assertEqual(selection.start, ("BBB-002",))
        self.assertEqual(selection.blocked_by_dependency,
                         {"AAA-002": ("AAA-001",), "CCC-002": ("AAA-002",)})
        self.assertFalse(s.finished(states))

    def test_final_phase_waits_for_every_other_feature(self):
        roadmap = roadmap_from(row("QA-001") + row("QA-011", deps="QA-001", priority="P0")
                               + row("AAA-001", priority="P3"))
        s = sched.Scheduler(roadmap, max_concurrency=10)
        states = {"QA-001": "integrated"}
        self.assertEqual(s.ready(states, set()), ["AAA-001"])
        states["AAA-001"] = "blocked"
        self.assertEqual(s.ready(states, set()), ["QA-011"])

    def test_concurrency_ceiling_and_cycle(self):
        with self.assertRaises(ValueError):
            sched.Scheduler(self.roadmap, max_concurrency=11)
        features, _ = rp.parse_text(HEADER + row("AAA-001", deps="AAA-002")
                                    + row("AAA-002", deps="AAA-001"))
        with self.assertRaises(rp.RoadmapError):
            sched.topological_order(rp.Roadmap("0", {f.id: f for f in features}))


class StateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / ".autonomous" / "state.json"
        self.store = st.StateStore(self.path)
        self.store.init("a" * 64, "deadbeef", [
            {"id": "AAA-001", "priority": "P0", "depends_on": []},
            {"id": "AAA-002", "priority": "P1", "depends_on": ["AAA-001"]}], "main", "int")

    def test_resume_restores_progress_without_repeating(self):
        self.store.set_state("AAA-001", "implementing", branch="feature/aaa-001")
        self.store.set_state("AAA-001", "integrated", integrated_sha="abc123")
        again = st.StateStore(self.path).load(expect_roadmap_sha="a" * 64)
        self.assertEqual(again.feature("AAA-001")["integrated_sha"], "abc123")
        self.assertEqual(again.states(), {"AAA-001": "integrated", "AAA-002": "proposed"})
        self.assertEqual(again.in_flight(), [])
        with self.assertRaises(st.StateError):      # a second init must not wipe the run
            st.StateStore(self.path).init("a" * 64, "x", [], "main", "int")

    def test_changed_roadmap_refuses_to_resume(self):
        with self.assertRaises(st.StateError):
            st.StateStore(self.path).load(expect_roadmap_sha="b" * 64)

    def test_write_is_atomic(self):
        before = self.path.read_text()

        with self.assertRaises(TypeError):      # fails part-way through serialization
            st.atomic_write_json(self.path, {"a": 1, "x": object()})
        self.assertEqual(self.path.read_text(), before)
        self.assertEqual([p.name for p in self.path.parent.iterdir()], ["state.json"])

    def test_skipped_existing_needs_code_and_test_evidence(self):
        with self.assertRaises(st.StateError):
            self.store.set_state("AAA-001", "skipped_existing")
        with self.assertRaises(st.StateError):
            self.store.set_state("AAA-001", "skipped_existing",
                                 audit={"code_paths": ["a.swift"], "test_evidence": []})
        self.store.set_state("AAA-001", "skipped_existing", audit={
            "code_paths": ["a.swift:10"], "test_evidence": ["swift test: ATests.testX passed"]})
        self.assertEqual(self.store.feature("AAA-001")["state"], "skipped_existing")

    def test_blocked_needs_reason_and_states_do_not_go_backwards(self):
        with self.assertRaises(st.StateError):
            self.store.set_state("AAA-001", "blocked")
        self.store.set_state("AAA-001", "tasked")
        with self.assertRaises(st.StateError):
            self.store.set_state("AAA-001", "specified")
        with self.assertRaises(st.StateError):
            self.store.set_state("AAA-001", "done")
        with self.assertRaises(st.StateError):
            self.store.set_state("NOPE-001", "audited")

    def test_three_failed_attempts_block(self):
        self.store.set_state("AAA-001", "implementing")
        self.assertTrue(self.store.record_attempt("AAA-001", "compiler", "first"))
        self.assertTrue(self.store.record_attempt("AAA-001", "test", "second"))
        self.assertFalse(self.store.record_attempt("AAA-001", "test", "third"))
        rec = st.StateStore(self.path).load().feature("AAA-001")
        self.assertEqual((rec["state"], rec["attempts"], rec["blocker"], rec["error_category"]),
                         ("blocked", 3, "third", "test"))

    def test_in_flight_lists_interrupted_features(self):
        self.store.set_state("AAA-002", "planned")
        self.assertEqual(st.StateStore(self.path).load().in_flight(), ["AAA-002"])


class AgentDriverTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.cwd = Path(self.tmp.name)
        self.log = self.cwd / "logs" / "turn.json"

    def test_refuses_permission_bypass_and_blanket_shell(self):
        with self.assertRaises(agent_driver.AgentError):
            agent_driver.build_command("claude", "x", extra=("--dangerously-skip-permissions",))
        with self.assertRaises(agent_driver.AgentError):
            agent_driver.build_command("claude", "x", allowed_tools=("Read", "Bash"))
        cmd = agent_driver.build_command("claude", "x", max_turns=5, max_budget_usd=2)
        self.assertNotIn("--dangerously-skip-permissions", cmd)
        self.assertIn("Bash(git push:*)", cmd[cmd.index("--disallowedTools"):])
        self.assertNotIn("Bash(git push:*)",
                         cmd[cmd.index("--allowedTools"):cmd.index("--disallowedTools")])
        self.assertEqual(cmd[cmd.index("--max-budget-usd") + 1], "2.00")

    def test_timeout_is_a_failure_with_a_log(self):
        def runner(cmd, **kw):
            raise subprocess.TimeoutExpired(cmd, kw["timeout"])
        result = agent_driver.run_claude("p", self.cwd, timeout=5, log_path=self.log,
                                         binary="/bin/claude", runner=runner)
        self.assertFalse(result.ok)
        self.assertTrue(result.timed_out)
        self.assertEqual(result.exit_code, 124)
        logged = json.loads(self.log.read_text())
        self.assertEqual((logged["ok"], logged["timed_out"], logged["prompt"]), (False, True, "p"))

    def test_not_logged_in_is_a_prerequisite_failure_despite_exit_zero(self):
        def runner(cmd, **kw):
            return SimpleNamespace(returncode=0, stderr="", stdout=json.dumps(
                {"is_error": True, "result": "Not logged in · Please run /login"}))
        result = agent_driver.run_claude("p", self.cwd, binary="/bin/claude", runner=runner)
        self.assertEqual((result.ok, result.category), (False, "prerequisite"))
        self.assertNotEqual(result.exit_code, 0)

    def test_success_passes_only_allowlisted_environment(self):
        seen = {}

        def runner(cmd, **kw):
            seen.update(kw)
            return SimpleNamespace(returncode=0, stderr="", stdout=json.dumps(
                {"is_error": False, "result": "done", "total_cost_usd": 0.25}))
        env = {"PATH": "/usr/bin", "HOME": "/h", "ANTHROPIC_API_KEY": "sk-x", "GH_TOKEN": "t"}
        result = agent_driver.run_claude("p", self.cwd, binary="/bin/claude", runner=runner,
                                         env=env, log_path=self.log)
        self.assertTrue(result.ok)
        self.assertEqual(result.cost_usd, 0.25)
        self.assertEqual(seen["env"], {"PATH": "/usr/bin", "HOME": "/h"})
        self.assertEqual(seen["cwd"], str(self.cwd))

    def test_missing_binary_and_garbage_output_fail(self):
        result = agent_driver.run_claude("p", self.cwd, env={"CLAUDE_BIN": "/nonexistent/claude"})
        self.assertEqual((result.ok, result.exit_code), (False, 127))
        result = agent_driver.run_claude(
            "p", self.cwd, binary="/bin/claude",
            runner=lambda cmd, **kw: SimpleNamespace(returncode=0, stderr="", stdout="not json"))
        self.assertFalse(result.ok)

    def test_budget_limits(self):
        usage = lambda path: SimpleNamespace(free=100 * 1024 ** 3)  # noqa: E731
        budget = agent_driver.Budget(max_concurrency=2, max_wall_seconds=10, max_spend_usd=5)
        budget.check(spent_usd=1, wall_seconds=1, running=2, disk_path=self.cwd,
                     disk_usage=usage)
        for kwargs in ({"spent_usd": 5, "wall_seconds": 1, "running": 1},
                       {"spent_usd": 1, "wall_seconds": 10, "running": 1},
                       {"spent_usd": 1, "wall_seconds": 1, "running": 3}):
            with self.assertRaises(agent_driver.BudgetExceeded):
                budget.check(disk_path=self.cwd, disk_usage=usage, **kwargs)
        with self.assertRaises(agent_driver.BudgetExceeded):
            budget.check(spent_usd=0, wall_seconds=0, running=0, disk_path=self.cwd,
                         disk_usage=lambda path: SimpleNamespace(free=1))
        with self.assertRaises(ValueError):
            agent_driver.Budget(max_concurrency=11)


class SpecDriverTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.worktree = Path(self.tmp.name)
        self.spec_dir = self.worktree / "specs" / "003-aaa-001"
        self.feature = roadmap_from(row("AAA-001", title="Windowed FFT")).features["AAA-001"]
        self.calls: list[str] = []

    def turn(self, writes: dict[str, str], fail: str | None = None):
        def run_turn(prompt, cwd, log_path):
            skill = prompt.split()[0].lstrip("/")
            self.calls.append(skill)
            if skill in writes:
                self.spec_dir.mkdir(parents=True, exist_ok=True)
                (self.spec_dir / writes[skill]).write_text("content", encoding="utf-8")
            ok = skill != fail
            return SimpleNamespace(ok=ok, reason=None if ok else "boom", log_path=str(log_path),
                                   cost_usd=0.1, seconds=1.0)
        return run_turn

    ALL = {"speckit-specify": "spec.md", "speckit-plan": "plan.md", "speckit-tasks": "tasks.md"}

    def test_runs_six_skills_in_order_and_checkpoints(self):
        steps = []
        results = spec_driver.run_feature(
            self.feature, self.worktree, self.spec_dir, self.turn(self.ALL),
            log_dir=self.worktree / "logs", on_step=lambda r, s: steps.append((r.skill, s)))
        self.assertEqual(self.calls, list(spec_driver.SKILL_SEQUENCE))
        self.assertTrue(all(r.ok for r in results))
        self.assertEqual(steps[0], ("speckit-specify", "specified"))
        self.assertEqual(steps[-1], ("speckit-implement", "built"))

    def test_implementation_refused_without_spec_plan_tasks(self):
        writes = {"speckit-specify": "spec.md", "speckit-plan": "plan.md"}
        results = spec_driver.run_feature(self.feature, self.worktree, self.spec_dir,
                                          self.turn(writes), log_dir=self.worktree / "logs")
        self.assertNotIn("speckit-implement", self.calls)
        self.assertEqual(results[-1].skill, "speckit-tasks")
        self.assertIn("without tasks.md", results[-1].reason)
        self.assertEqual(spec_driver.missing_artifacts(self.spec_dir), ["tasks.md"])

    def test_failure_stops_and_resume_continues_after_last_good_skill(self):
        results = spec_driver.run_feature(self.feature, self.worktree, self.spec_dir,
                                          self.turn(self.ALL, fail="speckit-plan"),
                                          log_dir=self.worktree / "logs")
        self.assertEqual([r.skill for r in results],
                         ["speckit-specify", "speckit-clarify", "speckit-plan"])
        self.calls.clear()
        spec_driver.run_feature(self.feature, self.worktree, self.spec_dir, self.turn(self.ALL),
                                log_dir=self.worktree / "logs", start_after="speckit-clarify")
        self.assertEqual(self.calls, ["speckit-plan", "speckit-tasks", "speckit-analyze",
                                      "speckit-implement"])

    def test_prompts_carry_id_behavior_and_acceptance(self):
        prompts = spec_driver.prompts_for(self.feature)
        self.assertEqual(list(prompts), list(spec_driver.SKILL_SEQUENCE))
        self.assertIn("AAA-001", prompts["speckit-specify"])
        self.assertIn("It passes.", prompts["speckit-specify"])
        self.assertEqual(spec_driver.spec_dir_name(self.feature, 7), "007-aaa-001-windowed-fft")


def run(args, cwd):
    return subprocess.run(args, cwd=str(cwd), check=True, capture_output=True, text=True)


class WorktreeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name).resolve() / "repo"
        self.repo.mkdir()
        run(["git", "init", "-q", "-b", "main"], self.repo)
        run(["git", "config", "user.email", "t@example.invalid"], self.repo)
        run(["git", "config", "user.name", "T"], self.repo)
        (self.repo / "shared.txt").write_text("base\n")
        (self.repo / ".gitignore").write_text(".autonomous/\n")
        run(["git", "add", "."], self.repo)
        run(["git", "commit", "-q", "-m", "base"], self.repo)
        run(["git", "switch", "-q", "-c", "integration"], self.repo)
        self.wt = wtm.Worktrees(self.repo, "integration")

    def commit(self, feature_id, name, text):
        path = self.wt.create(feature_id)
        (path / name).write_text(text)
        run(["git", "add", "."], path)
        run(["git", "commit", "-q", "-m", f"{feature_id}: {name}"], path)
        return path

    def test_two_features_get_separate_checkouts_and_branches(self):
        a = self.commit("AAA-001", "a.txt", "a\n")
        b = self.commit("BBB-001", "b.txt", "b\n")
        self.assertNotEqual(a, b)
        self.assertEqual(self.wt.current_branch(a), "feature/aaa-001")
        self.assertFalse((b / "a.txt").exists())
        self.assertFalse((self.repo / "a.txt").exists())
        self.assertEqual(self.wt.create("AAA-001"), a)          # resume reuses it
        self.assertEqual(self.wt.overlapping("AAA-001", "BBB-001"), [])

    def test_integrate_needs_gates_and_is_idempotent(self):
        self.commit("AAA-001", "a.txt", "a\n")
        refused = self.wt.integrate("AAA-001", gates_passed=False)
        self.assertFalse(refused.ok)
        self.assertFalse((self.repo / "a.txt").exists())
        merged = self.wt.integrate("AAA-001", gates_passed=True)
        self.assertTrue(merged.ok)
        self.assertTrue((self.repo / "a.txt").exists())
        again = self.wt.integrate("AAA-001", gates_passed=True)
        self.assertTrue(again.already_merged)
        self.assertEqual(again.sha, merged.sha)                 # no duplicate merge commit
        self.assertEqual(run(["git", "rev-parse", "main"], self.repo).stdout.strip(),
                         run(["git", "rev-parse", "integration~1"], self.repo).stdout.strip())

    def test_conflicting_edits_are_detected_and_nothing_is_overwritten(self):
        self.commit("AAA-001", "shared.txt", "from A\n")
        self.commit("BBB-001", "shared.txt", "from B\n")
        self.assertEqual(self.wt.overlapping("AAA-001", "BBB-001"), ["shared.txt"])
        self.assertTrue(self.wt.integrate("AAA-001", gates_passed=True).ok)
        result = self.wt.integrate("BBB-001", gates_passed=True)
        self.assertFalse(result.ok)
        self.assertEqual(result.conflicts, ("shared.txt",))
        self.assertEqual((self.repo / "shared.txt").read_text(), "from A\n")
        self.assertTrue(self.wt.is_clean())                     # merge was aborted
        self.assertEqual((self.wt.path("BBB-001") / "shared.txt").read_text(), "from B\n")

    def test_cleanup_preserves_commits_and_uncommitted_work(self):
        path = self.commit("AAA-001", "a.txt", "a\n")
        sha = self.wt.head(cwd=path)
        (path / "wip.txt").write_text("unsaved")
        with self.assertRaises(wtm.GitError):
            self.wt.remove("AAA-001")
        self.assertTrue((path / "wip.txt").exists())
        (path / "wip.txt").unlink()
        self.wt.remove("AAA-001")
        self.assertFalse(path.exists())
        self.assertEqual(self.wt.head("feature/aaa-001"), sha)

    def test_dirty_or_wrong_branch_integration_checkout_is_refused(self):
        self.commit("AAA-001", "a.txt", "a\n")
        (self.repo / "shared.txt").write_text("local edit\n")
        self.assertIn("uncommitted", self.wt.integrate("AAA-001", gates_passed=True).reason)
        run(["git", "stash", "-q"], self.repo)
        run(["git", "switch", "-q", "main"], self.repo)
        self.assertIn("not on integration",
                      self.wt.integrate("AAA-001", gates_passed=True).reason)

    def test_git_policy_refuses_destructive_commands(self):
        for args in (["push", "origin", "main"], ["reset", "--hard", "HEAD~1"],
                     ["branch", "-D", "feature/x"], ["merge", "--force", "x"],
                     ["clean", "-fdx"], ["checkout", "--", "."], ["rebase", "main"],
                     ["worktree", "remove", "--force", "x"]):
            with self.assertRaises(wtm.GitPolicyError, msg=" ".join(args)):
                wtm.git(args, self.repo)


class GateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name)
        for name, deps in (("Core", ""), ("Mid", '.package(path: "../Core")'),
                           ("Top", '.package(path: "../Mid")'),
                           ("Engine", '.binaryTarget(name: "E", path: "../../Build/E.xcframework")')):
            (self.repo / "Packages" / name).mkdir(parents=True)
            (self.repo / "Packages" / name / "Package.swift").write_text(deps)

    def test_affected_packages_include_dependents(self):
        self.assertEqual(gates.affected_packages(self.repo, ["Packages/Core/Sources/x.swift"]),
                         ["Core", "Mid", "Top"])
        self.assertEqual(gates.affected_packages(self.repo, ["Packages/Top/Sources/x.swift"]),
                         ["Top"])
        self.assertEqual(gates.affected_packages(self.repo, ["docs/x.md"]), [])

    def test_plan_depends_on_changed_files_and_checkout_kind(self):
        names = lambda plan: [g.name for g in plan]  # noqa: E731
        self.assertEqual(names(gates.plan_gates(self.repo, ["docs/x.md"])),
                         ["compliance", "docs"])
        self.assertEqual(names(gates.plan_gates(self.repo, ["scripts/a.py"])),
                         ["compliance", "docs", "script-tests", "autonomous-tests"])
        in_wt = names(gates.plan_gates(self.repo, ["Packages/Engine/x.swift",
                                                   "Packages/Top/x.swift"], in_worktree=True))
        self.assertEqual(in_wt, ["compliance", "docs", "swift-test:Top"])
        (self.repo / "Packages" / "Top" / "Package.swift").write_text(
            'platforms: [.iOS("26.0")], .package(path: "../Mid")')
        ios_only = gates.plan_gates(self.repo, ["Packages/Top/x.swift"], in_worktree=True,
                                    simulator_udid="UDID")[-1]
        self.assertEqual((ios_only.name, ios_only.cwd), ("sim-test:Top", "Packages/Top"))
        self.assertIn("id=UDID", ios_only.command)
        self.assertIn("-test-timeouts-enabled", ios_only.command)
        full = gates.plan_gates(self.repo, ["Apps/App/x.swift"], simulator_udid="UDID")
        self.assertEqual(names(full), ["compliance", "docs", "xcodegen", "app-build:simulator",
                                       "app-tests:simulator"])
        test_cmd = full[-1].command
        self.assertIn("-test-timeouts-enabled", test_cmd)
        self.assertIn("CODE_SIGNING_ALLOWED=NO", test_cmd)

    def test_first_failure_stops_and_is_logged_with_category(self):
        plan = [gates.Gate("ok", (sys.executable, "-c", "print('fine')")),
                gates.Gate("bad", (sys.executable, "-c",
                                   "import sys; print('x.swift:1: error: nope'); sys.exit(1)"),
                           kind="unit"),
                gates.Gate("never", (sys.executable, "-c", "print('unreached')"))]
        results = gates.run_gates(plan, self.repo, self.repo / "logs")
        self.assertEqual([r.gate.name for r in results], ["ok", "bad"])
        self.assertFalse(gates.all_passed(plan, results))
        self.assertEqual(results[1].category, "compiler")
        self.assertIn("error: nope", Path(results[1].log_path).read_text())
        self.assertTrue(gates.all_passed(plan[:1], results[:1]))

    def test_timeout_and_missing_tool_are_toolchain_failures(self):
        slow = gates.Gate("slow", (sys.executable, "-c", "import time; time.sleep(5)"),
                          timeout=0.3)
        result = gates.run_gate(slow, self.repo, self.repo / "logs")
        self.assertEqual((result.exit_code, result.timed_out, result.category),
                         (124, True, "toolchain"))
        gone = gates.run_gate(gates.Gate("gone", ("no-such-tool-xyz",)), self.repo,
                              self.repo / "logs")
        self.assertEqual((gone.exit_code, gone.category), (127, "toolchain"))

    def test_categories(self):
        g = gates.Gate("swift-test:X", ("swift", "test"))
        self.assertEqual(gates.categorize(g, "XCTAssertEqual failed: error: x", False), "test")
        self.assertEqual(gates.categorize(gates.Gate("compliance", ("x",)), "", False),
                         "security")


class DeviceGateTests(unittest.TestCase):
    DEVICES = {"result": {"devices": [
        {"identifier": "A", "hardwareProperties": {"productType": "iPhone15,4", "udid": "U1",
                                                    "reality": "physical"},
         "deviceProperties": {"osVersionNumber": "27.0.1"},
         "connectionProperties": {"pairingState": "paired"}},
        {"identifier": "C", "hardwareProperties": {"productType": "iPad15,7", "udid": "U3",
                                                    "reality": "physical"},
         "deviceProperties": {"osVersionNumber": "26.5"},
         "connectionProperties": {"pairingState": "paired"}},
        {"identifier": "S", "hardwareProperties": {"productType": "iPad17,3",
                                                    "reality": "simulated"}}]}}

    def test_pending_implementation_blocks_device_phase_and_says_why(self):
        verdict = device_gate.decide({"A-001": "integrated", "A-002": "implementing"})
        self.assertFalse(verdict["implementation_complete"])
        self.assertEqual(verdict["phase"], "implementation")
        self.assertEqual(verdict["pending"], ["A-002"])
        self.assertIn("not implemented yet", verdict["reasons"][0])

    def test_blocked_feasible_feature_blocks_device_phase(self):
        verdict = device_gate.decide({"A-001": "integrated", "A-002": "blocked"})
        self.assertFalse(verdict["implementation_complete"])
        self.assertIn("strict completion allows none", verdict["reasons"][0])

    def test_complete_run_waits_for_missing_devices(self):
        states = {"A-001": "integrated", "A-002": "skipped_existing", "A-003": "infeasible"}
        devices = device_gate.parse_devices(self.DEVICES)
        self.assertEqual(sorted(devices), ["D1", "D3"])          # the simulator is ignored
        verdict = device_gate.decide(states, devices)
        self.assertTrue(verdict["implementation_complete"])
        self.assertEqual(verdict["phase"], "awaiting_final_device")
        self.assertEqual(len(verdict["device_prerequisites"]), 1)
        self.assertTrue(verdict["device_prerequisites"][0].startswith("D2: not visible"))

    def test_all_devices_present_opens_the_gate_and_updated_d3_is_flagged(self):
        payload = json.loads(json.dumps(self.DEVICES))
        payload["result"]["devices"][2]["hardwareProperties"]["reality"] = "physical"
        payload["result"]["devices"][2]["connectionProperties"] = {"pairingState": "paired"}
        devices = device_gate.parse_devices(payload)
        self.assertEqual(device_gate.decide({"A-001": "integrated"}, devices)["phase"],
                         "final_device")
        devices["D3"]["os"] = "27.2"
        self.assertIn("must not be updated", device_gate.device_prerequisites(devices)[0])


class ReportTests(unittest.TestCase):
    def test_counts_match_state_and_secrets_are_masked(self):
        with tempfile.TemporaryDirectory() as tmp:
            store = st.StateStore(Path(tmp) / "state.json")
            store.init("a" * 64, "head", [{"id": f"AAA-00{i}", "priority": "P0",
                                           "depends_on": []} for i in range(1, 5)],
                       "main", "int")
            store.set_state("AAA-001", "integrated", integrated_sha="1234567890abcdef",
                            branch="feature/aaa-001")
            store.set_state("AAA-002", "blocked", blocker="needs token=abc123secret here",
                            error_category="prerequisite")
            store.set_state("AAA-003", "skipped_existing", audit={
                "code_paths": ["A.swift:3"], "test_evidence": ["ATests passed"]})
            store.add_evidence("AAA-001", "swift test api_key=sk-abcdefgh12345", 0, "log.txt",
                               "1234567890abcdef")
            summary = report.summarize(store.data)
            self.assertEqual(summary["by_state"], {"proposed": 1, "integrated": 1, "blocked": 1,
                                                   "skipped_existing": 1})
            self.assertEqual(sum(summary["by_state"].values()), summary["total"])
            md, js = report.write_reports(store.data, {"AAA-001": "First"},
                                          device_gate.decide(store.states()),
                                          out_dir=Path(tmp) / "out")
            text = md.read_text() + js.read_text()
            self.assertNotIn("abc123secret", text)
            self.assertNotIn("sk-abcdefgh12345", text)
            self.assertIn("| integrated | 1 |", text)
            self.assertIn("may **not** start", text)
            self.assertEqual(json.loads(js.read_text())["features"]["AAA-001"]["state"],
                             "integrated")


class CIMonitorTests(unittest.TestCase):
    def fake(self, views):
        calls = []
        listing = [{"databaseId": 7, "headSha": "abc1234ffff", "status": "in_progress",
                    "conclusion": "", "event": "push", "createdAt": "x"}]

        def runner(cmd, **kw):
            calls.append(cmd[1:3])
            if cmd[1:3] == ["run", "list"]:
                return SimpleNamespace(returncode=0, stdout=json.dumps(listing), stderr="")
            return SimpleNamespace(returncode=0, stdout=json.dumps(views.pop(0)), stderr="")
        return runner, calls

    def view(self, status, conclusion, jobs):
        return {"databaseId": 7, "headSha": "abc1234ffff", "status": status,
                "conclusion": conclusion,
                "jobs": [{"name": n, "status": s, "conclusion": c, "databaseId": i}
                         for i, (n, s, c) in enumerate(jobs)]}

    def test_exits_when_complete_and_reports_early_job_results(self):
        import ci_monitor, io, contextlib
        runner, calls = self.fake([
            self.view("in_progress", "", [("linux", "completed", "failure"), ("mac", "in_progress", "")]),
            self.view("completed", "failure", [("linux", "completed", "failure"), ("mac", "completed", "success")])])
        out = io.StringIO()
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(ci_monitor, "ROOT", Path(tmp)), \
                contextlib.redirect_stdout(out):
            code = ci_monitor.main(["--sha", "abc1234", "--interval", "0"], runner=runner, sleep=lambda s: None)
        self.assertEqual(code, 1)
        text = out.getvalue()
        self.assertIn("job linux: failure", text)
        self.assertEqual(text.count("job linux"), 1)
        self.assertEqual(calls.count(["run", "view"]), 2)     # one call per check, no polling burst

    def test_a_run_replaced_in_the_queue_is_superseded_not_failed(self):
        import ci_monitor, io, contextlib
        runner, _ = self.fake([self.view("completed", "cancelled", [])])
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(ci_monitor, "ROOT", Path(tmp)), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(ci_monitor.main(["--sha", "abc1234", "--interval", "0"], runner=runner,
                                             sleep=lambda s: None), 3)

    def test_success(self):
        import ci_monitor, io, contextlib
        runner, _ = self.fake([self.view("completed", "success", [("linux", "completed", "success")])])
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(ci_monitor, "ROOT", Path(tmp)), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(ci_monitor.main(["--sha", "abc1234", "--interval", "0"], runner=runner,
                                             sleep=lambda s: None), 0)


class OrchestratorCommandTests(unittest.TestCase):
    """The CLI against a temporary state file and the real roadmap."""

    def test_init_set_next_report_round_trip(self):
        import orchestrator
        with tempfile.TemporaryDirectory() as tmp:
            state = str(Path(tmp) / "state.json")
            out = Path(tmp) / "out"
            original = report.REPORT_DIR
            report.write_reports.__defaults__ = (None, None, out)
            try:
                self.assertEqual(orchestrator.main(["--state-file", state, "init"]), 0)
                self.assertEqual(orchestrator.main(["--state-file", state, "init"]), 1)
                self.assertEqual(orchestrator.main(
                    ["--state-file", state, "set", "skipped_existing", "AUD-016"]), 1)
                self.assertEqual(orchestrator.main(
                    ["--state-file", state, "set", "blocked", "OSC-001", "--blocker", "policy",
                     "--category", "policy"]), 0)
                self.assertEqual(orchestrator.main(["--state-file", state, "next"]), 0)
                self.assertEqual(orchestrator.main(["--state-file", state, "report"]), 0)
                data = json.loads(Path(state).read_text())
                self.assertEqual(data["features"]["OSC-001"]["state"], "blocked")
                self.assertEqual(len(data["features"]), 326)
                self.assertTrue((out / "STATUS.md").exists())
            finally:
                report.write_reports.__defaults__ = (None, None, original)


if __name__ == "__main__":
    os.chdir(Path(__file__).resolve().parent.parent.parent.parent)
    unittest.main(verbosity=1)
