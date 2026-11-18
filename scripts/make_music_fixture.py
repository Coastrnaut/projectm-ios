#!/usr/bin/env python3
"""QA-011 device acceptance: a deterministic 60 s synthetic music track for the owner-session automation.

The bundled reference track is a test signal (tones with a silent gap), so visuals that follow music barely move
on it. This writes music-like audio instead: 120 BPM kick, snare and hi-hats, a bass line and chord pads, in
stereo, with a quiet intro, a loud chorus, a breakdown and a loud ending, so beats, onsets, sections and stereo
all have something to follow. Generated, not recorded: no licence. Output: a 44.1 kHz stereo WAV, converted to
AAC (.m4a) with `afconvert` when it is available (macOS).

    python3 scripts/make_music_fixture.py [--out Build/fixtures/music-fixture.m4a] [--variant left|inverted]

Variants for the stereo device tests (QA-011 B05): `left` keeps the music in the left channel only (the right is
silent: AUD-009 channel selection); `inverted` makes the right channel the negated left (a phase-inverted feed:
ANL-013 stereo correlation reads a negative r).

MP3 for AUD-002-T25 (owner approved Homebrew `lame`, 2026-11-18): `--mp3 cbr` writes music-fixture-cbr.mp3 (constant
192 kbit/s), `--mp3 vbr` writes music-fixture-vbr.mp3 (variable, `-V 2`, with an ID3v2 tag and a generated PNG cover).
The music fixture is decoded to WAV with `afconvert` first (generated when missing), then encoded by `lame`.
"""
from __future__ import annotations

import argparse
import math
import shutil
import struct
import subprocess
import wave
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RATE = 44_100
SECONDS = 60
BPM = 120


def synthesize(seconds: int = SECONDS, rate: int = RATE) -> tuple[list[float], list[float]]:
    n = seconds * rate
    left = [0.0] * n
    right = [0.0] * n
    beat = 60.0 / BPM
    seed = 0x2545F491

    def noise() -> float:
        nonlocal seed
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        return seed / 0x3FFFFFFF - 1.0

    def section_gain(t: float) -> tuple[float, bool]:
        """(level, drums on): quiet intro, loud chorus, breakdown, loud ending."""
        if t < 10:
            return 0.25, False
        if t < 20:
            return 0.55, True
        if t < 40:
            return 1.0, True
        if t < 50:
            return 0.45, False
        return 1.0, True

    roots = [55.0, 43.65, 49.0, 41.2]           # A1, F1, G1, E1 (one bar each)
    chords = [(220.0, 261.63, 329.63), (174.61, 220.0, 261.63), (196.0, 246.94, 293.66), (164.81, 207.65, 246.94)]
    for i in range(n):
        t = i / rate
        level, drums = section_gain(t)
        bar = int(t / (4 * beat)) % 4
        in_beat = t % beat
        step = int(t / beat)
        sample_l = sample_r = 0.0
        # Pads (stereo spread) and bass.
        for k, f in enumerate(chords[bar]):
            pad = 0.06 * math.sin(2 * math.pi * f * t + k)
            sample_l += pad * (1.0 if k != 2 else 0.4)
            sample_r += pad * (1.0 if k != 0 else 0.4)
        bass = 0.22 * math.sin(2 * math.pi * roots[bar] * t) * (1.0 - min(in_beat / beat, 1.0) * 0.6)
        sample_l += bass
        sample_r += bass
        if drums:
            # Kick on every beat: a fast downward sweep.
            if in_beat < 0.25:
                env = math.exp(-in_beat * 18)
                kick = 0.9 * env * math.sin(2 * math.pi * (50 + 120 * math.exp(-in_beat * 40)) * in_beat)
                sample_l += kick
                sample_r += kick
            # Snare on beats 2 and 4.
            if step % 2 == 1 and in_beat < 0.18:
                sn = 0.35 * math.exp(-in_beat * 25) * noise()
                sample_l += sn
                sample_r += sn
            # Hi-hats on eighths, panned right.
            eighth = t % (beat / 2)
            if eighth < 0.04:
                hat = 0.12 * math.exp(-eighth * 90) * noise()
                sample_l += hat * 0.4
                sample_r += hat
        left[i] = max(-1.0, min(1.0, sample_l * level))
        right[i] = max(-1.0, min(1.0, sample_r * level))
    return left, right


def write_wav(path: Path, left: list[float], right: list[float], rate: int = RATE) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(rate)
        frames = bytearray()
        for a, b in zip(left, right):
            frames += struct.pack("<hh", int(a * 32_000), int(b * 32_000))
        w.writeframes(bytes(frames))


def cover_png(path: Path, size: int = 64) -> None:
    """A small generated cover image (a colour gradient) for the VBR file's ID3 artwork."""
    rows = b"".join(b"\x00" + bytes(c for x in range(size) for c in (x * 4 % 256, y * 4 % 256, 160)) for y in range(size))
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def make_mp3(kind: str, out: Path | None) -> int:
    """AUD-002-T25: the music fixture as MP3 from a real encoder (`lame`), constant or variable bit rate."""
    lame = shutil.which("lame") or ("/opt/homebrew/bin/lame" if Path("/opt/homebrew/bin/lame").exists() else None)
    if lame is None:
        print("make_music_fixture: lame not found (brew install lame)")
        return 1
    fixtures = ROOT / "Build" / "fixtures"
    out = out or fixtures / f"music-fixture-{kind}.mp3"
    m4a = fixtures / "music-fixture.m4a"
    if not m4a.exists():
        main(["--out", str(m4a)])
    wav = fixtures / "music-fixture-decoded.wav"
    if m4a.exists() and shutil.which("afconvert"):
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16", str(m4a), str(wav)], check=True)
    else:
        left, right = synthesize()
        write_wav(wav, left, right)
    command = [lame, "--quiet"]
    if kind == "cbr":
        command += ["-b", "192"]
    else:
        cover = fixtures / "music-fixture-cover.png"
        cover_png(cover)
        command += ["-V", "2", "--add-id3v2", "--tt", "Music fixture VBR", "--ta", "projectM-iOS tests", "--ti", str(cover)]
    subprocess.run(command + [str(wav), str(out)], check=True)
    print(f"make_music_fixture: {out} ({out.stat().st_size} bytes)")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--out", default=None)
    p.add_argument("--variant", choices=["normal", "left", "inverted"], default="normal")
    p.add_argument("--mp3", choices=["cbr", "vbr"], default=None, help="write the MP3 fixture instead (needs lame)")
    args = p.parse_args(argv)
    if args.mp3:
        return make_mp3(args.mp3, Path(args.out) if args.out else None)
    name = "music-fixture" if args.variant == "normal" else f"music-fixture-{args.variant}"
    out = Path(args.out) if args.out else ROOT / "Build" / "fixtures" / f"{name}.m4a"
    wav = out.with_suffix(".wav")
    left, right = synthesize()
    if args.variant == "left":
        mono = [(a + b) / 2 for a, b in zip(left, right)]
        left, right = mono, [0.0] * len(mono)
    elif args.variant == "inverted":
        mono = [(a + b) / 2 for a, b in zip(left, right)]
        left, right = mono, [-x for x in mono]
    write_wav(wav, left, right)
    if out.suffix == ".m4a" and shutil.which("afconvert"):
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "192000", str(wav), str(out)], check=True)
        print(f"make_music_fixture: {out} ({out.stat().st_size} bytes)")
    else:
        print(f"make_music_fixture: {wav} ({wav.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
