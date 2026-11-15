#!/usr/bin/env python3
"""QA-011: inventory of every open `{device}`/`{owner}` task and the owner's batched checklist
(specs/313-qa-011-final-device-matrix).

    python3 scripts/qa011_inventory.py            # write docs/test-reports/qa-011/device-inventory.json
                                                  # and docs/test-reports/qa-011/owner-checklist.md
    python3 scripts/qa011_inventory.py --check    # exit 1 when either committed file is stale
    python3 scripts/qa011_inventory.py --summary  # counts only

Each unchecked task line (`- [ ] `, with its indented continuation lines) whose text carries `{device}` or
`{owner}` (bare or in back-quotes) becomes one entry: task ID, spec, feature, devices, status (open, optional,
waived), category and session. Categories (spec Clarifications 2026-11-15):
  a  scriptable with only an unlocked device and Auto-Lock off: the matrix of scripts/run_device_matrix.py;
  b  needs a person at the device: grouped into the owner sessions below;
  c  owner-only work away from the devices (App Store Connect, signing).
The output has no timestamps, so the same task files always give the same bytes.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_device_matrix as rdm  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SPECS = ROOT / "specs"
OUT_DIR = ROOT / "docs/test-reports/qa-011"
INVENTORY = OUT_DIR / "device-inventory.json"
CHECKLIST = OUT_DIR / "owner-checklist.md"
KIND = "projectM-iOS.qa011.deviceInventory"
SELF_SPEC = "-qa-011-"
LABELS = ("D1", "D2", "D3")

TASK_START = re.compile(r"^- \[ \] ")
ANY_TASK = re.compile(r"^\s*- \[[ xX]\] ")
TAG = re.compile(r"\{(device|owner)\}")
TASK_ID = re.compile(r"^- \[ \] `?((?:[A-Z]+-\d+-)?T\d+)`?\b")

# Category (a): every part of the task is scripted by these matrix cases.
CATEGORY_A: dict[str, list[str]] = {
    "PERF-001-T16": ["autorun-perf001"],
    "PERF-002-T13": ["autorun-perf001"],
    "PERF-009-T16": ["warmstart-perf009"],
    "QA-010-T12": ["autorun-perf001", "launches-sc015", "thresholds"],
    "AUD-014-T32": ["autorun-sc009"],
    "QA-003-T17": ["xctest-goldens"],
    "QA-006-T13": ["xctest-soak-600"],
    "SHD-004-T20": ["xctest-materials"],
    "SHD-002-T24": ["bench-shd002"],
    "CMP-008-T19": ["bench-cmp008"],
    "CMP-009-T19": ["bench-cmp009"],
    "CMP-010-T19": ["bench-cmp010"],
    "SHD-010-T13": ["bench-expression"],
    "REC-013-T14": ["xctest-offline-export"],
}
# Category (b) tasks with a scripted part (the checklist names the case).
AUTOMATED_PARTS: dict[str, list[str]] = {"CMP-001-T20": ["xctest-angle-layer"]}

OWNER_ONLY = re.compile(r"App Store Connect|TestFlight|signing team|certificate|provisioning profile|"
                        r"Paid Apps|banking", re.I)
WAIVED = re.compile(r"⛔")
OPTIONAL = re.compile(r"\bOptional\b|only if a later row needs it|not required for (?:this row|acceptance)|"
                      r"not required for this row's acceptance", re.I)

# Owner sessions in the order the owner does them (fewest reinstalls and hardware changes): first the sessions on
# one Debug install with no extra hardware, then one kind of hardware at a time, Instruments last.
SESSIONS: list[dict] = [
    {"id": "B01", "title": "Visuals and effects: look and frame rate with music", "install": "Debug build (once, "
     "kept through B08)", "preparation": ["Install the signed Debug build from Xcode or `xcodebuild -allowProvisioningUpdates`",
     "Unlock, Auto-Lock Never, Do Not Disturb on, brightness fixed", "Import the reference track and a few photos "
     "for In-App Playback and the Photo visual", "Show the performance overlay (Settings)"],
     "record": ["Frame rate shown by the overlay per check", "Pass/fail by eye with a one-line note",
                "Screenshots only as illustration (never evidence of performance)"]},
    {"id": "B02", "title": "Shows, presets, scenes and everyday controls", "install": "same Debug install",
     "preparation": ["A show with 4-5 cues and a few scenes", "Music playing through In-App Playback"],
     "record": ["Pass/fail per step with a note", "Times where the step names a limit"]},
    {"id": "B03", "title": "Debug fault injection and crash recovery", "install": "same Debug install (DEBUG launch "
     "arguments through Xcode's scheme editor or `devicectl ... process launch -- <args>`)",
     "preparation": ["Xcode open with the device attached", "The launch arguments each step names"],
     "record": ["Pass/fail, the event log lines the step names", "Crash reports produced on purpose"]},
    {"id": "B04", "title": "Accessibility: VoiceOver, large text, Reduce Motion, filters, haptics and hand use",
     "install": "same Debug install", "preparation": ["Accessibility Shortcut set to VoiceOver",
     "Text size AX5 ready in Settings › Accessibility › Display & Text Size", "Reduce Motion, Increase Contrast and "
     "Color Filters reachable"], "record": ["What VoiceOver reads for each control", "Pass/fail per step"]},
    {"id": "B05", "title": "Audio routes, headphones, calls and interruptions", "install": "same Debug install",
     "preparation": ["Wired headphones (USB-C or adapter) and Bluetooth headphones (AirPods)", "A second phone to "
     "call D1 and a FaceTime contact for D2/D3", "An alarm set 2 minutes ahead", "Imported MP3/M4A tracks"],
     "record": ["Pass/fail per route change and interruption", "Whether audio or visuals glitched"]},
    {"id": "B06", "title": "Camera and motion sensors", "install": "same Debug install",
     "preparation": ["Good light and a coloured light source", "A face and hands in frame", "Camera permission not "
     "yet granted for the first step (reset with Settings › General › Transfer or Reset › Reset Location & Privacy "
     "only if needed)"], "record": ["Pass/fail per step", "Frame rate and thermal state where asked"]},
    {"id": "B07", "title": "Photos and Files pickers, iCloud, sharing, import and export", "install": "same Debug install",
     "preparation": ["Photos with HEIC, ProRAW, panorama, animated GIF, HDR and transparent PNG items",
     "Files: On My iPhone/iPad and iCloud Drive with a not-yet-downloaded file", "A DRM-protected purchase and "
     "DRM-free MP3/AAC/M4A/WAV files", "A second device for AirDrop"],
     "record": ["Pass/fail per pick, import and share", "Messages shown on refusals"]},
    {"id": "B08", "title": "Recording", "install": "same Debug install",
     "preparation": ["At least 5 GB free (and, for the low-storage step, a nearly full device)", "Music playing"],
     "record": ["File size, duration, frame rate and dropped frames", "Whether the file plays in Files"]},
    {"id": "B09", "title": "Network: Wi-Fi controllers, two devices, Airplane Mode, privacy report",
     "install": "fresh install of the Debug build at the start (UIX-001 needs it)",
     "preparation": ["A Mac or second device on the same Wi-Fi with an OSC sender/receiver", "Two of D1-D3 on one "
     "Wi-Fi", "App Privacy Report on (Settings › Privacy & Security)", "USB cable connected so devicectl still "
     "reaches the device in Airplane Mode"], "record": ["Pass/fail per step", "App Privacy Report entries"]},
    {"id": "B10", "title": "MIDI hardware", "install": "same install",
     "preparation": ["A class-compliant USB MIDI controller with faders, knobs, pads (14-bit and motorised if "
     "available)", "A USB-C hub", "A MIDI clock source at 120 and 174 BPM"], "record": ["Pass/fail per mapping"]},
    {"id": "B11", "title": "External display, AirPlay and projector", "install": "same install",
     "preparation": ["USB-C to HDMI adapter and an HDMI display (4K if available)", "An Apple TV on the same "
     "network", "A projector (and a curved surface for grid warp)", "A hardware keyboard for D2"],
     "record": ["Pass/fail per step", "External frame rate from the overlay", "Display resolution and refresh"]},
    {"id": "B12", "title": "iPad multitasking: Stage Manager, Split View, windows", "install": "same install on D2 and D3",
     "preparation": ["Stage Manager on", "A second app for Split View"], "record": ["Pass/fail per step"]},
    {"id": "B13", "title": "Measurements attached to Xcode and Instruments", "install": "Release build run from "
     "Xcode (Profile) with the device attached", "preparation": ["Instruments templates: Allocations, Metal System "
     "Trace, Energy Log, os_signpost", "Xcode's memory gauge and Simulate Memory Warning", "A 240 fps camera for "
     "the latency steps"], "record": ["Trace files (kept outside git; note their SHA-256)", "Numbers into "
     "docs/test-reports/performance.md"]},
]
SESSION_IDS = [s["id"] for s in SESSIONS]

# Matching priority: first the rules for scarce hardware or special builds, then the feature prefix, then
# keywords; the first match picks the session. SESSION_OVERRIDES settle the few steps the rules misread.
HARDWARE_RULES: list[tuple[str, re.Pattern]] = [(sid, re.compile(rx, re.I)) for sid, rx in [
    ("B10", r"\bMIDI\b|controller with (?:motorised|LED)|14-bit controller|physical controller|USB controller|"
            r"clock source"),
    ("B11", r"external display|projector|AirPlay|HDMI|Apple TV|\b4K display|composite adapter|extended display"),
    ("B09", r"Wi-?Fi|\bLAN\b|two devices|second device on|Airplane Mode|App Privacy Report|Local Network|"
            r"\bOSC\b|network-synced"),
    ("B12", r"Stage Manager|Split View|split editor|multiwindow|editor windows|hardware keyboard|in the split"),
    ("B13", r"Instruments|Metal System Trace|Energy Log|memory gauge|Simulate Memory Warning|memory report|"
            r"currentAllocatedSize|signposts?|240 fps|AnalysisBench|in Release|Release build|GPU (?:time|frame)|"
            r"frame cost|frame-time sample|cost on D1|allocation trace|usability|participants|device sweep|"
            r"thermal state|sustained load|RendererLab"),
    ("B03", r"-uitest|\bDEBUG\b|Debug build|Crash now|force-quit"),
]]
PREFIX_SESSIONS = {"CAM": "B06", "MIDI": "B10", "OSC": "B09", "OUT": "B11", "ACC": "B04", "AUD": "B05",
                   "REC": "B08", "MED": "B07", "FILE": "B07", "SHOW": "B02", "QA-008": "B08", "QA-009": "B04"}
KEYWORD_RULES: list[tuple[str, re.Pattern]] = [(sid, re.compile(rx, re.I)) for sid, rx in [
    ("B06", r"\bcamera\b|\blens\b|Ultra Wide|face tracking|real face|real hands|Tilt forward|Shake|"
            r"white balance|person masked|Mirror flips|Back and Front"),
    ("B05", r"headphones|Bluetooth|AirPods|route change|interruption|phone call|FaceTime|incoming call|alarm|"
            r"Siri|hard-panned|quiet room|phase-inverted|\bseek\b|[Ss]huffle|One Track|reorder while|"
            r"Microphone|microphone|platform backends|signal kind"),
    ("B07", r"Photos|Files|iCloud|AirDrop|share sheet|Messages|import|Storage|Clear Caches|DRM|HEIC|ProRAW|GIF|"
            r"DNG|panorama|picker|installing over"),
    ("B08", r"\brecord\b|\brecordings?\b|Save Frame|countdown"),
    ("B01", r"with music, choose|performance overlay|PERF-001/007 overlay|frame time|Photo visual"),
    ("B04", r"VoiceOver|AX5|Dynamic Type|largest text|Reduce Motion|Color Filters|Increase Contrast|[Hh]aptics|"
            r"left hand|Left hand|\bthumb\b|72 pt|one-handed"),
    ("B02", r"\bshow\b|\bcue\b|cues|preset|scene|collection|tap tempo|tempo|BPM|tutorial|Help|HUD|sample a live|"
            r"Settings|app switcher|backgrounding|lock and|lock;|Reset 2 parameters|editor|gesture"),
]]
SESSION_OVERRIDES = {"UIX-007-T13": "B12", "UIX-006-T14": "B02", "PERF-004-T15": "B13", "FILE-001-T19": "B07",
                     "FX-001-T27": "B01"}
DEFAULT_SESSION = "B01"
SESSION_ORDER = {sid: i for i, sid in enumerate(SESSION_IDS)}


# MARK: - Parsing

def feature_of(spec_dir: str) -> str:
    m = re.match(r"^\d{3}-([a-z]+)-(\d{3})-", spec_dir)
    return f"{m.group(1).upper()}-{m.group(2)}" if m else spec_dir.split("-", 1)[0]


def parse_tasks(text: str) -> list[tuple[int, str]]:
    """(line number, joined text) of every unchecked task, continuation lines included."""
    lines = text.split("\n")
    out, i = [], 0
    while i < len(lines):
        if TASK_START.match(lines[i]):
            start, body, j = i + 1, [lines[i].strip()], i + 1
            while (j < len(lines) and lines[j].strip() and lines[j].startswith((" ", "\t"))
                   and not ANY_TASK.match(lines[j])):
                body.append(lines[j].strip())
                j += 1
            out.append((start, " ".join(body)))
            i = j
        else:
            i += 1
    return out


def step_text(text: str) -> str:
    """The step without its leading checkbox."""
    return re.sub(r"^- \[ \] ", "", text)


QUICKSTART_REF = re.compile(r"quickstart\s+(?:[A-Z]\d*(?:\s*\d+(?:\s*-\s*\d+)?)?(?:\s*(?:,|and)\s*[A-Z]\d+)*)", re.I)


def devices_of(text: str) -> tuple[list[str], bool]:
    """D1-D3 named by the step (notes after " — " ignored); none → D1, inferred."""
    step = text.split(" — ")[0]
    step = QUICKSTART_REF.sub("quickstart", step)   # "quickstart D1, D2" are quickstart sections
    found: set[str] = set()
    for a, b in re.findall(r"\bD([1-3])\s*[-–]\s*D?([1-3])\b", step):
        found.update(f"D{n}" for n in range(int(a), int(b) + 1))
    found.update(f"D{n}" for n in re.findall(r"\bD([1-3])\b", step))
    if re.search(r"every (?:FR-032 )?device|each device|all three devices", step, re.I):
        found.update(LABELS)
    if re.search(r"iPadOS 26(?:\.5)?|iOS 26 path", step):
        found.add("D3")
    if re.search(r"\b(?:an|the) iPads?\b", step) and not found & {"D2", "D3"}:
        found.update(("D2", "D3"))
    if re.search(r"[Tt]wo devices|second device", step) and len(found) < 2:
        found.update(("D1", "D2") if not found or found == {"D1"} else ("D1",))
    if re.search(r"reference device", step):
        found.add("D1")
    if not found:
        return ["D1"], True
    return sorted(found), False


def status_of(text: str) -> str:
    if WAIVED.search(text):
        return "waived"
    if OPTIONAL.search(text):
        return "optional"
    return "open"


def classify(task_id: str, text: str, tags: list[str]) -> tuple[str, str | None, list[str]]:
    """(category, session, matrix cases)."""
    if task_id in CATEGORY_A:
        return "a", "MATRIX", list(CATEGORY_A[task_id])
    step = text.split(" — ")[0]
    if OWNER_ONLY.search(step) and not re.search(r"\bD[1-3]\b|on (?:a|the) device", step):
        return "c", None, []
    return "b", session_for(task_id, step), list(AUTOMATED_PARTS.get(task_id, []))


def session_for(task_id: str, step: str) -> str:
    if task_id in SESSION_OVERRIDES:
        return SESSION_OVERRIDES[task_id]
    for sid, rule in HARDWARE_RULES:
        if rule.search(step):
            return sid
    for prefix, sid in PREFIX_SESSIONS.items():
        if task_id.startswith(prefix + "-"):
            return sid
    for sid, rule in KEYWORD_RULES:
        if rule.search(step):
            return sid
    return DEFAULT_SESSION


def estimate_minutes(text: str, devices: list[str]) -> int:
    named = sum(int(n) for n in re.findall(r"\b(\d{1,2})\s*(?:-\s*)?(?:minutes?|min)\b", text.split(" — ")[0])
                if int(n) <= 30)
    return (5 + named) * len(devices)


def collect(specs: Path = SPECS) -> list[dict]:
    tasks = []
    for path in sorted(specs.glob("*/tasks.md")):
        spec = path.parent.name
        if SELF_SPEC in spec:   # QA-011's own device-run tasks are the matrix itself
            continue
        for line, text in parse_tasks(path.read_text(encoding="utf-8")):
            tags = sorted(set(TAG.findall(text)))
            if not tags:
                continue
            m = TASK_ID.match(text)
            task_id = m.group(1) if m else f"{spec}:{line}"
            devices, inferred = devices_of(step_text(text))
            status = status_of(text)
            category, session, cases = classify(task_id, step_text(text), tags)
            if status == "waived":
                session = None
            tasks.append({"id": task_id, "spec": spec, "feature": feature_of(spec), "line": line, "tags": tags,
                          "status": status, "category": category, "session": session, "devices": devices,
                          "devicesInferred": inferred, "matrixCases": cases,
                          "estimatedMinutes": estimate_minutes(text, devices) if session else 0,
                          "text": step_text(text)})
    return tasks


# MARK: - Inventory and checklist

def count(values) -> dict[str, int]:
    out: dict[str, int] = {}
    for v in values:
        out[v] = out.get(v, 0) + 1
    return dict(sorted(out.items()))


def sessions_with_tasks(tasks: list[dict]) -> list[dict]:
    out = []
    for s in SESSIONS:
        members = [t for t in tasks if t["session"] == s["id"]]
        minutes = sum(t["estimatedMinutes"] for t in members)
        out.append({**s, "order": SESSION_ORDER[s["id"]] + 1,
                    "devices": sorted({d for t in members for d in t["devices"]}),
                    "tasks": [f"{t['spec']}:{t['id']}" for t in members],
                    "optionalTasks": sum(1 for t in members if t["status"] == "optional"),
                    "estimatedMinutes": int(math.ceil(minutes / 5.0) * 5)})
    return out


def build_inventory(tasks: list[dict]) -> dict:
    live = [t for t in tasks if t["status"] != "waived"]
    devices_by_case = rdm.case_devices({"tasks": tasks})
    return {
        "kind": KIND, "schemaVersion": 1,
        "source": "specs/*/tasks.md: unchecked task lines tagged {device} or {owner}",
        "generator": "scripts/qa011_inventory.py",
        "counts": {
            "total": len(tasks), "specs": len({t["spec"] for t in tasks}),
            "byStatus": count(t["status"] for t in tasks),
            "byCategory": count(t["category"] for t in live),
            "byCategoryIncludingWaived": count(t["category"] for t in tasks),
            "byDevice": {d: sum(1 for t in live if d in t["devices"]) for d in LABELS},
            "byDeviceAndCategory": {d: count(t["category"] for t in live if d in t["devices"]) for d in LABELS},
            "bySession": count(t["session"] for t in live if t["session"]),
            "devicesInferred": sum(1 for t in live if t["devicesInferred"]),
        },
        "matrixCases": [{"id": c["id"], "kind": c["kind"], "title": c["title"], "closes": c["closes"],
                         "partOf": c.get("partOf", []), "devices": devices_by_case[c["id"]],
                         "timeoutSeconds": c["timeoutSeconds"]} for c in rdm.CASES],
        "sessions": sessions_with_tasks(tasks),
        "tasks": tasks,
    }


def render_json(inventory: dict) -> str:
    return json.dumps(inventory, indent=2, ensure_ascii=False, sort_keys=False) + "\n"


def matrix_command(label: str) -> str:
    return f"python3 scripts/run_device_matrix.py --device {label}"


def render_checklist(inv: dict) -> str:
    c = inv["counts"]
    tasks = {f"{t['spec']}:{t['id']}": t for t in inv["tasks"]}
    total_minutes = sum(s["estimatedMinutes"] for s in inv["sessions"])
    out = [
        "# QA-011 owner checklist: final physical device stage",
        "",
        "Generated by `python3 scripts/qa011_inventory.py` from every `specs/*/tasks.md` (do not edit by hand; "
        "`--check` fails when this file is stale). Spec: `specs/313-qa-011-final-device-matrix/`.",
        "",
        f"Open device and owner work: **{c['total']} tasks in {c['specs']} specs** — "
        + ", ".join(f"{k} {v}" for k, v in c["byStatus"].items()) + ". Categories (waived excluded): "
        + ", ".join(f"({k}) {v}" for k, v in c["byCategory"].items())
        + ". (a) runs in the scripted matrix; (b) needs a person at the device; (c) is owner-only work away "
        "from the devices.",
        "",
        "Rules for every session: nothing here is done by an agent. Simulator results are never evidence. Tick a "
        "task `[X]` in its own `tasks.md` only after the step passed on the device, appending "
        "\" — Verified <date> on <device>: <how>\". Keep D3 on iPadOS 26.5.",
        "",
        "## Session 0: the scripted matrix (category a)",
        "",
        "Preparation for each device: connect the cable, unlock it, set Auto-Lock to Never (Settings › Display & "
        "Brightness), keep it unlocked and on power. The run starts with a fresh install (an empty container), so on "
        "D1 and D3 stay at the device for `autorun-sc009`: iOS asks once for microphone access; tap Allow. "
        "Nothing else needs a person. The main session runs (D1, then D2, then D3):",
        "",
        "```bash",
        "python3 scripts/verify_environment.py",
        "python3 scripts/run_device_tests.py build          # Release + PROJECTM_AUTOMATION, the owner's team",
    ]
    for label in LABELS:
        out.append(f"{matrix_command(label)}    # then: python3 scripts/run_device_matrix.py verify "
                   f"docs/test-reports/qa-011/runs/{label}/<run-id>/record.json")
    out += ["```", "", "| Case | Devices | Closes | Limit |", "|---|---|---|---|"]
    for m in inv["matrixCases"]:
        closes = ", ".join(m["closes"] + [f"part of {x}" for x in m["partOf"]])
        out.append(f"| `{m['id']}` | {', '.join(m['devices'])} | {closes} | {m['timeoutSeconds']} s |")
    a_tasks = [t for t in inv["tasks"] if t["category"] == "a" and t["status"] != "waived"]
    out += ["", "Tasks the matrix closes when its cases pass on the named devices:", ""]
    for t in a_tasks:
        out.append(f"- [ ] `{t['id']}` ({', '.join(t['devices'])}) — {', '.join(t['matrixCases'])}")
    out += ["", f"Estimated person time for sessions B01-B13: about {total_minutes // 60} h {total_minutes % 60} min "
            "(5 minutes per task and device plus any duration a step names; the matrix itself runs unattended "
            "for about 1-1.5 h per device).", ""]
    for s in inv["sessions"]:
        members = [tasks[k] for k in s["tasks"]]
        out += [f"## {s['id']} {s['title']}", "",
                f"- Devices: {', '.join(s['devices']) or '-'}; tasks: {len(members)}"
                + (f" ({s['optionalTasks']} optional)" if s["optionalTasks"] else "")
                + f"; estimated {s['estimatedMinutes']} min",
                f"- Install: {s['install']}",
                "- Preparation: unlock each device, Auto-Lock Never, cable connected; "
                + "; ".join(s["preparation"]),
                "- Record: " + "; ".join(s["record"]) + "; the result goes into each task's own `tasks.md` and "
                "the test report it names.", "", "Steps:", ""]
        for t in members:
            extra = []
            if t["status"] == "optional":
                extra.append("optional")
            if t["devicesInferred"]:
                extra.append("device inferred")
            if t["matrixCases"]:
                extra.append("scripted part: " + ", ".join(f"`{x}`" for x in t["matrixCases"]))
            note = f" *({'; '.join(extra)})*" if extra else ""
            out.append(f"- [ ] `{t['id']}` [{', '.join(t['devices'])}] ({t['spec']}){note}: {t['text']}")
        out += ["", "Closes: " + (", ".join(f"`{tasks[k]['id']}`" for k in s["tasks"]) or "-"), ""]
    c_tasks = [t for t in inv["tasks"] if t["category"] == "c" and t["status"] != "waived"]
    out += ["## Owner-only work away from the devices (category c)", ""]
    out += [f"- [ ] `{t['id']}` ({t['spec']}): {t['text']}" for t in c_tasks] or ["None open."]
    waived = [t for t in inv["tasks"] if t["status"] == "waived"]
    out += ["", "## Waived (⛔ not required; listed for completeness, no session)", ""]
    out += [f"- `{t['id']}` ({t['spec']})" for t in waived] or ["None."]
    return "\n".join(out) + "\n"


def generate(specs: Path = SPECS) -> tuple[str, str]:
    inv = build_inventory(collect(specs))
    return render_json(inv), render_checklist(inv)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="exit 1 when the committed files are stale")
    parser.add_argument("--summary", action="store_true", help="print the counts only")
    parser.add_argument("--specs", type=Path, default=SPECS)
    parser.add_argument("--out-dir", type=Path, default=OUT_DIR)
    args = parser.parse_args(argv)
    text, checklist = generate(args.specs)
    inventory_path, checklist_path = args.out_dir / INVENTORY.name, args.out_dir / CHECKLIST.name
    counts = json.loads(text)["counts"]
    if args.summary:
        print(json.dumps(counts, indent=2))
        return 0
    if args.check:
        stale = [p for p, body in ((inventory_path, text), (checklist_path, checklist))
                 if not p.exists() or p.read_text(encoding="utf-8") != body]
        for p in stale:
            print(f"stale: {p} (run python3 scripts/qa011_inventory.py)")
        return 1 if stale else 0
    args.out_dir.mkdir(parents=True, exist_ok=True)
    inventory_path.write_text(text, encoding="utf-8")
    checklist_path.write_text(checklist, encoding="utf-8")
    print(f"{counts['total']} tasks in {counts['specs']} specs: {counts['byStatus']}, categories "
          f"{counts['byCategory']}, devices {counts['byDevice']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
