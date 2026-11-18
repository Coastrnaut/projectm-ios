"""Sound from the Mac's speaker for microphone device tests: `audio.play`, `audio.tone`, `audio.stop`.

    MAC-DO {"action": "audio.play", "file": "Build/fixtures/music-fixture.m4a", "seconds": 20, "volume": 0.8}
    MAC-DO {"action": "audio.tone", "hz": 440, "seconds": 5}
    MAC-DO {"action": "audio.stop"}

Paths are relative to the repository and must stay inside it. `afplay` (macOS) plays in the background; a new play
stops the previous one.
"""
from __future__ import annotations

import math
import struct
import tempfile
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def tone_wav(path: Path, hz: float, seconds: float, rate: int = 44_100, level: float = 0.5) -> Path:
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", int(level * 32_000 * math.sin(2 * math.pi * hz * i / rate)))
                               for i in range(int(seconds * rate))))
    return path


def afplay(path: Path, request: dict) -> list[str]:
    cmd = ["afplay", str(path)]
    if "seconds" in request:
        cmd += ["-t", str(float(request["seconds"]))]
    if "volume" in request:
        cmd += ["-v", str(float(request["volume"]))]
    return cmd


def fixture_path(name: str) -> Path:
    path = (ROOT / name).resolve()
    if ROOT.resolve() not in path.parents or not path.is_file():
        raise ValueError(f"no such fixture in the repository: {name}")
    return path


def play(request: dict, context) -> str:
    path = fixture_path(str(request.get("file", "Build/fixtures/music-fixture.m4a")))
    context.start("audio", afplay(path, request))
    return f"playing {path.name}"


def tone(request: dict, context) -> str:
    hz, seconds = float(request.get("hz", 440)), float(request.get("seconds", 5))
    path = tone_wav(Path(tempfile.gettempdir()) / f"mac-driver-tone-{int(hz)}.wav", hz, seconds)
    context.start("audio", afplay(path, {k: v for k, v in request.items() if k == "volume"}))
    return f"tone {hz:g} Hz for {seconds:g} s"


def stop(request: dict, context) -> str:
    return "stopped" if context.stop("audio") else "nothing playing"


ACTIONS = {"play": play, "tone": tone, "stop": stop}
