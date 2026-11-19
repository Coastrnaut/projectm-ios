#!/usr/bin/env python3
"""QA-011 media fixtures for the device tests: pictures, videos, audio formats and presets, made on the Mac.

Generated, deterministic content (patterns, a fixed-seed noise, the music fixture's synthetic track), so nothing
needs a licence. Pictures and videos come from Apple's encoders (scripts/fixtures/make_media.swift: ImageIO and
AVFoundation, compiled once with `swiftc -O`); audio formats from `afconvert` (Apple's encoders); the rest in Python.
Output goes to Build/fixtures/media/ (gitignored); `python3 scripts/install_test_fixtures.py --media` copies it into
the app's Documents on D1-D3, where the Debug device-test host also shows it in Files (DeviceTests.yml).

    python3 scripts/make_media_fixtures.py                  # everything missing
    python3 scripts/make_media_fixtures.py --only photo-gps.heic not-audio.mp3
    python3 scripts/make_media_fixtures.py --list           # names and what each is for
    python3 scripts/make_media_fixtures.py --force          # remake existing files

MP3 (CBR and VBR) is not made: the Mac has no MP3 encoder (no lame or ffmpeg); those stay the owner's files unless
the owner approves installing one. The hard-left and phase-inverted tracks come from make_music_fixture.py.
"""
from __future__ import annotations

import argparse
import math
import shutil
import struct
import subprocess
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Build" / "fixtures" / "media"
SWIFT_SOURCE = ROOT / "scripts" / "fixtures" / "make_media.swift"
SWIFT_BINARY = ROOT / "Build" / "fixtures" / "make_media"
PRESET_SIZE = 524_288   # PRE-012's static file limit (512 KiB)

# name -> (maker, what it is for). Makers: "swift" (make_media.swift), "audio" (afconvert), "python".
CATALOG: dict[str, tuple[str, str]] = {
    "photo-gps.heic": ("swift", "HEIC with GPS and a capture date (location stripped on import)"),
    "panorama-60mp.png": ("swift", "15000 x 4000 PNG (60 MP: downsampled on import)"),
    "panorama-60mp.heic": ("swift", "15000 x 4000 HEIC (60 MP)"),
    "photo-45mb.jpg": ("swift", "a JPEG of at least 45 MB (bounded read)"),
    "photo-small.jpg": ("swift", "a small JPEG (source of not-a-preset.milk)"),
    "photo-transparent.png": ("swift", "PNG with an alpha gradient"),
    "animated-200.gif": ("swift", "a 200-frame animated GIF (160 x 120)"),
    "video-h264-1080p.mp4": ("swift", "H.264 1920 x 1080, 30 fps, 10 s"),
    "video-hevc-4k60.mov": ("swift", "HEVC 3840 x 2160, 60 fps, 10 s"),
    "video-hevc-360p-10min.mov": ("swift", "HEVC 640 x 360, 30 fps, 10 minutes"),
    "video-hdr-hlg.mov": ("swift", "HEVC Main10, HLG, BT.2020, 1920 x 1080, 5 s"),
    "audio-music.wav": ("audio", "the music fixture as 16-bit WAV"),
    "audio-music.aiff": ("audio", "the music fixture as AIFF"),
    "audio-aac.aac": ("audio", "AAC in ADTS (.aac)"),
    "audio-aac.m4a": ("audio", "AAC in M4A"),
    "audio-alac.m4a": ("audio", "Apple Lossless in M4A"),
    "audio-10mb.m4a": ("audio", "an M4A of at least 10 MB (5.5 min AAC 256 kbit/s)"),
    "audio-60min.m4a": ("audio", "a 60-minute M4A (mono AAC 64 kbit/s)"),
    "audio-damaged.m4a": ("audio", "an AAC M4A whose moov atom (index) is cut or zeroed (unreadable)"),
    "click-120bpm.m4a": ("audio", "a 120 BPM click track, 30 s (accent every 4th beat)"),
    "not-audio.mp3": ("python", "a PDF named .mp3 (refused by content, not name)"),
    "not-a-preset.milk": ("python", "a JPEG named .milk"),
    "preset-512k.milk": ("python", "a valid preset of exactly 524,288 bytes (the size limit)"),
    "preset-strobe.milk": ("python", "a preset that inverts every frame (the flash classifier flags it)"),
    # QA-011 Batch 5 (media layers, files and presets).
    "preset-small.milk": ("python", "a small valid preset (a second import for PRE-012 and PRE-014)"),
    "slide-1.png": ("swift", "640 x 480 red checkerboard (slideshow and Ken Burns slide 1)"),
    "slide-2.png": ("swift", "640 x 480 green checkerboard (slide 2)"),
    "slide-3.png": ("swift", "640 x 480 blue checkerboard (slide 3)"),
    "slide-4.png": ("swift", "640 x 480 yellow checkerboard (slide 4)"),
    "slide-5.png": ("swift", "640 x 480 magenta checkerboard (slide 5)"),
    "logo-white-disc.png": ("swift", "512 x 512 white disc on transparency, anti-aliased edge (logo fringe check)"),
}


# MARK: Python-made files

def pdf_bytes() -> bytes:
    """A minimal one-page PDF (valid xref offsets)."""
    objects = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
               b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>"]
    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for n, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % n + body + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
    for off in offsets:
        out += b"%010d 00000 n \n" % off
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref)
    return bytes(out)


PRESET_HEAD = ("[preset00]\n// QA-011 fixture (scripts/make_media_fixtures.py)\nfdecay=0.98\nnWaveMode=6\nfWaveScale=1\n"
               "wave_r=1.0\nwave_g=0.6\nwave_b=0.2\nwave_x=0.5\nwave_y=0.5\n")


def preset_of_size(size: int = PRESET_SIZE) -> bytes:
    """A valid preset padded with comment lines to exactly `size` bytes."""
    body = PRESET_HEAD.encode()
    pad = size - len(body)
    if pad < 0:
        raise ValueError("size smaller than the preset header")
    line = b"// " + b"x" * 76 + b"\n"   # 80 bytes per comment line
    out = body + line * (pad // len(line))
    rest = size - len(out)
    if rest:
        out += (b"//" + b"x" * (rest - 3) + b"\n") if rest >= 3 else b"\n" * rest
    assert len(out) == size
    return out


def small_preset() -> str:
    """A small valid preset with its own wave colour (a second, distinct import)."""
    return PRESET_HEAD.replace("wave_r=1.0\nwave_g=0.6\nwave_b=0.2", "wave_r=0.2\nwave_g=0.8\nwave_b=1.0")


def strobe_preset() -> str:
    """Inverts the whole picture every frame: preset_flash_risk.py's toggle-flip and toggle rules."""
    return PRESET_HEAD + "per_frame_1=invert = 1 - invert;\nper_frame_2=brighten = frame % 2;\n"


# MARK: Audio

def click_track(path: Path, seconds: int = 30, bpm: int = 120, rate: int = 44_100) -> None:
    """Mono 16-bit WAV: a 10 ms 1 kHz click on every beat, the first of every four louder."""
    beat = 60.0 / bpm
    frames = bytearray()
    for i in range(seconds * rate):
        t = i / rate
        n = int(t / beat)
        within = t - n * beat
        value = 0.0
        if within < 0.010:
            value = (0.9 if n % 4 == 0 else 0.5) * math.sin(2 * math.pi * 1000 * within)
        frames += struct.pack("<h", int(value * 32_000))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(frames))


def damage_m4a(data: bytes) -> bytes:
    """Damages an MP4/M4A file's top-level `moov` atom (its index) so no player can read the audio: cut inside it
    when it is the last atom, otherwise (afconvert writes it before `mdat`) zero everything after its first 16
    bytes, keeping the file's size and its audio data."""
    offset = 0
    while offset + 8 <= len(data):
        size, kind = struct.unpack(">I4s", data[offset:offset + 8])
        if size == 1 and offset + 16 <= len(data):
            size = struct.unpack(">Q", data[offset + 8:offset + 16])[0]
        elif size == 0:
            size = len(data) - offset
        if kind == b"moov":
            end = offset + size
            if end >= len(data):
                return data[:offset + 16]
            return data[:offset + 16] + bytes(size - 16) + data[end:]
        if size < 8:
            break
        offset += size
    raise ValueError("no moov atom")


def music_wav(path: Path, repeat: int = 1, mono_half_rate: bool = False) -> None:
    """The music fixture's 60 s synthetic track, repeated; `mono_half_rate`: mono at 22.05 kHz (small temp files)."""
    sys.path.insert(0, str(ROOT / "scripts"))
    import make_music_fixture as mmf
    left, right = mmf.synthesize()
    with wave.open(str(path), "wb") as w:
        w.setsampwidth(2)
        if mono_half_rate:
            w.setnchannels(1)
            w.setframerate(mmf.RATE // 2)
            block = b"".join(struct.pack("<h", int((left[i] + right[i]) * 16_000)) for i in range(0, len(left), 2))
        else:
            w.setnchannels(2)
            w.setframerate(mmf.RATE)
            block = b"".join(struct.pack("<hh", int(a * 32_000), int(b * 32_000)) for a, b in zip(left, right))
        for _ in range(repeat):
            w.writeframes(block)


def afconvert(source: Path, target: Path, *options: str) -> None:
    subprocess.run(["afconvert", *options, str(source), str(target)], check=True, capture_output=True)


def make_audio(name: str, out: Path, scratch: Path) -> None:
    base = scratch / "music.wav"
    if not base.exists():
        music_wav(base)
    target = out / name
    if name == "audio-music.wav":
        shutil.copyfile(base, target)
    elif name == "audio-music.aiff":
        afconvert(base, target, "-f", "AIFF", "-d", "BEI16")
    elif name == "audio-aac.aac":
        afconvert(base, target, "-f", "adts", "-d", "aac", "-b", "192000")
    elif name == "audio-aac.m4a":
        afconvert(base, target, "-f", "m4af", "-d", "aac", "-b", "192000")
    elif name == "audio-alac.m4a":
        afconvert(base, target, "-f", "m4af", "-d", "alac")
    elif name == "audio-10mb.m4a":
        long = scratch / "music-330s.wav"
        music_wav(long, repeat=6)   # 6 min
        afconvert(long, target, "-f", "m4af", "-d", "aac", "-b", "256000")
        long.unlink()
    elif name == "audio-60min.m4a":
        long = scratch / "music-60min.wav"
        music_wav(long, repeat=60, mono_half_rate=True)
        afconvert(long, target, "-f", "m4af", "-d", "aac", "-b", "64000")
        long.unlink()
    elif name == "audio-damaged.m4a":
        whole = scratch / "whole.m4a"
        afconvert(base, whole, "-f", "m4af", "-d", "aac", "-b", "192000")
        target.write_bytes(damage_m4a(whole.read_bytes()))
    elif name == "click-120bpm.m4a":
        wav = scratch / "click.wav"
        click_track(wav)
        afconvert(wav, target, "-f", "m4af", "-d", "aac", "-b", "192000")
    else:
        raise ValueError(name)


# MARK: Swift-made files

def swift_binary() -> Path:
    """make_media.swift compiled with -O (a 60 MP pattern takes minutes in the interpreter), rebuilt when newer."""
    if not SWIFT_BINARY.exists() or SWIFT_BINARY.stat().st_mtime < SWIFT_SOURCE.stat().st_mtime:
        SWIFT_BINARY.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["xcrun", "swiftc", "-O", "-suppress-warnings", str(SWIFT_SOURCE), "-o", str(SWIFT_BINARY)], check=True)
    return SWIFT_BINARY


def make(names: list[str], out: Path = OUT, force: bool = False) -> int:
    out.mkdir(parents=True, exist_ok=True)
    scratch = out.parent / "media-scratch"
    scratch.mkdir(parents=True, exist_ok=True)
    wanted = [n for n in names if force or not (out / n).exists()]
    status = 0
    swift = [n for n in wanted if CATALOG[n][0] == "swift"]
    if "not-a-preset.milk" in wanted and not (out / "photo-small.jpg").exists() and "photo-small.jpg" not in swift:
        swift.append("photo-small.jpg")
    if swift:
        result = subprocess.run([str(swift_binary()), str(out), *swift])
        status |= result.returncode
    for name in wanted:
        maker = CATALOG[name][0]
        try:
            if maker == "audio":
                make_audio(name, out, scratch)
            elif name == "not-audio.mp3":
                (out / name).write_bytes(pdf_bytes())
            elif name == "not-a-preset.milk":
                shutil.copyfile(out / "photo-small.jpg", out / name)
            elif name == "preset-512k.milk":
                (out / name).write_bytes(preset_of_size())
            elif name == "preset-small.milk":
                (out / name).write_text(small_preset(), encoding="utf-8")
            elif name == "preset-strobe.milk":
                (out / name).write_text(strobe_preset(), encoding="utf-8")
            else:
                continue
            print(f"make_media_fixtures: {name} {(out / name).stat().st_size}")
        except (OSError, subprocess.CalledProcessError, ValueError) as error:
            print(f"make_media_fixtures: {name} FAILED: {error}")
            status = 1
    shutil.rmtree(scratch, ignore_errors=True)
    return status


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--only", nargs="+", choices=sorted(CATALOG), help="make only these")
    p.add_argument("--force", action="store_true", help="remake files that exist")
    p.add_argument("--list", action="store_true", help="list the fixtures")
    p.add_argument("--out", type=Path, default=OUT)
    args = p.parse_args(argv)
    if args.list:
        for name, (maker, what) in CATALOG.items():
            print(f"{name:28} {maker:6} {what}")
        return 0
    if sys.platform != "darwin":
        print("make_media_fixtures: needs macOS (ImageIO, AVFoundation, afconvert)")
        return 1
    return make(args.only or list(CATALOG), args.out, args.force)


if __name__ == "__main__":
    raise SystemExit(main())
