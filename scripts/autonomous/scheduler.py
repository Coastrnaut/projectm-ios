#!/usr/bin/env python3
"""Dependency scheduler (AUTO-003): topological ready queue, bounded parallelism, file locks.

Order: P0, then P1, P2, P3, with stable ID tiebreaking. A prerequisite inherits the highest
priority of anything that depends on it (CMP-001 is P0 and needs FX-001, a P1 row, so FX-001
is scheduled as P0). A feature is ready when every dependency is in a "done" state. Features
that share an ownership lock (a package or file set) never run at the same time.
"""
from __future__ import annotations

from dataclasses import dataclass

try:
    from .roadmap_parser import PRIORITIES, Feature, Roadmap, RoadmapError, find_cycle
except ImportError:  # run as a script or with scripts/autonomous on sys.path
    from roadmap_parser import PRIORITIES, Feature, Roadmap, RoadmapError, find_cycle

HARD_MAX_CONCURRENCY = 10      # CLAUDE.md: at most 10 agents at once, in total
DEFAULT_CONCURRENCY = 2        # roadmap: default 2 isolated implementation worktrees

# The states that satisfy a dependency, and the ones that end a feature without doing so.
DONE_STATES = frozenset({"integrated", "skipped_existing", "implementation_complete",
                         "awaiting_final_device", "device_passed", "accepted"})
BLOCKED_STATES = frozenset({"blocked", "infeasible"})

# Final-phase rows: the physical-device matrix and the release evidence built on it. They become
# ready only when every other feature is terminal (roadmap: "Run complete D1/D2/D3 matrix only
# after all implementation tasks close"; device testing is the last stage).
FINAL_PHASE = frozenset({"QA-011", "QA-012"})

# Default ownership: the package or directory an area mostly writes to. Two features with a
# common lock are serialized. `locks_for` can be replaced by a per-feature override map.
AREA_LOCKS: dict[str, tuple[str, ...]] = {
    "AUD": ("Packages/CaptureKit", "Packages/AudioCore"),
    "ANL": ("Packages/AnalysisFeatures",),
    "VIS": ("Packages/VisualGenerators",),
    # FX-001 put effects in Packages/VisualGenerators (ADR-0010); FX-019 also edits Rendering.
    "FX": ("Packages/VisualGenerators", "Packages/Compositor", "Packages/Rendering"),
    "CMP": ("Packages/Compositor",),
    "MED": ("Packages/MediaSources",),
    "CAM": ("Packages/MediaSources",),
    "PRE": ("Packages/PresetLibrary",),
    "SCN": ("Packages/SceneDocuments",),
    "MOD": ("Packages/ParameterGraph",),
    "SHOW": ("Packages/PerformanceControl",),
    "MIDI": ("Packages/PerformanceControl",),
    "OSC": ("Packages/PerformanceControl",),
    "REC": ("Packages/Recording",),
    "OUT": ("Packages/Compositor", "Apps/projectM-iOS"),
    "UIX": ("Apps/projectM-iOS",),
    "ACC": ("Apps/projectM-iOS",),
    "PERF": ("Packages/Rendering", "Packages/Diagnostics"),
    "FILE": ("Packages/LocalPortability",),
    "SHD": ("Packages/VisualGenerators", "Packages/ParameterGraph"),
    "QA": ("scripts", "Packages/TestSupport"),
    "AUTO": ("scripts/autonomous",),
}


def effective_priorities(roadmap: Roadmap) -> dict[str, str]:
    """Each feature's own priority raised to the highest priority among its dependents."""
    rank = {fid: PRIORITIES.index(f.priority) for fid, f in roadmap.features.items()}
    for fid in topological_order(roadmap, by_priority=False)[::-1]:
        for dep in roadmap.features[fid].depends_on:
            rank[dep] = min(rank[dep], rank[fid])
    return {fid: PRIORITIES[r] for fid, r in rank.items()}


def topological_order(roadmap: Roadmap, by_priority: bool = True) -> list[str]:
    """A full order in which every dependency precedes its dependents.

    With by_priority, ties are broken by effective priority and then by ID; otherwise by ID.
    Raises RoadmapError on a cycle.
    """
    cycle = find_cycle(roadmap.features)
    if cycle:
        raise RoadmapError(["dependency cycle: " + " -> ".join(cycle)])
    eff = effective_priorities(roadmap) if by_priority else {}
    key = (lambda fid: (PRIORITIES.index(eff[fid]), fid)) if by_priority else (lambda fid: fid)
    remaining = {fid: set(f.depends_on) for fid, f in roadmap.features.items()}
    order: list[str] = []
    while remaining:
        ready = sorted((fid for fid, deps in remaining.items() if not deps), key=key)
        nxt = ready[0]
        order.append(nxt)
        del remaining[nxt]
        for deps in remaining.values():
            deps.discard(nxt)
    return order


def locks_for(feature: Feature, overrides: dict[str, tuple[str, ...]] | None = None
              ) -> tuple[str, ...]:
    if overrides and feature.id in overrides:
        return tuple(overrides[feature.id])
    return AREA_LOCKS.get(feature.area, (f"area:{feature.area}",))


@dataclass(frozen=True)
class Selection:
    start: tuple[str, ...]                 # features to start now
    waiting_on_lock: tuple[str, ...]       # ready, but a running feature owns their files
    waiting_on_slot: tuple[str, ...]       # ready, but concurrency is full
    blocked_by_dependency: dict[str, tuple[str, ...]]  # feature -> blocked prerequisites


class Scheduler:
    def __init__(self, roadmap: Roadmap, max_concurrency: int = DEFAULT_CONCURRENCY,
                 lock_overrides: dict[str, tuple[str, ...]] | None = None):
        if not 1 <= max_concurrency <= HARD_MAX_CONCURRENCY:
            raise ValueError(f"max_concurrency must be 1..{HARD_MAX_CONCURRENCY}")
        self.roadmap = roadmap
        self.max_concurrency = max_concurrency
        self.lock_overrides = lock_overrides
        self.order = topological_order(roadmap)
        self.priority = effective_priorities(roadmap)

    def blocked_by_dependency(self, states: dict[str, str]) -> dict[str, tuple[str, ...]]:
        """Features that cannot become ready because a prerequisite (transitively) is blocked."""
        blocked: dict[str, tuple[str, ...]] = {}
        for fid in self.order:  # dependencies come first, so one pass is transitive
            f = self.roadmap.features[fid]
            if states.get(fid) in DONE_STATES or states.get(fid) in BLOCKED_STATES:
                continue
            bad = tuple(d for d in f.depends_on
                        if states.get(d) in BLOCKED_STATES or d in blocked)
            if bad:
                blocked[fid] = bad
        return blocked

    def ready(self, states: dict[str, str], running: set[str]) -> list[str]:
        """Not started, not running, every dependency done; in schedule order."""
        out = []
        others_terminal = all(states.get(f) in DONE_STATES or states.get(f) in BLOCKED_STATES
                              for f in self.roadmap.features if f not in FINAL_PHASE)
        for fid in self.order:
            state = states.get(fid, "proposed")
            if fid in running or state in DONE_STATES or state in BLOCKED_STATES:
                continue
            if fid in FINAL_PHASE and not others_terminal:
                continue
            if all(states.get(d) in DONE_STATES for d in self.roadmap.features[fid].depends_on):
                out.append(fid)
        # Highest effective priority first, then schedule order (2026-11-13: the plain schedule
        # order put a P2 row whose dependencies finished early ahead of a P0 row whose last
        # dependency had just been integrated, and the P2 row took the shared area lock).
        position = {fid: i for i, fid in enumerate(self.order)}
        return sorted(out, key=lambda fid: (PRIORITIES.index(self.priority[fid]), position[fid]))

    def select(self, states: dict[str, str], running: set[str]) -> Selection:
        held: set[str] = set()
        for fid in running:
            held.update(locks_for(self.roadmap.features[fid], self.lock_overrides))
        start: list[str] = []
        on_lock: list[str] = []
        on_slot: list[str] = []
        for fid in self.ready(states, running):
            locks = set(locks_for(self.roadmap.features[fid], self.lock_overrides))
            if locks & held:
                on_lock.append(fid)
            elif len(running) + len(start) >= self.max_concurrency:
                on_slot.append(fid)
            else:
                start.append(fid)
                held |= locks
        return Selection(tuple(start), tuple(on_lock), tuple(on_slot),
                         self.blocked_by_dependency(states))

    def finished(self, states: dict[str, str]) -> bool:
        return all(states.get(fid) in DONE_STATES or states.get(fid) in BLOCKED_STATES
                   for fid in self.roadmap.features)
