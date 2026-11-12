#!/usr/bin/env python3
"""Spec Kit generation driver (AUTO-005, AUTO-006).

Runs the repository's installed skills for one feature, in order, through the agent driver,
and refuses to start `/speckit-implement` until spec.md, plan.md and tasks.md exist. Ambiguity
is resolved by the agent with conservative, local-first defaults; each material decision must
appear in the spec's Clarifications section (and an ADR when it overrides a default).

The same sequence is followed when a Claude session executes a feature itself (no logged-in
CLI): `prompts_for` gives the exact skill invocations and `missing_artifacts` is the gate.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

try:
    from .roadmap_parser import Feature
except ImportError:
    from roadmap_parser import Feature

SKILL_SEQUENCE = ("speckit-specify", "speckit-clarify", "speckit-plan", "speckit-tasks",
                  "speckit-analyze", "speckit-implement")
# The state reached when a skill succeeds.
STATE_AFTER = {"speckit-specify": "specified", "speckit-clarify": "specified",
               "speckit-plan": "planned", "speckit-tasks": "tasked",
               "speckit-analyze": "tasked", "speckit-implement": "built"}
REQUIRED_BEFORE_IMPLEMENT = ("spec.md", "plan.md", "tasks.md")
ROADMAP_PATH = "docs/FEATURE_ROADMAP_AUTONOMOUS.md"

COMMON_RULES = (
    "Follow CLAUDE.md and .specify/memory/constitution.md; they win over the roadmap. "
    "Public Apple APIs only. No networking APIs unless an accepted ADR allows them. "
    "Do not push, change signing, or touch files outside this feature's scope. "
    "No co-author or generated-by lines in commits."
)


class SpecDriverError(RuntimeError):
    pass


def spec_dir_name(feature: Feature, number: int) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", feature.title.lower()).strip("-")[:40].rstrip("-")
    return f"{number:03d}-{feature.id.lower()}-{slug}"


def prompts_for(feature: Feature) -> dict[str, str]:
    """The skill invocation for each step, as the roadmap words them."""
    deps = ", ".join(feature.depends_on) or "none"
    return {
        "speckit-specify": (
            f"/speckit-specify Implement {feature.id} ({feature.title}) from {ROADMAP_PATH}. "
            f"Observable behavior, verbatim: \"{feature.behavior}\" "
            f"Acceptance, verbatim: \"{feature.acceptance}\" "
            f"Dependencies: {deps}. Honor the repository constitution. Prefix every "
            f"requirement and success-criterion ID with {feature.id} so IDs never collide."),
        "speckit-clarify": (
            "/speckit-clarify Resolve any ambiguity conservatively using local-first and "
            "public iOS APIs; record each decision as a Clarifications bullet; do not ask "
            "the user for routine decisions."),
        "speckit-plan": (
            "/speckit-plan Extend existing packages and contracts where possible; design "
            "deterministic tests, local persistence and rollback."),
        "speckit-tasks": (
            "/speckit-tasks Produce granular test-first tasks, explicit acceptance evidence, "
            "and no premature physical-device execution; tag device-only checks {device}."),
        "speckit-analyze": (
            "/speckit-analyze Check spec/plan/tasks consistency, licensing, privacy and "
            "cross-feature dependencies; apply the fixes."),
        "speckit-implement": (
            f"/speckit-implement Implement only {feature.id} and its missing prerequisite "
            "deltas, run package/build/simulator checks, and commit on this feature branch."),
    }


def missing_artifacts(spec_dir: Path, names=REQUIRED_BEFORE_IMPLEMENT) -> list[str]:
    """Required files that are absent or empty."""
    return [n for n in names
            if not (spec_dir / n).is_file() or not (spec_dir / n).read_text(
                encoding="utf-8", errors="replace").strip()]


@dataclass
class StepResult:
    skill: str
    ok: bool
    reason: str | None
    log_path: str | None
    cost_usd: float
    seconds: float


def run_feature(feature: Feature, worktree: Path, spec_dir: Path, run_turn, *,
                log_dir: Path, start_after: str | None = None,
                on_step=None) -> list[StepResult]:
    """Run the remaining skills for a feature. Stops at the first failure.

    `run_turn(prompt, cwd, log_path)` returns an object with ok, reason, log_path, cost_usd and
    seconds (agent_driver.run_claude with its options bound). `start_after` resumes after a
    skill that already succeeded. `on_step(result, state)` checkpoints after every skill.
    """
    sequence = list(SKILL_SEQUENCE)
    if start_after:
        if start_after not in sequence:
            raise SpecDriverError(f"unknown skill {start_after}")
        sequence = sequence[sequence.index(start_after) + 1:]
    prompts = prompts_for(feature)
    results: list[StepResult] = []
    for skill in sequence:
        if skill == "speckit-implement":
            missing = missing_artifacts(spec_dir)
            if missing:
                results.append(StepResult(skill, False,
                                          "missing before implementation: " + ", ".join(missing),
                                          None, 0.0, 0.0))
                if on_step:
                    on_step(results[-1], None)
                break
        log_path = log_dir / f"{feature.id}-{skill}.json"
        turn = run_turn(f"{prompts[skill]}\n\n{COMMON_RULES}", worktree, log_path)
        result = StepResult(skill, turn.ok, turn.reason, turn.log_path, turn.cost_usd,
                            turn.seconds)
        if result.ok and skill in ("speckit-specify", "speckit-plan", "speckit-tasks"):
            expected = {"speckit-specify": "spec.md", "speckit-plan": "plan.md",
                        "speckit-tasks": "tasks.md"}[skill]
            if missing_artifacts(spec_dir, (expected,)):
                result = StepResult(skill, False, f"{skill} finished without {expected}",
                                    turn.log_path, turn.cost_usd, turn.seconds)
        results.append(result)
        if on_step:
            on_step(result, STATE_AFTER[skill] if result.ok else None)
        if not result.ok:
            break
    return results
