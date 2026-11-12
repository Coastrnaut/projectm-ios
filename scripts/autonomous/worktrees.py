#!/usr/bin/env python3
"""Worktree isolation (AUTO-004) and the merge conflict arbiter (AUTO-011).

One branch `feature/<id-lowercase>` and one worktree per active slice, under
`.autonomous/worktrees/`. Integration is a non-fast-forward merge into the integration branch
by a single writer, only for a slice whose gates passed. A conflicting merge is aborted and
reported; nothing is overwritten. Failed work is kept: removing a worktree never deletes its
branch. Every git call goes through `git()`, which refuses pushes, forced operations, hard
resets and branch deletion.
"""
from __future__ import annotations

import subprocess
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
WORKTREE_DIR = ".autonomous/worktrees"

FORBIDDEN_SUBCOMMANDS = {"push", "clean", "filter-branch", "gc", "reflog", "update-ref"}
FORBIDDEN_ARGS = {"--force", "-f", "--force-with-lease", "--hard", "-D", "--delete", "-d",
                  "--mirror", "--prune"}


class GitPolicyError(RuntimeError):
    """A git command outside the run's mutation boundary was requested."""


class GitError(RuntimeError):
    def __init__(self, args: list[str], code: int, output: str):
        super().__init__(f"git {' '.join(args)} exited {code}: {output.strip()[:400]}")
        self.code, self.output = code, output


def check_policy(args: list[str]) -> None:
    if not args:
        raise GitPolicyError("empty git command")
    sub = args[0]
    if sub in FORBIDDEN_SUBCOMMANDS:
        raise GitPolicyError(f"git {sub} is not allowed in an autonomous run")
    # `git worktree remove` and `git merge --abort` are allowed; forced variants are not.
    bad = FORBIDDEN_ARGS & set(args[1:])
    if bad:
        raise GitPolicyError(f"git {sub} {' '.join(sorted(bad))} is not allowed")
    if sub == "branch" and any(a in ("-m", "-M", "--move") for a in args[1:]):
        raise GitPolicyError("renaming branches is not allowed")
    if sub == "checkout" and "--" in args:
        raise GitPolicyError("discarding working-tree changes is not allowed")
    if sub in ("reset", "restore", "rebase"):
        raise GitPolicyError(f"git {sub} is not allowed; integrate with merges")


def git(args: list[str], cwd: Path, check: bool = True) -> subprocess.CompletedProcess:
    check_policy(args)
    proc = subprocess.run(["git", *args], cwd=str(cwd), capture_output=True, text=True)
    if check and proc.returncode != 0:
        raise GitError(args, proc.returncode, proc.stdout + proc.stderr)
    return proc


def branch_name(feature_id: str) -> str:
    return f"feature/{feature_id.lower()}"


@dataclass
class MergeResult:
    ok: bool
    sha: str | None
    already_merged: bool = False
    conflicts: tuple[str, ...] = ()
    reason: str | None = None


class Worktrees:
    def __init__(self, repo: Path = ROOT, integration_branch: str = "autonomous/integration"):
        self.repo = Path(repo)
        self.integration_branch = integration_branch

    def path(self, feature_id: str) -> Path:
        return self.repo / WORKTREE_DIR / feature_id.lower()

    def head(self, ref: str = "HEAD", cwd: Path | None = None) -> str:
        return git(["rev-parse", ref], cwd or self.repo).stdout.strip()

    def branch_exists(self, name: str) -> bool:
        return git(["rev-parse", "--verify", "--quiet", f"refs/heads/{name}"], self.repo,
                   check=False).returncode == 0

    def current_branch(self, cwd: Path | None = None) -> str:
        return git(["rev-parse", "--abbrev-ref", "HEAD"], cwd or self.repo).stdout.strip()

    def is_clean(self, cwd: Path | None = None) -> bool:
        return not git(["status", "--porcelain"], cwd or self.repo).stdout.strip()

    def create(self, feature_id: str) -> Path:
        """Create (or reuse) the feature's branch and worktree from the integration branch.
        Idempotent, so a resumed run gets the same checkout back."""
        path = self.path(feature_id)
        name = branch_name(feature_id)
        if path.exists() and (path / ".git").exists():
            if self.current_branch(path) != name:
                raise GitError(["worktree"], 1, f"{path} is on another branch")
            return path
        path.parent.mkdir(parents=True, exist_ok=True)
        if self.branch_exists(name):
            git(["worktree", "add", str(path), name], self.repo)
        else:
            git(["worktree", "add", "-b", name, str(path), self.integration_branch], self.repo)
        return path

    def remove(self, feature_id: str) -> None:
        """Remove the checkout only when it is clean. The branch and its commits stay."""
        path = self.path(feature_id)
        if not path.exists():
            return
        if not self.is_clean(path):
            raise GitError(["worktree", "remove"], 1,
                           f"{path} has uncommitted work; it is preserved")
        git(["worktree", "remove", str(path)], self.repo)

    def changed_files(self, feature_id: str) -> list[str]:
        """Files the feature branch changed since it left the integration branch."""
        out = git(["diff", "--name-only",
                   f"{self.integration_branch}...{branch_name(feature_id)}"], self.repo).stdout
        return [line for line in out.splitlines() if line]

    def overlapping(self, feature_a: str, feature_b: str) -> list[str]:
        """Files both slices changed: these two must be integrated one after the other, with
        the second re-checked after the first lands."""
        return sorted(set(self.changed_files(feature_a)) & set(self.changed_files(feature_b)))

    def is_merged(self, feature_id: str) -> bool:
        return git(["merge-base", "--is-ancestor", branch_name(feature_id),
                    self.integration_branch], self.repo, check=False).returncode == 0

    def integrate(self, feature_id: str, gates_passed: bool, message: str | None = None
                  ) -> MergeResult:
        """Merge the feature branch into the integration branch. One writer: the main
        checkout must be on the integration branch and clean. Idempotent for a branch that
        is already merged, so a resumed run makes no duplicate merge commit."""
        if not gates_passed:
            return MergeResult(False, None, reason="gates have not passed; not integrating")
        name = branch_name(feature_id)
        if not self.branch_exists(name):
            return MergeResult(False, None, reason=f"branch {name} does not exist")
        if self.current_branch() != self.integration_branch:
            return MergeResult(False, None,
                               reason=f"main checkout is not on {self.integration_branch}")
        if not self.is_clean():
            return MergeResult(False, None, reason="integration checkout has uncommitted changes")
        if self.is_merged(feature_id):
            return MergeResult(True, self.head(), already_merged=True)
        proc = git(["merge", "--no-ff", "--no-edit", "-m",
                    message or f"Integrate {feature_id} ({name})", name], self.repo, check=False)
        if proc.returncode != 0:
            conflicts = tuple(
                line for line in git(["diff", "--name-only", "--diff-filter=U"],
                                     self.repo).stdout.splitlines() if line)
            git(["merge", "--abort"], self.repo, check=False)
            return MergeResult(False, None, conflicts=conflicts,
                               reason="merge conflict" if conflicts
                               else (proc.stdout + proc.stderr).strip()[:300])
        return MergeResult(True, self.head())
