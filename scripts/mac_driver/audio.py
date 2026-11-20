"""Sound from the Mac's speaker for microphone device tests: `audio.play`, `audio.tone`, `audio.stop`.

    MAC-DO {"action": "audio.play", "file": "Build/fixtures/music-fixture.m4a", "seconds": 20, "volume": 0.8}
    MAC-DO {"action": "audio.tone", "hz": 440, "seconds": 5}
    MAC-DO {"action": "audio.stop"}

Paths are relative to the repository and must stay inside it. `afplay` (macOS) plays in the background; a new play
stops the previous one. The answer names the Mac's output volume and warns when the output is muted or quiet, or when
afplay exited at once, so a microphone test that hears nothing can be told from an app fault.
"""
from __future__ import annotations

import math
import re
import struct
import tempfile
import time
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
    if request.get("loop") and "seconds" in request:
        # Microphone tests (QA-011 Batch 3): repeat the file until `seconds` have passed; afplay plays once.
        seconds = float(request["seconds"])
        volume = f" -v {float(request['volume'])}" if "volume" in request else ""
        script = (f'end=$(( $(date +%s) + {int(seconds + 0.999)} )); '
                  f'while [ $(date +%s) -lt $end ]; do afplay "$0"{volume} -t $(( end - $(date +%s) )); done')
        return ["/bin/sh", "-c", script, str(path)]
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


# Below this output volume (0-100) a device next to the Mac may not hear it (QA-011 pass 9, D2, 2026-11-19: every
# play request ran on time, yet the microphone tests read the room as quieter with the music than without).
QUIET_VOLUME = 25


def parse_volume_settings(text: str) -> tuple[int | None, bool | None]:
    """`osascript -e "get volume settings"` → (output volume 0-100, muted); None for what the text does not say."""
    volume = re.search(r"output volume:(\d+)", text)
    muted = re.search(r"output muted:(true|false)", text)
    return (int(volume.group(1)) if volume else None, (muted.group(1) == "true") if muted else None)


def output_note(context) -> str:
    """What the Mac's output looks like, for the MAC-DONE line; a warning when the device may not hear it."""
    if context.dry_run:
        return ""
    result = context.command(["osascript", "-e", "get volume settings"])
    volume, muted = parse_volume_settings(result.stdout or "")
    if volume is None and muted is None:
        return ""
    if muted:
        return " WARNING: the Mac's output is muted; the device will hear nothing"
    if volume is not None and volume < QUIET_VOLUME:
        return f" WARNING: the Mac's output volume is {volume}; the device may hear nothing"
    return f" (Mac output volume {volume})"


def started_note(context) -> str:
    """An afplay that exits at once (unreadable file, no output device) is reported instead of silence."""
    proc = context.background.get("audio")
    if proc is None or context.dry_run:
        return ""
    time.sleep(0.2)
    code = proc.poll()
    return "" if code is None else f" ERROR: afplay exited at once (code {code})"


def play(request: dict, context) -> str:
    path = fixture_path(str(request.get("file", "Build/fixtures/music-fixture.m4a")))
    context.start("audio", afplay(path, request))
    return f"playing {path.name}{started_note(context)}{output_note(context)}"


def tone(request: dict, context) -> str:
    hz, seconds = float(request.get("hz", 440)), float(request.get("seconds", 5))
    path = tone_wav(Path(tempfile.gettempdir()) / f"mac-driver-tone-{int(hz)}.wav", hz, seconds)
    context.start("audio", afplay(path, {k: v for k, v in request.items() if k == "volume"}))
    return f"tone {hz:g} Hz for {seconds:g} s{started_note(context)}{output_note(context)}"


def stop(request: dict, context) -> str:
    return "stopped" if context.stop("audio") else "nothing playing"


ACTIONS = {"play": play, "tone": tone, "stop": stop}
