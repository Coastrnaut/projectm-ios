#!/usr/bin/env python3
"""Recompute reference-tone golden hashes with an independent Python port (AUD-016).

The Swift generator (Packages/AudioCore/Sources/AudioCore/ReferenceTones/) builds every sample from
correctly rounded IEEE 754 arithmetic and its own polynomials (research AUD-016-D1). CPython's float
operations are the same IEEE operations, so this port of the same formulas must reproduce the
golden SHA-256 values in Packages/AudioCore/Tests/AudioCoreTests/ReferenceToneGoldens.swift bit for
bit. A match is evidence that the goldens depend only on the arithmetic, not on Swift, the platform
math library or the host.

Checks the mono variants of sine-1k, sine-100, sine-1500, sweep-log, sweep-linear, pulse-120,
pulse-120-accent, pulse-132 and silence at 44.1 and 48 kHz (18 hashes; about a minute).
Standard library only. Exit 0 when every hash matches.
"""
from __future__ import annotations

import hashlib
import math
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GOLDENS = ROOT / "Packages" / "AudioCore" / "Tests" / "AudioCoreTests" / "ReferenceToneGoldens.swift"

HALF_PI = 1.5707963267948966
SIN = [-1 / 6, 1 / 120, -1 / 5040, 1 / 362880, -1 / 39916800, 1 / 6227020800, -1 / 1307674368000, 1 / 355687428096000]
COS = [-1 / 2, 1 / 24, -1 / 720, 1 / 40320, -1 / 3628800, 1 / 479001600, -1 / 87178291200, 1 / 20922789888000]
LN2_HI, LN2_LO, INV_LN2 = 6.93147180369123816490e-01, 1.90821492927058770002e-10, 1.44269504088896338700e+00


def sin_poly(x: float) -> float:
    x2 = x * x
    p = SIN[6] + x2 * SIN[7]
    q = SIN[4] + x2 * (SIN[5] + x2 * p)
    r = SIN[2] + x2 * (SIN[3] + x2 * q)
    t = SIN[0] + x2 * (SIN[1] + x2 * r)
    return x + x * (x2 * t)


def cos_poly(x: float) -> float:
    x2 = x * x
    p = COS[6] + x2 * COS[7]
    q = COS[4] + x2 * (COS[5] + x2 * p)
    r = COS[2] + x2 * (COS[3] + x2 * q)
    t = COS[0] + x2 * (COS[1] + x2 * r)
    return 1 + x2 * t


def quarter(u: float) -> float:
    return sin_poly(u * HALF_PI) if u <= 0.5 else cos_poly((1 - u) * HALF_PI)


def sin2pi(cycles: float) -> float:
    c = cycles - math.floor(cycles)
    q4 = c * 4
    quadrant = math.floor(q4)
    r = q4 - quadrant
    return (quarter(r), quarter(1 - r), -quarter(r), -quarter(1 - r))[int(quadrant)]


def round_away(x: float) -> float:
    return math.copysign(math.floor(abs(x) + 0.5), x)


def exp(x: float) -> float:
    k = round_away(x * INV_LN2)
    r = (x - k * LN2_HI) - k * LN2_LO
    p = 1 / 6227020800
    for d in (479001600, 39916800, 3628800, 362880, 40320, 5040, 720, 120, 24, 6):
        p = 1 / d + r * p
    p = 0.5 + r * p
    p = 1.0 + r * p
    p = 1.0 + r * p
    return math.ldexp(p, int(k))


def log(x: float) -> float:
    m, e = math.frexp(x)
    m, e = m * 2, e - 1
    if m > 1.4142135623730951:
        m, e = m * 0.5, e + 1
    s = (m - 1) / (m + 1)
    s2 = s * s
    total, j = 1 / 27, 25.0
    while j >= 1:
        total = 1 / j + s2 * total
        j -= 2
    return e * LN2_HI + (e * LN2_LO + 2 * s * total)


def sine(frequency: float, rate: int, frames: int) -> list[float]:
    return [0.25 * sin2pi(math.fmod(n * frequency, rate) / rate) for n in range(frames)]


def sweep(curve: str, rate: int, frames: int) -> list[float]:
    d = float(frames)
    if curve == "linear":
        slope = (20000.0 - 20.0) / (2 * d)
        return [0.25 * sin2pi((20.0 * n + slope * n * n) / rate) for n in range(frames)]
    ln_ratio = log(20000.0 / 20.0)
    growth, scale = ln_ratio / d, 20.0 * d / (rate * ln_ratio)
    return [0.25 * sin2pi(scale * (exp(growth * n) - 1)) for n in range(frames)]


def pulses(bpm: float, accents: list[float], rate: int, frames: int) -> list[float]:
    per_beat, width = 60 * rate / bpm, round_away(0.002 * rate)
    out = [0.0] * frames
    beat = 0
    while (onset := int(round_away(beat * per_beat))) < frames:
        for i in range(onset, min(frames, onset + int(width))):
            out[i] = 0.5 * accents[beat % len(accents)]
        beat += 1
    return out


def digest(samples: list[float]) -> str:
    return hashlib.sha256(struct.pack(f"<{len(samples)}f", *samples)).hexdigest()


def main() -> int:
    goldens = dict(re.findall(r'"([^"]+)": "([0-9a-f]{64})"', GOLDENS.read_text(encoding="utf-8")))
    failures = 0
    for rate in (44_100, 48_000):
        frames = rate * 10
        variants = {
            "sine-1k": lambda: sine(1000.0, rate, frames),
            "sine-100": lambda: sine(100.0, rate, frames),
            "sine-1500": lambda: sine(1500.0, rate, frames),
            "sweep-log": lambda: sweep("log", rate, frames),
            "sweep-linear": lambda: sweep("linear", rate, frames),
            "pulse-120": lambda: pulses(120, [1], rate, frames),
            "pulse-120-accent": lambda: pulses(120, [1, 0.5, 0.5, 0.5], rate, frames),
            "pulse-132": lambda: pulses(132, [1], rate, frames),
            "silence": lambda: [0.0] * frames,
        }
        for fixture, make in variants.items():
            key = f"{fixture}@{rate}/1"
            ok = digest(make()) == goldens.get(key)
            failures += not ok
            print(f"{'OK  ' if ok else 'FAIL'} {key}")
    print("check_reference_tone_goldens:", "OK" if failures == 0 else f"{failures} mismatch(es)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
