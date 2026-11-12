#!/usr/bin/env python3
"""Checkpointed run state (AUTO-010): `.autonomous/state.json`, written atomically.

One record per feature: state, branch and commit SHAs, evidence, attempts and blocker. Every
change is saved by writing a temporary file, fsyncing it and renaming it over the old one, so
an interrupted run leaves either the old or the new state, never a torn file. Resuming loads
the file and refuses to continue against a different roadmap SHA.
"""
from __future__ import annotations

import json
import os
import tempfile
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_STATE = ROOT / ".autonomous" / "state.json"
SCHEMA_VERSION = 1

# The roadmap's state machine, in order.
PIPELINE = ("proposed", "audited", "specified", "planned", "tasked", "implementing", "built",
            "unit_passed", "simulator_passed", "integrated", "implementation_complete",
            "awaiting_final_device", "device_passed", "accepted")
SIDE_STATES = ("blocked", "skipped_existing", "infeasible")
STATES = PIPELINE + SIDE_STATES
ERROR_CATEGORIES = ("toolchain", "compiler", "test", "conflict", "platform", "license",
                    "security", "prerequisite", "policy")
MAX_ATTEMPTS = 3


class StateError(RuntimeError):
    pass


def now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def atomic_write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=1, sort_keys=True)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def new_feature_record(feature_id: str, priority: str, depends_on: list[str]) -> dict:
    return {"id": feature_id, "priority": priority, "depends_on": list(depends_on),
            "state": "proposed", "worktree": None, "branch": None, "branch_sha": None,
            "integrated_sha": None, "spec_dir": None, "last_command": None,
            "started": None, "finished": None, "evidence": [], "attempts": 0,
            "error_category": None, "blocker": None, "audit": None, "cost_usd": 0.0,
            "history": []}


class StateStore:
    def __init__(self, path: Path = DEFAULT_STATE):
        self.path = Path(path)
        self.data: dict = {}

    # -- lifecycle ---------------------------------------------------------------------
    def exists(self) -> bool:
        return self.path.exists()

    def init(self, roadmap_sha: str, repo_head: str, features: list[dict],
             base_branch: str, integration_branch: str) -> None:
        """Start a new run. `features` are dicts with id, priority, depends_on."""
        if self.exists():
            raise StateError(f"{self.path} exists; resume it or move it away")
        self.data = {
            "schema_version": SCHEMA_VERSION, "run_id": uuid.uuid4().hex[:12],
            "created": now(), "updated": now(), "roadmap_sha256": roadmap_sha,
            "repo_head_at_start": repo_head, "base_branch": base_branch,
            "integration_branch": integration_branch, "phase": "implementation",
            "budget": {"spent_usd": 0.0, "wall_seconds": 0.0},
            "features": {f["id"]: new_feature_record(f["id"], f["priority"], f["depends_on"])
                         for f in features},
        }
        self.save()

    def load(self, expect_roadmap_sha: str | None = None) -> "StateStore":
        try:
            self.data = json.loads(self.path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            raise StateError(f"no state at {self.path}") from None
        except json.JSONDecodeError as exc:
            raise StateError(f"{self.path} is not valid JSON: {exc}") from None
        if self.data.get("schema_version") != SCHEMA_VERSION:
            raise StateError(f"unsupported state schema {self.data.get('schema_version')}")
        if expect_roadmap_sha and self.data["roadmap_sha256"] != expect_roadmap_sha:
            raise StateError("the roadmap changed since this run froze it "
                             f"({self.data['roadmap_sha256'][:12]} != {expect_roadmap_sha[:12]}); "
                             "start a new run or restore the roadmap")
        return self

    def save(self) -> None:
        self.data["updated"] = now()
        atomic_write_json(self.path, self.data)

    # -- access ------------------------------------------------------------------------
    def feature(self, feature_id: str) -> dict:
        try:
            return self.data["features"][feature_id]
        except KeyError:
            raise StateError(f"unknown feature {feature_id}") from None

    def states(self) -> dict[str, str]:
        return {fid: rec["state"] for fid, rec in self.data["features"].items()}

    def in_flight(self) -> list[str]:
        """Features an interrupted run left between `audited` and `integrated`."""
        lo, hi = PIPELINE.index("specified"), PIPELINE.index("integrated")
        return sorted(fid for fid, rec in self.data["features"].items()
                      if rec["state"] in PIPELINE and lo <= PIPELINE.index(rec["state"]) < hi)

    # -- transitions -------------------------------------------------------------------
    def set_state(self, feature_id: str, state: str, *, command: str | None = None,
                  note: str | None = None, **fields: object) -> dict:
        if state not in STATES:
            raise StateError(f"unknown state '{state}'")
        rec = self.feature(feature_id)
        old = rec["state"]
        if state == "skipped_existing":
            audit = fields.get("audit") or rec.get("audit") or {}
            if not audit.get("code_paths") or not audit.get("test_evidence"):
                raise StateError(f"{feature_id}: skipped_existing needs code paths and passing "
                                 "test evidence, never a keyword match")
        if state == "blocked" and not (fields.get("blocker") or rec.get("blocker")):
            raise StateError(f"{feature_id}: blocked needs a reason")
        if state in PIPELINE and old in PIPELINE and state != old:
            if PIPELINE.index(state) < PIPELINE.index(old) and state != "implementing":
                raise StateError(f"{feature_id}: cannot move back from {old} to {state}")
        category = fields.get("error_category")
        if category is not None and category not in ERROR_CATEGORIES:
            raise StateError(f"unknown error category '{category}'")
        for key, value in fields.items():
            if key not in rec:
                raise StateError(f"unknown field '{key}'")
            rec[key] = value
        rec["state"] = state
        if command:
            rec["last_command"] = command
        if state == "implementing" and not rec["started"]:
            rec["started"] = now()
        if state in ("integrated", "skipped_existing", "blocked", "infeasible"):
            rec["finished"] = now()
        if state not in ("blocked", "infeasible"):
            rec["blocker"], rec["error_category"] = None, None
        rec["history"].append({"at": now(), "from": old, "to": state, "note": note})
        self.save()
        return rec

    def add_evidence(self, feature_id: str, command: str, exit_code: int,
                     log: str | None = None, sha: str | None = None) -> None:
        self.feature(feature_id)["evidence"].append(
            {"at": now(), "command": command, "exit_code": exit_code, "log": log, "sha": sha})
        self.save()

    def record_attempt(self, feature_id: str, category: str, reason: str) -> bool:
        """Count a failed attempt. Returns True while another retry is allowed; at the limit
        the feature becomes blocked with the last reason."""
        rec = self.feature(feature_id)
        rec["attempts"] += 1
        if rec["attempts"] >= MAX_ATTEMPTS:
            self.set_state(feature_id, "blocked", blocker=reason, error_category=category,
                           note=f"attempt {rec['attempts']} of {MAX_ATTEMPTS} failed")
            return False
        rec["history"].append({"at": now(), "from": rec["state"], "to": rec["state"],
                               "note": f"attempt {rec['attempts']} failed ({category}): {reason}"})
        self.save()
        return True

    def add_cost(self, feature_id: str | None, usd: float, seconds: float) -> None:
        self.data["budget"]["spent_usd"] += usd
        self.data["budget"]["wall_seconds"] += seconds
        if feature_id:
            self.feature(feature_id)["cost_usd"] += usd
        self.save()
