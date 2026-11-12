#!/usr/bin/env python3
"""Headless Claude execution (AUTO-007) and the unattended safety budget (AUTO-014).

`run_claude` starts one `claude -p` turn with an explicit working directory, a timeout, an
environment allowlist, an explicit tool allowlist and a persisted log. A timeout, a non-zero
exit, an error result or "not logged in" is a failure with a category, never a silent success.
Permission bypass flags are refused. `Budget` stops a run at its limits.
"""
from __future__ import annotations

import glob
import json
import os
import shutil
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path

HARD_MAX_CONCURRENCY = 10
FORBIDDEN_FLAGS = ("--dangerously-skip-permissions", "--allow-dangerously-skip-permissions")
FORBIDDEN_PERMISSION_MODES = ("bypassPermissions",)
# Variables a headless turn may inherit. Nothing else from the environment is passed on, so
# tokens and keys in the shell never reach the agent's tools.
ENV_ALLOWLIST = ("PATH", "HOME", "USER", "LOGNAME", "SHELL", "LANG", "LC_ALL", "LC_CTYPE",
                 "TMPDIR", "DEVELOPER_DIR", "TERM", "XDG_CONFIG_HOME", "CLAUDE_CONFIG_DIR")
# Tools a feature agent may use. Shell access is limited to named commands; there is no
# blanket Bash, and git push is not on the list.
DEFAULT_ALLOWED_TOOLS = (
    "Read", "Edit", "Write", "Glob", "Grep", "Skill",
    "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(git add:*)",
    "Bash(git commit:*)", "Bash(git rev-parse:*)", "Bash(swift build:*)", "Bash(swift test:*)",
    "Bash(xcodebuild:*)", "Bash(xcodegen generate:*)", "Bash(xcrun simctl:*)",
    "Bash(python3 scripts/:*)", "Bash(python3 .specify/scripts/:*)", "Bash(ls:*)",
    "Bash(mkdir:*)",
)
DEFAULT_DISALLOWED_TOOLS = ("Bash(git push:*)", "Bash(git reset:*)", "Bash(git clean:*)",
                            "Bash(rm -rf:*)", "Bash(curl:*)", "Bash(security:*)", "WebFetch",
                            "WebSearch")
APP_BUNDLE_GLOB = ("~/Library/Application Support/Claude/claude-code/*/*/"
                   "claude.app/Contents/MacOS/claude")


class AgentError(RuntimeError):
    pass


class BudgetExceeded(RuntimeError):
    """A limit was reached. The run stops; state is already checkpointed."""


@dataclass
class AgentResult:
    ok: bool
    exit_code: int
    category: str | None          # None when ok; else toolchain / prerequisite / test / ...
    reason: str | None
    text: str
    cost_usd: float
    seconds: float
    log_path: str | None
    timed_out: bool = False
    permission_denials: list = field(default_factory=list)


def find_claude(env: dict[str, str] | None = None) -> str | None:
    """CLAUDE_BIN, then PATH, then the newest CLI inside the Claude desktop app."""
    env = os.environ if env is None else env
    explicit = env.get("CLAUDE_BIN")
    if explicit:
        return explicit if os.access(explicit, os.X_OK) else None
    on_path = shutil.which("claude", path=env.get("PATH"))
    if on_path:
        return on_path
    bundled = sorted(glob.glob(os.path.expanduser(APP_BUNDLE_GLOB)))
    return bundled[-1] if bundled else None


def build_command(binary: str, prompt: str, *, allowed_tools=DEFAULT_ALLOWED_TOOLS,
                  disallowed_tools=DEFAULT_DISALLOWED_TOOLS, max_turns: int = 60,
                  max_budget_usd: float | None = None, model: str | None = None,
                  extra: tuple[str, ...] = ()) -> list[str]:
    for flag in extra:
        if flag in FORBIDDEN_FLAGS or flag in FORBIDDEN_PERMISSION_MODES:
            raise AgentError(f"refusing forbidden flag {flag}")
    if any(tool.strip() in ("Bash", "Bash(*)", "Bash(:*)") for tool in allowed_tools):
        raise AgentError("refusing blanket shell permission; list the commands")
    if max_turns < 1:
        raise AgentError("max_turns must be at least 1")
    cmd = [binary, "-p", prompt, "--output-format", "json", "--max-turns", str(max_turns),
           "--allowedTools", *allowed_tools, "--disallowedTools", *disallowed_tools]
    if max_budget_usd is not None:
        cmd += ["--max-budget-usd", f"{max_budget_usd:.2f}"]
    if model:
        cmd += ["--model", model]
    return cmd + list(extra)


def filtered_env(env: dict[str, str] | None = None) -> dict[str, str]:
    env = os.environ if env is None else env
    return {k: v for k, v in env.items() if k in ENV_ALLOWLIST}


def classify(payload: dict | None, exit_code: int, stderr: str) -> tuple[str, str]:
    text = ((payload or {}).get("result") or "") + " " + stderr
    low = text.lower()
    if "not logged in" in low or "/login" in low or "authentication" in low:
        return "prerequisite", "Claude CLI is not logged in (owner: run `claude` and /login)"
    if (payload or {}).get("subtype") == "error_max_turns":
        return "toolchain", "turn limit reached before the step finished"
    if "budget" in low and "exceed" in low:
        return "toolchain", "per-turn spend limit reached"
    return "toolchain", (text.strip()[:300] or f"claude exited {exit_code}")


def run_claude(prompt: str, cwd: Path, *, timeout: float = 3600, log_path: Path | None = None,
               binary: str | None = None, env: dict[str, str] | None = None,
               runner=subprocess.run, **command_options) -> AgentResult:
    """One headless turn. Never raises for a failed turn; returns a categorized result."""
    cwd = Path(cwd)
    if not cwd.is_dir():
        raise AgentError(f"working directory {cwd} does not exist")
    binary = binary or find_claude(env)
    started = time.monotonic()

    def finish(result: AgentResult, raw: str) -> AgentResult:
        if log_path:
            Path(log_path).parent.mkdir(parents=True, exist_ok=True)
            Path(log_path).write_text(json.dumps({
                "cwd": str(cwd), "prompt": prompt, "exit_code": result.exit_code,
                "ok": result.ok, "category": result.category, "reason": result.reason,
                "seconds": round(result.seconds, 1), "cost_usd": result.cost_usd,
                "timed_out": result.timed_out, "output": raw}, indent=1), encoding="utf-8")
        return result

    if not binary:
        return finish(AgentResult(False, 127, "prerequisite",
                                  "Claude CLI not found (set CLAUDE_BIN or install it)", "",
                                  0.0, 0.0, str(log_path) if log_path else None), "")
    cmd = build_command(binary, prompt, **command_options)
    try:
        proc = runner(cmd, cwd=str(cwd), env=filtered_env(env), capture_output=True,
                      text=True, timeout=timeout, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired as exc:
        raw = (exc.stdout or "") if isinstance(exc.stdout, str) else ""
        return finish(AgentResult(False, 124, "toolchain", f"timed out after {timeout:.0f} s",
                                  "", 0.0, time.monotonic() - started,
                                  str(log_path) if log_path else None, timed_out=True), raw)
    seconds = time.monotonic() - started
    payload = None
    try:
        payload = json.loads(proc.stdout)
    except (json.JSONDecodeError, TypeError):
        pass
    cost = float((payload or {}).get("total_cost_usd") or 0.0)
    failed = proc.returncode != 0 or payload is None or bool(payload.get("is_error"))
    if failed:
        category, reason = classify(payload, proc.returncode, proc.stderr or "")
        return finish(AgentResult(False, proc.returncode or 1, category, reason,
                                  (payload or {}).get("result") or "", cost, seconds,
                                  str(log_path) if log_path else None), proc.stdout or "")
    return finish(AgentResult(True, 0, None, None, payload.get("result") or "", cost, seconds,
                              str(log_path) if log_path else None,
                              permission_denials=payload.get("permission_denials") or []),
                  proc.stdout or "")


@dataclass
class Budget:
    """Limits for an unattended run. `check` raises BudgetExceeded at the first one reached."""
    max_concurrency: int = 2
    max_wall_seconds: float = 8 * 3600
    max_feature_seconds: float = 8 * 3600
    max_spend_usd: float = 200.0
    min_free_disk_bytes: int = 20 * 1024 ** 3

    def __post_init__(self) -> None:
        if not 1 <= self.max_concurrency <= HARD_MAX_CONCURRENCY:
            raise ValueError(f"max_concurrency must be 1..{HARD_MAX_CONCURRENCY}")

    def check(self, *, spent_usd: float, wall_seconds: float, running: int,
              disk_path: Path, disk_usage=shutil.disk_usage) -> None:
        if running > self.max_concurrency:
            raise BudgetExceeded(f"{running} agents running; limit {self.max_concurrency}")
        if spent_usd >= self.max_spend_usd:
            raise BudgetExceeded(f"spend ${spent_usd:.2f} reached limit ${self.max_spend_usd:.2f}")
        if wall_seconds >= self.max_wall_seconds:
            raise BudgetExceeded(f"wall time {wall_seconds:.0f} s reached limit "
                                 f"{self.max_wall_seconds:.0f} s")
        free = disk_usage(str(disk_path)).free
        if free < self.min_free_disk_bytes:
            raise BudgetExceeded(f"free disk {free // 1024 ** 3} GB below floor "
                                 f"{self.min_free_disk_bytes // 1024 ** 3} GB")
