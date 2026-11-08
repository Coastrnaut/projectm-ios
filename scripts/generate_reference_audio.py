#!/usr/bin/env python3
"""Generate the deterministic In-App Playback reference track (task T044, FR-006, SC-006).

Output (byte-identical on every run; no randomness, no timestamps in the file):
  Apps/CaptureLab/Resources/reference.wav         60 s, 44,100 Hz, stereo, 16-bit PCM
  Apps/CaptureLab/Resources/reference-clicks.json click times used to measure SC-006

Timeline:
  0–10 s   tones: left 1 kHz, right 440 Hz, both at −12 dBFS (level-meter sanity)
  10–20 s  digital silence (exercises "Audio received — silent")
  20–40 s  beat pattern at 120 BPM: decaying 60 Hz kick on every beat, hi-hat tick on off-beats
  40–60 s  sharp clicks: a 2 ms full-scale burst once per second (impulses for SC-006)

The track is generated in-house, so the project owns all rights (research R-09).
"""
from __future__ import annotations

import argparse
import json
import math
import struct
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = ROOT / "Apps" / "CaptureLab" / "Resources"
RATE = 44_100
SECONDS = 60
FULL = 32767


def db_to_amp(db: float) -> float:
    return 10 ** (db / 20)


def sample(t: float) -> tuple[float, float]:
    if t < 10:
        a = db_to_amp(-12)
        return a * math.sin(2 * math.pi * 1000 * t), a * math.sin(2 * math.pi * 440 * t)
    if t < 20:
        return 0.0, 0.0
    if t < 40:
        beat = 0.5  # 120 BPM
        phase = (t - 20) % beat
        kick = 0.8 * math.exp(-phase * 18) * math.sin(2 * math.pi * 60 * phase)
        off = (t - 20 - beat / 2) % beat
        hat = 0.0
        if off < 0.01:
            # deterministic "noise": a fixed high-frequency chord instead of random samples
            hat = 0.25 * math.exp(-off * 400) * (math.sin(2 * math.pi * 7000 * t) + math.sin(2 * math.pi * 9100 * t)) / 2
        v = kick + hat
        return v, v
    phase = (t - 40) % 1.0
    v = 0.99 if phase < 0.002 else 0.0
    return v, v


def click_times() -> list[float]:
    return [40.0 + i for i in range(20)]


def render() -> bytes:
    frames = bytearray()
    pack = struct.Struct("<hh").pack
    for n in range(RATE * SECONDS):
        left, right = sample(n / RATE)
        frames += pack(round(max(-1.0, min(1.0, left)) * FULL), round(max(-1.0, min(1.0, right)) * FULL))
    return bytes(frames)


def write(out_dir: Path) -> tuple[Path, Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    wav_path = out_dir / "reference.wav"
    with wave.open(str(wav_path), "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(render())
    json_path = out_dir / "reference-clicks.json"
    json_path.write_text(json.dumps({
        "sampleRate": RATE,
        "durationSeconds": SECONDS,
        "clickDurationSeconds": 0.002,
        "clickTimesSeconds": click_times(),
        "segments": [
            {"start": 0, "end": 10, "content": "tones L 1 kHz / R 440 Hz at -12 dBFS"},
            {"start": 10, "end": 20, "content": "digital silence"},
            {"start": 20, "end": 40, "content": "120 BPM beat pattern"},
            {"start": 40, "end": 60, "content": "2 ms full-scale clicks once per second"},
        ],
    }, indent=2) + "\n", encoding="utf-8", newline="\n")
    return wav_path, json_path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate the reference track")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args(argv)
    wav_path, json_path = write(args.out)
    print(f"wrote {wav_path} and {json_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
