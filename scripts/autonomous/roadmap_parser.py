#!/usr/bin/env python3
"""Parse docs/FEATURE_ROADMAP_AUTONOMOUS.md into a validated dependency DAG (AUTO-001).

The feature tables are the inventory: one row per stable ID with nine columns
(ID, Feature, Observable behavior, Gap status, Priority, Depends on, Effort, Acceptance, Tech).
Validation rejects duplicate IDs, unresolved dependencies, cycles, illegal priorities or
efforts, and rows without an acceptance check, before anything is edited.

Run: python3 scripts/autonomous/roadmap_parser.py [--json] [roadmap.md]
Standard library only.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_ROADMAP = ROOT / "docs" / "FEATURE_ROADMAP_AUTONOMOUS.md"

PRIORITIES = ("P0", "P1", "P2", "P3")
EFFORTS = ("XS", "S", "M", "L", "XL")
ID_RE = re.compile(r"^[A-Z]{2,5}-\d{3}$")
ROW_RE = re.compile(r"^\|\s*\*\*([A-Z]{2,5}-\d{3})\*\*\s*\|(.*)\|\s*$")
NO_DEPS = {"", "—", "-", "–", "none", "None"}


class RoadmapError(ValueError):
    """The roadmap is not a usable DAG. `problems` lists every finding."""

    def __init__(self, problems: list[str]):
        super().__init__("; ".join(problems))
        self.problems = problems


@dataclass(frozen=True)
class Feature:
    id: str
    title: str
    behavior: str
    gap: str
    priority: str
    depends_on: tuple[str, ...]
    effort: str
    acceptance: str
    tech: str
    line: int

    @property
    def area(self) -> str:
        return self.id.split("-")[0]

    @property
    def is_extension(self) -> bool:
        return self.gap.lower().startswith("extension")


@dataclass
class Roadmap:
    sha256: str
    features: dict[str, Feature] = field(default_factory=dict)

    def dependents(self) -> dict[str, list[str]]:
        out: dict[str, list[str]] = {fid: [] for fid in self.features}
        for f in self.features.values():
            for dep in f.depends_on:
                if dep in out:
                    out[dep].append(f.id)
        return out

    def to_json(self) -> dict:
        return {"sha256": self.sha256, "count": len(self.features),
                "features": [asdict(f) for f in self.features.values()]}


def split_row(line: str) -> list[str]:
    """Cells of a Markdown table row. A backslash-escaped pipe stays inside its cell."""
    body = line.strip()
    if body.startswith("|"):
        body = body[1:]
    if body.endswith("|") and not body.endswith("\\|"):
        body = body[:-1]
    return [c.replace("\\|", "|").strip() for c in re.split(r"(?<!\\)\|", body)]


def parse_text(text: str) -> tuple[list[Feature], list[str]]:
    features: list[Feature] = []
    problems: list[str] = []
    for number, line in enumerate(text.splitlines(), start=1):
        if not ROW_RE.match(line):
            continue
        cells = split_row(line)
        fid = cells[0].strip("*")
        if len(cells) != 9:
            problems.append(f"line {number}: {fid} has {len(cells)} columns, expected 9")
            continue
        deps_cell = cells[5]
        deps = () if deps_cell in NO_DEPS else tuple(
            d.strip() for d in deps_cell.split(",") if d.strip())
        features.append(Feature(id=fid, title=cells[1], behavior=cells[2], gap=cells[3],
                                priority=cells[4], depends_on=deps, effort=cells[6],
                                acceptance=cells[7], tech=cells[8], line=number))
    return features, problems


def find_cycle(features: dict[str, Feature]) -> list[str] | None:
    """One dependency cycle as a path that ends where it starts, or None."""
    WHITE, GREY, BLACK = 0, 1, 2
    colour = {fid: WHITE for fid in features}
    for start in sorted(features):
        if colour[start] != WHITE:
            continue
        stack: list[tuple[str, int]] = [(start, 0)]
        path = [start]
        colour[start] = GREY
        while stack:
            node, index = stack[-1]
            deps = [d for d in features[node].depends_on if d in features]
            if index < len(deps):
                stack[-1] = (node, index + 1)
                nxt = deps[index]
                if colour[nxt] == GREY:
                    return path[path.index(nxt):] + [nxt]
                if colour[nxt] == WHITE:
                    colour[nxt] = GREY
                    stack.append((nxt, 0))
                    path.append(nxt)
            else:
                colour[node] = BLACK
                stack.pop()
                path.pop()
    return None


def validate(features: list[Feature]) -> list[str]:
    problems: list[str] = []
    seen: dict[str, int] = {}
    for f in features:
        if f.id in seen:
            problems.append(f"duplicate ID {f.id} (lines {seen[f.id]} and {f.line})")
        seen.setdefault(f.id, f.line)
        if not ID_RE.match(f.id):
            problems.append(f"{f.id}: malformed ID")
        if f.priority not in PRIORITIES:
            problems.append(f"{f.id}: illegal priority '{f.priority}'")
        if f.effort not in EFFORTS:
            problems.append(f"{f.id}: illegal effort '{f.effort}'")
        if not f.acceptance:
            problems.append(f"{f.id}: missing acceptance check")
        if not f.title or not f.behavior:
            problems.append(f"{f.id}: missing title or observable behavior")
        if f.id in f.depends_on:
            problems.append(f"{f.id}: depends on itself")
        if len(set(f.depends_on)) != len(f.depends_on):
            problems.append(f"{f.id}: repeated dependency")
    by_id = {f.id: f for f in features}
    for f in features:
        for dep in f.depends_on:
            if dep not in by_id:
                problems.append(f"{f.id}: unresolved dependency {dep}")
    cycle = find_cycle(by_id)
    if cycle:
        problems.append("dependency cycle: " + " -> ".join(cycle))
    return problems


def parse_roadmap(path: Path = DEFAULT_ROADMAP) -> Roadmap:
    """Parse and validate. Raises RoadmapError listing every problem."""
    data = Path(path).read_bytes()
    features, problems = parse_text(data.decode("utf-8"))
    if not features:
        problems.append("no feature rows found")
    problems += validate(features)
    if problems:
        raise RoadmapError(problems)
    return Roadmap(sha256=hashlib.sha256(data).hexdigest(),
                   features={f.id: f for f in features})


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("roadmap", nargs="?", default=str(DEFAULT_ROADMAP))
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    try:
        roadmap = parse_roadmap(Path(args.roadmap))
    except RoadmapError as exc:
        for p in exc.problems:
            print(f"roadmap: {p}", file=sys.stderr)
        return 1
    if args.json:
        json.dump(roadmap.to_json(), sys.stdout, indent=1)
        print()
        return 0
    by_priority = {p: sum(1 for f in roadmap.features.values() if f.priority == p)
                   for p in PRIORITIES}
    areas: dict[str, int] = {}
    for f in roadmap.features.values():
        areas[f.area] = areas.get(f.area, 0) + 1
    print(f"roadmap sha256 {roadmap.sha256}")
    print(f"{len(roadmap.features)} features; " +
          ", ".join(f"{p}: {n}" for p, n in by_priority.items()))
    print("areas: " + ", ".join(f"{a} {n}" for a, n in areas.items()))
    print("DAG valid: no duplicates, unresolved dependencies or cycles")
    return 0


if __name__ == "__main__":
    sys.exit(main())
