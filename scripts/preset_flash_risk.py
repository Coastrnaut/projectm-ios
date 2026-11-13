#!/usr/bin/env python3
"""Flash risk classifier for Milkdrop preset text (roadmap ACC-002; specs/030-acc-002-reduced-flash-preset-policy,
research ACC-002-D2, ADR-0014).

A deterministic, local, text-only screen: it flags presets whose per-frame equations can make the
whole picture alternate in brightness quickly. It renders nothing and measures nothing; the FX-019
runtime envelope (ADR-0011) still limits every frame. The Swift twin is
Packages/PresetLibrary/Sources/PresetLibrary/PresetFlashRisk.swift. Both must give the same rules
for every fixture in Packages/PresetLibrary/Tests/PresetLibraryTests/FlashFixtures (expected.json);
scripts/test_scripts.py and PresetFlashRiskTests check that.

Rules (ids are reported, in this order):

  toggle-driven   a whole-frame toggle (invert, solarize, brighten, darken) is assigned in a
                  per-frame statement that reads audio (bass, mid, treb, vol, their _att, or a
                  per-frame variable assigned from them) or holds an undamped flicker source
  toggle-flip     a whole-frame toggle is flipped from its own value (invert = 1 - invert)
  luma-flicker    a whole-frame level (gamma, decay, echo_alpha, ob_a, ib_a) is assigned in a
                  per-frame statement holding an undamped flicker source

A flicker source is rand(...), frame % N or fmod(frame, N) with 0 < N <= 20 (3 Hz or faster at
60 fps), or sin/cos whose argument multiplies time by a literal >= 18 (about 2.9 Hz or faster) or
holds frame (bare, or times a literal >= 0.3). A source is damped when it lies inside a term
`c * term` with a literal c < 0.1, or inside if(cond, a, b) with literal a and b less than 0.1
apart: the common "decay = decay - 0.01*equal(frame%5,0)" idiom changes the decay by 1 %.
Statements before the last plain constant assignment of the same target (invert = 0) are dead
and not considered for it.

Only per_frame_N lines are read: per_frame_init, per-pixel code, custom shapes and waves, and
Milkdrop 2 shaders are not (known false negatives, research ACC-002-D2).
"""
from __future__ import annotations

import re

TOGGLES = ("invert", "solarize", "brighten", "darken")
LEVELS = ("gamma", "decay", "echo_alpha", "ob_a", "ib_a")
AUDIO = ("bass", "mid", "treb", "vol", "bass_att", "mid_att", "treb_att", "vol_att")
RULES = ("toggle-driven", "toggle-flip", "luma-flicker")
MAX_FRAME_MODULUS = 20.0
MIN_TIME_RATE = 18.0
MIN_FRAME_RATE = 0.3
DAMPING = 0.1

_NUM = r"(?:\d+\.?\d*|\.\d+)"
_LINE = re.compile(r"^per_frame_(\d+)\s*=(.*)$")
_IDENT = re.compile(r"[a-z_][a-z0-9_]*")
_ASSIGN = re.compile(r"(?<![a-z0-9_])([a-z_][a-z0-9_]*)\s*[-+*/%]?=(?!=)")
_CONSTANT = re.compile(r"^([a-z_][a-z0-9_]*)\s*=\s*-?" + _NUM + r"$")
_RAND = re.compile(r"(?<![a-z0-9_])rand\s*\(")
_MOD = re.compile(r"(?<![a-z0-9_])frame\s*%\s*(" + _NUM + r")")
_FMOD = re.compile(r"(?<![a-z0-9_])fmod\s*\(\s*frame\s*,\s*(" + _NUM + r")\s*\)")
_TRIG = re.compile(r"(?<![a-z0-9_])(?:sin|cos)\s*\(")
_IF = re.compile(r"(?<![a-z0-9_])if\s*\(")
_COEFFICIENT = re.compile(r"(?<![a-z0-9_.])(" + _NUM + r")\s*\*\s*")


def per_frame_code(text: str) -> str:
    """The per_frame_N equations in line-number order, lowercased, comments removed, joined by spaces."""
    lines: list[tuple[int, str]] = []
    for raw in text.splitlines():
        m = _LINE.match(raw.strip().lower())
        if m:
            lines.append((int(m.group(1)), m.group(2).split("//", 1)[0]))
    lines.sort(key=lambda item: item[0])
    return " ".join(body for _, body in lines)


def statements(code: str) -> list[str]:
    """Splits at semicolons outside parentheses; drops empty statements."""
    out: list[str] = []
    depth = 0
    start = 0
    for i, c in enumerate(code):
        if c == "(":
            depth += 1
        elif c == ")":
            depth = max(0, depth - 1)
        elif c == ";" and depth == 0:
            out.append(code[start:i])
            start = i + 1
    out.append(code[start:])
    return [s.strip() for s in out if s.strip()]


def _closing(s: str, open_index: int) -> int:
    """Index of the parenthesis closing the one at open_index (len(s) - 1 when unbalanced)."""
    depth = 0
    for i in range(open_index, len(s)):
        if s[i] == "(":
            depth += 1
        elif s[i] == ")":
            depth -= 1
            if depth == 0:
                return i
    return len(s) - 1


def _arguments(s: str, open_index: int) -> list[str]:
    """The top-level comma-separated arguments of the call whose '(' is at open_index."""
    end = _closing(s, open_index)
    args: list[str] = []
    depth = 0
    start = open_index + 1
    for i in range(open_index + 1, end):
        if s[i] == "(":
            depth += 1
        elif s[i] == ")":
            depth -= 1
        elif s[i] == "," and depth == 0:
            args.append(s[start:i].strip())
            start = i + 1
    args.append(s[start:end].strip())
    return args


def _rate(arg: str, word: str) -> float | None:
    """The largest K in `word*K` or `K*word` inside arg (1 for a bare word); None when word is absent."""
    best: float | None = None
    for m in re.finditer(r"(?<![a-z0-9_.])" + word + r"(?![a-z0-9_])", arg):
        after = re.match(r"\s*\*\s*(" + _NUM + r")", arg[m.end():])
        before = re.search(r"(" + _NUM + r")\s*\*\s*$", arg[:m.start()])
        k = float(after.group(1)) if after else float(before.group(1)) if before else 1.0
        best = k if best is None else max(best, k)
    return best


def flicker_spans(stmt: str) -> list[tuple[int, int]]:
    """Character spans [start, end) of the flicker sources in a statement."""
    spans: list[tuple[int, int]] = []
    for m in _RAND.finditer(stmt):
        spans.append((m.start(), _closing(stmt, m.end() - 1) + 1))
    for pattern in (_MOD, _FMOD):
        for m in pattern.finditer(stmt):
            if 0 < float(m.group(1)) <= MAX_FRAME_MODULUS:
                spans.append((m.start(), m.end()))
    for m in _TRIG.finditer(stmt):
        end = _closing(stmt, m.end() - 1)
        arg = stmt[m.end():end]
        time_rate = _rate(arg, "time")
        frame_rate = _rate(arg, "frame")
        if (time_rate is not None and time_rate >= MIN_TIME_RATE) or (frame_rate is not None and frame_rate >= MIN_FRAME_RATE):
            spans.append((m.start(), end + 1))
    return spans


def damped_spans(stmt: str) -> list[tuple[int, int]]:
    """Spans of `c * term` (literal c < DAMPING; term a call, a parenthesized group or a name) and of
    if(cond, a, b) calls with literal a and b less than DAMPING apart."""
    spans: list[tuple[int, int]] = []
    for m in _COEFFICIENT.finditer(stmt):
        if float(m.group(1)) >= DAMPING:
            continue
        i = m.end()
        name = _IDENT.match(stmt, i)
        if name:
            k = name.end()
            while k < len(stmt) and stmt[k] == " ":
                k += 1
            end = _closing(stmt, k) + 1 if k < len(stmt) and stmt[k] == "(" else name.end()
        elif i < len(stmt) and stmt[i] == "(":
            end = _closing(stmt, i) + 1
        else:
            continue
        spans.append((m.start(), end))
    for m in _IF.finditer(stmt):
        args = _arguments(stmt, m.end() - 1)
        if len(args) == 3 and all(re.fullmatch(r"-?" + _NUM, a) for a in args[1:]) \
                and abs(float(args[1]) - float(args[2])) < DAMPING:
            spans.append((m.start(), _closing(stmt, m.end() - 1) + 1))
    return spans


def undamped_flicker(stmt: str) -> bool:
    """Whether the statement holds a flicker source outside every damped span."""
    damped = damped_spans(stmt)
    return any(not any(d0 <= s0 and s1 <= d1 for d0, d1 in damped) for s0, s1 in flicker_spans(stmt))


def _targets(stmt: str) -> set[str]:
    return {m.group(1) for m in _ASSIGN.finditer(stmt)}


def classify(text: str) -> list[str]:
    """The rule ids that flag this preset text, in RULES order; empty when none does."""
    stmts = statements(per_frame_code(text))
    audio_vars = set(AUDIO)
    changed = True
    while changed:   # per-frame variables assigned from audio read audio too (fixed point)
        changed = False
        for stmt in stmts:
            if set(_IDENT.findall(stmt)) & audio_vars:
                new = _targets(stmt) - audio_vars
                if new:
                    audio_vars |= new
                    changed = True
    live_from: dict[str, int] = {}   # target -> index of its last plain constant assignment
    for index, stmt in enumerate(stmts):
        m = _CONSTANT.match(stmt)
        if m:
            live_from[m.group(1)] = index
    hits: set[str] = set()
    for index, stmt in enumerate(stmts):
        assigned = _targets(stmt)
        targets = {t for t in assigned if index >= live_from.get(t, -1)}
        flicker = undamped_flicker(stmt)
        toggles = targets & set(TOGGLES)
        if toggles:
            reads = set(_IDENT.findall(stmt)) - assigned - set(TOGGLES)
            if flicker or reads & audio_vars:
                hits.add("toggle-driven")
            for toggle in toggles:
                if re.search(r"(?<![a-z0-9_.])1\s*-\s*" + toggle + r"(?![a-z0-9_])|bnot\s*\(\s*" + toggle + r"\s*\)", stmt):
                    hits.add("toggle-flip")
        if targets & set(LEVELS) and flicker:
            hits.add("luma-flicker")
    return [rule for rule in RULES if rule in hits]


def may_flash(text: str) -> bool:
    return bool(classify(text))
