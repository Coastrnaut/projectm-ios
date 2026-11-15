#!/usr/bin/env python3
"""Run feature 002's device tests from the Mac (T238 performance and size, T239 purchase checks,
T241 privacy review) on D1-D3 over devicectl, or rehearse them on a simulator.

The app's AutomationRunner does the measuring (PROJECTM_AUTORUN modes; see
Apps/projectM-iOS/Automation/AutomationRunner.swift). This script builds the measurement build,
installs it, launches each mode, pulls the reports into
docs/test-reports/exports/feature002/<D1|D2|D3|sim>/ and checks them against the spec's targets.

    python3 scripts/run_device_tests.py devices                 # which of D1-D3 are connected
    python3 scripts/run_device_tests.py build                   # Release + PROJECTM_AUTOMATION, devices
    python3 scripts/run_device_tests.py perf --device D1        # T238: SC-101, SC-102, SC-104
    python3 scripts/run_device_tests.py scroll --device D1      # T238: SC-103 (UI test on the device)
    python3 scripts/run_device_tests.py size                    # T238: SC-108 (App Thinning report)
    python3 scripts/run_device_tests.py entitlement --device D1 # T239: after a sandbox purchase/restore
    python3 scripts/run_device_tests.py privacy --device D1     # T241: session, container, keys
    python3 scripts/run_device_tests.py summarize               # verdicts from the pulled reports
    python3 scripts/run_device_tests.py thresholds --device D1 --run --report <PERF-012 export>
                                                                # QA-010: budgets (docs/performance/thresholds.json)

--simulator <UDID> replaces --device to rehearse a step on a simulator (a Debug build from
--app). Simulator results are never evidence (Constitution X); they go to exports/feature002/sim.
--dry-run prints the commands without running them.

What still needs a person (the script says so when it gets there):
- Signing: the measurement build and the on-device UI test use the team in the gitignored
  Configs/Signing.local.xcconfig; the script never changes signing.
- T239: the purchase sheet (Buy, then the sandbox account) and turning the network off (Airplane
  Mode) for the offline relaunch. The in-app purchase must exist in App Store Connect first (T242).
- T241: a fresh install (the script can remove the app first with --reinstall) and, for the
  purchase part, T239 done on the same install.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_performance_thresholds as cpt  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
BUNDLE = "org.projectmios.ProjectMiOS"
SCHEME = "projectM-iOS"
PROJECT = ROOT / "ProjectM-iOS.xcodeproj"
EXPORTS = ROOT / "docs/test-reports/exports/feature002"
BUILD = ROOT / "Build/automation"
DEVICES = {"D1": "iPhone15,4", "D2": "iPad17,3", "D3": "iPad15,7"}   # docs/test-reports/devices.md

# The spec's targets (specs/002-preset-library-unlock/spec.md, Success Criteria).
TARGETS = {
    "SC-101": "library ready within 0.15 s of the chooser appearing (D1, D3)",
    "SC-102": "search results within 0.05 s of each keystroke (D1, D3)",
    "SC-103": "at least 95% of frames on time while scrolling for 10 s (D1-D3)",
    "SC-104": "95% of preset switches from any pack show their first frame within 1 s (D1)",
    "SC-108": "installed size grows by no more than 40 MB over release 1.0",
}
# FR-065 plus FR-123, VIS-001-R11 (the visual and its bar count) and FX-001-R11 (the circular
# spectrum's glow): everything the app may store in its UserDefaults.
ALLOWED_KEYS = {"favorites", "lastPresetID",
                "recentPresets", "settings.recentPresets.enabled",   # PRE-006-R9 (preset IDs only; ADR-0055)
                "settings.performanceOverlay", "settings.reduceFlashing",
                "settings.photo.slideshow",   # MED-006
                "settings.photo.kenBurns",   # MED-007
                "settings.logo.id",   # MED-010
                "settings.logo.placement",   # MED-010
                "settings.clock.overlay",   # MED-011 (clock overlay; off by default)
                "settings.countdown.overlay",   # MED-012 (countdown overlay; off by default)
                "settings.presetScope", "notice.photosensitivityAcknowledged",
                "settings.visual", "settings.circularSpectrum.bars",
                "settings.camera.position", "settings.camera.mirrorFront", "settings.camera.mirrorBack",
                "settings.camera.cropMode", "settings.camera.cropAnchor", "settings.camera.zoom",   # CAM-007
                "settings.camera.lens",   # CAM-003
                "settings.camera.personMask",   # CAM-008
                "settings.camera.faceTracking", "settings.camera.faceTrackingConsent",   # CAM-009-R3
                "settings.camera.handTracking", "settings.camera.handTrackingConsent",   # CAM-010-R3
                "settings.visual.colorBlindSafePalette",   # ACC-003-R13
                "settings.sensorySafety.profile", "settings.sensorySafety.flashesPerSecond",   # ACC-012-R8
                "settings.sensorySafety.riseLimit", "settings.sensorySafety.intensityLimit",   # ACC-012-R8
                "settings.haptics.beatPulses", "settings.haptics.beatEvent", "settings.haptics.strength",   # ACC-007-R8
                "settings.motion.range",   # CAM-011-R12
                "settings.colorGrade.temperature", "settings.colorGrade.lift", "settings.colorGrade.gamma",   # FX-003-R8
                "settings.colorGrade.gain", "settings.colorGrade.saturation", "settings.colorGrade.hue",   # FX-004-R8
                "settings.colorGrade.contrast", "settings.colorGrade.contrastStrength",   # FX-005-R8
                "settings.colorGrade.posterize", "settings.colorGrade.posterizeLevels",   # FX-013-R8
                "settings.colorGrade.posterizeDither",   # FX-013-R8
                "settings.feedback.enabled", "settings.feedback.halfLife",   # FX-009-R11 (Trails, off by default)
                "settings.noiseEditor.values",   # SHD-006-R7 (Noise editor values, absent at defaults)
                "settings.colorGrade.enabled", "settings.effectChain.order", "settings.effectChain.presets",   # FX-020-R8, R10
                "settings.chromatic.enabled", "settings.chromatic.amount", "settings.chromatic.angle",   # FX-006-R9
                "settings.chromatic.radial",
                "settings.directionalBlur.enabled", "settings.directionalBlur.radius",   # FX-007-R10
                "settings.directionalBlur.angle",
                "settings.radialBlur.enabled", "settings.radialBlur.strength", "settings.radialBlur.centerX",   # FX-008-R9
                "settings.radialBlur.centerY",
                "settings.echo.enabled", "settings.echo.count", "settings.echo.delay",   # FX-010-R13
                "settings.echo.decay",
                "settings.mosaic.enabled", "settings.mosaic.size", "settings.mosaic.shape",   # FX-012-R9
                "settings.edgeOutline.enabled", "settings.edgeOutline.threshold",   # FX-014-R10
                "settings.edgeOutline.width", "settings.edgeOutline.color", "settings.edgeOutline.mode",
                "settings.circularSpectrum.glow", "settings.circularSpectrum.glowIntensity",
                "settings.circularSpectrum.glowRadius", "settings.circularSpectrum.glowThreshold",
                "settings.linearSpectrum.orientation", "settings.linearSpectrum.spacing",   # VIS-002-R11
                "settings.oscilloscope.line", "settings.oscilloscope.window",   # VIS-003-R10
                "settings.lissajous.mode", "settings.lissajous.persistence",   # VIS-004-R11
                "settings.radialWaveform.ring", "settings.radialWaveform.amplitude",   # VIS-005-R9
                "settings.beatRings.life",   # VIS-006-R9
                "settings.mandala.symmetry", "settings.mandala.mirror", "settings.mandala.petal",   # VIS-007-R9
                "settings.particleFountain.gravity",   # VIS-008-R10
                "settings.particleFountain.emitter",   # SHD-007-R8 (Particle emitter editor, absent at defaults)
                "settings.particleOrbit.radius",   # VIS-009-R10
                "settings.particleTrails",   # VIS-010-R9
                "settings.noiseField.frequency", "settings.noiseField.octaves", "settings.noiseField.seed",   # VIS-013-R9
                "settings.kaleidoscope.wedges",   # VIS-014-R9
                "settings.tunnel.pace",   # VIS-015-R9
                "settings.reactionDiffusion.preset",   # VIS-012-R13
                "settings.reactionDiffusion.pattern",
                "settings.reactionDiffusion.seed",
                "settings.reactionDiffusion.speed",
                "settings.starfield.speed", "settings.starfield.density",   # VIS-016-R8
                "settings.signedDistance.quality",   # VIS-017-R8
                "settings.tessellation.tiling", "settings.tessellation.tiles",   # VIS-018-R10
                "settings.tessellation.symmetry", "settings.tessellation.mirror", "settings.tessellation.palette",
                "settings.spectrum.attack", "settings.spectrum.release",   # ANL-003-R6
                "settings.osc.enabled", "settings.osc.port",   # OSC-001 (off by default)
                "settings.osc.disabledRoutes", "settings.osc.aliases",   # OSC-003 (route addresses and parameter IDs)
                "settings.osc.peerAllowlist.enabled", "settings.osc.approvedPeers",   # OSC-008 (user-approved local hosts)
                "settings.osc.send.enabled", "settings.osc.send.host", "settings.osc.send.port",   # OSC-005 (Send OSC)
                "settings.osc.send.kinds", "settings.osc.send.sceneNames",
                "settings.osc.discovery.browse", "settings.osc.discovery.advertise",   # OSC-011 (Nearby Devices switches)
                "settings.osc.cueSync.role",   # OSC-012 (Cue Sync role: off, lead, follow; absent = off)
                "settings.midi.enabled",   # MIDI-001 (off by default; no device names stored)
                "settings.midi.mappings",  # MIDI-003 (channel, controller and parameter ID per line; no device)
                "settings.midi.followClock",  # MIDI-010 (Follow MIDI clock; absent = off)
                "settings.parameterShelf.pins",  # UIX-004-R10 (ordered pinned parameter IDs)
                "settings.scene.locked",  # SCN-015 (scene lock; absent = unlocked)
                "settings.modulation.quantize",  # MOD-017 (quantize mode; absent = off)
                "settings.show.quantizeCues",  # SHOW-003 (cue step quantize mode; absent = off)
                "settings.show.loop",  # SHOW-007 (Loop the show timeline; absent = off)
                "settings.show.rotation",  # SHOW-013 (auto scene rotation choices; absent = defaults)
                "settings.inputTrim.decibels",   # AUD-008-R6 (analysis-only input trim)
                "settings.analysisChannel.mode",   # AUD-009-R6 (analysis-only channel selection)
                "settings.playbackBalance.position",   # AUD-010-R7 (In-App Playback monitoring balance)
                "settings.noiseGate.enabled",   # AUD-011-R8 (analysis-only noise gate, microphone)
                "settings.noiseGate.thresholdDecibels",   # AUD-011-R8
                "settings.recording.includeMicrophone",   # REC-004-R3 (microphone audio in recordings; off by default)
                "settings.recording.qualityProfile",   # REC-005-R7 (record quality profile; Standard by default)
                "settings.splitEditor.width",   # UIX-007-R7 (iPad split editor width; Standard by default)
                "settings.recording.frameRate",   # REC-006-R8 (record frame rate; Profile default by default)
                "settings.recording.aspect",   # REC-014-R7 (record aspect; Match screen by default)
                "settings.recording.customWidth", "settings.recording.customHeight",   # REC-014-R7 (custom size)
                "settings.recording.countdown",   # REC-007-R8 (recording countdown; Off by default)
                "settings.visualizer.sceneHUD",   # UIX-013-R11 (scene performance HUD; off by default)
                "settings.gestures.shortcuts",   # UIX-006-R9 (gesture shortcuts switch and mapping; off by default)
                "settings.visualizer.guides", "settings.visualizer.guides.actionSafe",   # OUT-005-R6 (safe-area guides; off)
                "settings.visualizer.guides.titleSafe", "settings.visualizer.guides.centreCross",
                "settings.controls.oneHanded",   # ACC-009-R9 (one-handed layout; Off by default)
                "settings.controls.leftHanded",   # ACC-010-R7 (left-handed controls; off by default)
                "settings.performance.powerProfile",   # PERF-008-R6 (power profile; Standard by default)
                "settings.externalDisplay.fit", "settings.externalDisplay.shape",   # OUT-004-R8 (external output correction)
                "settings.externalDisplay.pixelAspect",   # OUT-004-R8
                "settings.externalDisplay.resolution", "settings.externalDisplay.resolutionPercent",   # OUT-003-R7
                "settings.externalDisplay.outputMode",   # OUT-006-R7
                "settings.externalDisplay.cornerPin",   # OUT-007-R9 (corner pin; identity = absent)
                "settings.externalDisplay.calibration",   # OUT-009-R9 (display calibration; identity = absent)
                "settings.recording.timedStop",   # REC-008-R9 (stop recording after a length; Off by default)
                "settings.latencyOffset.microphone",   # AUD-013-R11 (per-source visual delay)
                "settings.latencyOffset.inAppPlayback", "settings.latencyOffset.systemAppCapture",   # AUD-013-R11
                "settings.photo.id", "settings.video.id", "settings.text.overlay",   # MED-001, MED-008, MED-009
                "settings.video.loop",   # MED-003 (the stored video's loop region)
                "settings.video.speed",  # MED-004 (the stored video's playback speed)
                "settings.video.reverse",  # MED-005 (reverse playback of the stored video)
                "guide.firstScene",   # UIX-001
                "permission.explained.camera", "permission.explained.localNetwork",   # UIX-015 (a yes each)
                "session.recovery.open", "session.recovery.sessionsSinceReopen",
                "session.recovery.heldVisual"}   # PERF-010
# Every key the app stores must be listed above; test_scripts.py checks this against the app's
# `static let ...Key = "..."` constants.
# AUD-001-R22 amends FR-065: audio files the user imported are stored, and only here: the audio
# library's content-addressed copies (assets/<sha256>[.ext]) and its imports in flight
# (incoming/<uuid>[.ext]). An audio file anywhere else in the container is still a violation.
IMPORTED_AUDIO = re.compile(
    r"Library/Application Support/AudioLibrary/"
    r"(assets/[0-9a-f]{64}(\.[0-9a-z]{1,8})?|incoming/[0-9A-Fa-f-]{36}(\.[0-9a-z]{1,8})?)")
AUDIO_SUFFIXES = (".wav", ".caf", ".m4a", ".aac", ".mp3", ".pcm", ".aif", ".aiff", ".flac", ".mp4", ".alac")
# Keys iOS frameworks write into the app's own defaults, not the app (reported as notes).
SYSTEM_KEYS = {"SKTransactionUpdatesLastChecked": "StoreKit (iOS): when it last checked for transaction "
                                                  "updates; a timestamp, no purchase data"}

DRY_RUN = False
LOCKED_WAIT = 30 * 60   # a locked device gets this long to be unlocked before a launch gives up


def run(cmd: list[str], *, env: dict | None = None, check: bool = True, capture: bool = False,
        timeout: float | None = None, quiet: bool = False) -> subprocess.CompletedProcess:
    shown = " ".join(shlex.quote(c) for c in cmd)
    if env:
        shown = " ".join(f"{k}={shlex.quote(v)}" for k, v in env.items()) + " " + shown
    if not quiet:
        print(f"$ {shown}", flush=True)
    if DRY_RUN:
        return subprocess.CompletedProcess(cmd, 0, "", "")
    return subprocess.run(cmd, env={**os.environ, **(env or {})}, check=check, text=True,
                          capture_output=capture, timeout=timeout)


def person(step: str) -> None:
    """A step only a person can do; waits for Return (skipped in --dry-run)."""
    print(f"\n>>> {step}")
    if not DRY_RUN:
        input(">>> Press Return when done. ")


# MARK: - Targets (a device over devicectl, or a simulator over simctl)

class Target:
    def __init__(self, label: str, identifier: str, simulator: bool):
        self.label, self.identifier, self.simulator = label, identifier, simulator

    @property
    def out_dir(self) -> Path:
        return EXPORTS / ("sim" if self.simulator else self.label)

    def install(self, app: Path) -> None:
        if self.simulator:
            run(["xcrun", "simctl", "install", self.identifier, str(app)])
        else:
            run(["xcrun", "devicectl", "device", "install", "app", "--device", self.identifier, str(app)])

    def uninstall(self) -> None:
        if self.simulator:
            run(["xcrun", "simctl", "uninstall", self.identifier, BUNDLE], check=False)
        else:
            run(["xcrun", "devicectl", "device", "uninstall", "app", "--device", self.identifier, BUNDLE], check=False)

    def launch(self, mode: str, extra: dict[str, str] | None = None) -> None:
        variables = {"PROJECTM_AUTORUN": mode, **(extra or {})}
        if self.simulator:
            run(["xcrun", "simctl", "launch", "--terminate-running-process", self.identifier, BUNDLE],
                env={f"SIMCTL_CHILD_{k}": v for k, v in variables.items()})
        else:
            cmd = ["xcrun", "devicectl", "device", "process", "launch", "--device", self.identifier,
                   "--terminate-existing", "--environment-variables", json.dumps(variables), BUNDLE]
            deadline = time.time() + LOCKED_WAIT
            while True:
                with tempfile.TemporaryDirectory() as tmp:
                    out = Path(tmp) / "launch.json"
                    result = run(cmd + ["--json-output", str(out)], check=False, capture=True)
                    if result.returncode == 0 or DRY_RUN:
                        return
                    # devicectl reports the reason in its JSON output, not on stdout or stderr.
                    reason = out.read_text() if out.exists() else result.stdout + result.stderr
                if time.time() > deadline:
                    sys.exit(f"launch failed on {self.label}: {reason[-600:]}")
                why = "is locked: unlock it (and set Auto-Lock to Never)" if "Locked" in reason else "launch failed"
                print(f"!! {self.label} {why}; retrying in 15 s", flush=True)
                time.sleep(15)

    def terminate(self) -> None:
        """Stops the app if a mode left it running."""
        if self.simulator:
            run(["xcrun", "simctl", "terminate", self.identifier, BUNDLE], check=False, quiet=True)
            return
        if DRY_RUN:
            return
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "processes.json"
            run(["xcrun", "devicectl", "device", "info", "processes", "--device", self.identifier,
                 "--json-output", str(out)], capture=True, quiet=True, check=False)
            if not out.exists():
                return
            for process in json.loads(out.read_text())["result"].get("runningProcesses", []):
                if f"/{SCHEME}.app/" in process.get("executable", ""):
                    run(["xcrun", "devicectl", "device", "process", "terminate", "--device", self.identifier,
                         "--pid", str(process["processIdentifier"])], check=False, capture=True)

    def container_files(self, subdirectory: str | None = None) -> list[str]:
        """Relative paths in the app's data container (or one folder of it)."""
        if DRY_RUN:
            return []
        if self.simulator:
            data = Path(run(["xcrun", "simctl", "get_app_container", self.identifier, BUNDLE, "data"],
                            capture=True, quiet=True).stdout.strip())
            base = data / subdirectory if subdirectory else data
            return sorted(str(p.relative_to(base)) for p in base.rglob("*")) if base.exists() else []
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "files.json"
            cmd = ["xcrun", "devicectl", "device", "info", "files", "--device", self.identifier,
                   "--domain-type", "appDataContainer", "--domain-identifier", BUNDLE, "--json-output", str(out)]
            if subdirectory:
                cmd += ["--subdirectory", subdirectory]
            run(cmd, capture=True, quiet=True)
            return sorted(f["relativePath"] for f in json.loads(out.read_text())["result"]["files"])

    def pull(self, relative: str, destination: Path) -> None:
        destination.parent.mkdir(parents=True, exist_ok=True)
        if self.simulator:
            data = Path(run(["xcrun", "simctl", "get_app_container", self.identifier, BUNDLE, "data"],
                            capture=True, quiet=True).stdout.strip())
            if not DRY_RUN:
                shutil.copy2(data / relative, destination)
        else:
            run(["xcrun", "devicectl", "device", "copy", "from", "--device", self.identifier,
                 "--domain-type", "appDataContainer", "--domain-identifier", BUNDLE,
                 "--source", relative, "--destination", str(destination)])

    def wait_for_report(self, prefix: str, before: set[str], timeout: float) -> str | None:
        """Waits until a new Documents file starting with `prefix` appears; returns its name."""
        if DRY_RUN:
            return None
        deadline = time.time() + timeout
        while time.time() < deadline:
            new = [f for f in self.container_files("Documents") if f.startswith(prefix) and f not in before]
            if new:
                time.sleep(1)   # let the app finish writing
                return sorted(new)[-1]
            time.sleep(3)
        return None


def connected_devices() -> dict[str, str]:
    """D1-D3 label → devicectl identifier, for the paired devices that are listed."""
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "devices.json"
        run(["xcrun", "devicectl", "list", "devices", "--json-output", str(out)], capture=True)
        return devices_from_listing(json.loads(out.read_text()))


def devices_from_listing(listing: dict) -> dict[str, str]:
    by_model = {model: label for label, model in DEVICES.items()}
    found = {}
    for device in listing["result"]["devices"]:
        hardware = device.get("hardwareProperties", {})
        label = by_model.get(hardware.get("productType", ""))
        if label and hardware.get("reality", "physical") == "physical":
            found[label] = device["identifier"]
    return found


def target_from_args(args) -> Target:
    if args.simulator:
        return Target("sim", args.simulator, simulator=True)
    if not args.device:
        sys.exit("give --device D1|D2|D3 or --simulator <UDID>")
    if DRY_RUN:
        return Target(args.device, f"<{args.device} identifier>", simulator=False)
    devices = connected_devices()
    if args.device not in devices:
        sys.exit(f"{args.device} ({DEVICES[args.device]}) is not connected and paired; found {sorted(devices)}")
    return Target(args.device, devices[args.device], simulator=False)


def app_path(args, target: Target) -> Path:
    if args.app:
        return Path(args.app)
    sdk = "iphonesimulator" if target.simulator else "iphoneos"
    config = "Debug" if target.simulator else "Release"
    return BUILD / f"Build/Products/{config}-{sdk}/{SCHEME}.app"


# MARK: - Steps

def cmd_build(args) -> None:
    """The measurement build: Release with PROJECTM_AUTOMATION (as for Gate 4)."""
    if not PROJECT.exists():
        run(["xcodegen", "generate"])
    run(["xcodebuild", "-project", str(PROJECT), "-scheme", SCHEME, "-configuration", "Release",
         "-destination", "generic/platform=iOS", "-derivedDataPath", str(BUILD), "-allowProvisioningUpdates",
         "SWIFT_ACTIVE_COMPILATION_CONDITIONS=PROJECTM_AUTOMATION", "build"])


def install(args, target: Target) -> None:
    if args.reinstall:
        target.uninstall()
    target.install(app_path(args, target))


def run_mode(target: Target, mode: str, prefix: str, timeout: float,
             extra: dict[str, str] | None = None) -> Path | None:
    before = set(target.container_files("Documents"))
    target.launch(mode, extra)
    name = target.wait_for_report(prefix, before, timeout)
    target.terminate()
    if not name:
        print(f"!! no {prefix} report within {timeout:.0f} s" + (" (dry run)" if DRY_RUN else ""))
        return None
    dest = target.out_dir / name
    target.pull(f"Documents/{name}", dest)
    print(f"pulled {dest.relative_to(ROOT)}")
    return dest


def launches(target: Target, mode: str, count: int) -> Path:
    """A launch mode (sc015, sc101): `count` recorded launches, then the samples file."""
    target.launch(mode)                              # a fresh install only acknowledges the notice
    time.sleep(0 if DRY_RUN else 8)
    for i in range(count):
        target.launch(mode)
        time.sleep(0 if DRY_RUN else 6)
    dest = target.out_dir / f"{mode}.json"
    target.pull(f"Documents/{mode}.json", dest)
    return dest


def cmd_perf(args) -> None:
    target = target_from_args(args)
    if not args.no_install:
        install(args, target)
    only = set(args.only.split(",")) if args.only else {"sc101", "sc102", "sc104"}
    if "sc101" in only:
        launches(target, "sc101", args.repeat)
    if "sc102" in only:
        run_mode(target, "sc102", "automation-sc102", 120)
    if "sc104" in only:   # 200 picks, 3 s apart: about 15 minutes
        extra = {"PROJECTM_DWELL": str(args.dwell), "PROJECTM_PICKS": str(args.picks)}
        if args.no_prewarm:
            extra["PROJECTM_PREWARM"] = "0"
        run_mode(target, "sc104", "automation-sc104", 600 + args.picks * (args.dwell + 2), extra)
    summarize(target.out_dir)


def cmd_scroll(args) -> None:
    """SC-103: the UI test on the device (Debug build signed with your team)."""
    target = target_from_args(args)
    destination = f"id={target.identifier}" if target.simulator else f"platform=iOS,id={udid_for(target)}"
    log = BUILD / "uitest" / f"{target.label}-sc103.log"   # large; the summary goes to sc103.json
    log.parent.mkdir(parents=True, exist_ok=True)
    result = run(["xcodebuild", "test", "-project", str(PROJECT), "-scheme", SCHEME, "-destination", destination,
                  "-derivedDataPath", str(BUILD / "uitest"), "-allowProvisioningUpdates",
                  "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "180",
                  "-only-testing:projectM-iOSUITests/PresetScrollPerformanceUITests"],
                 check=False, capture=True)
    if not DRY_RUN:
        log.write_text(result.stdout + result.stderr)
        lines = sc103_lines(result.stdout)
        (target.out_dir / "sc103.json").write_text(json.dumps(lines, indent=2) + "\n")
        print("\n".join(f"SC-103 {k}: {v}" for k, v in lines.items()) or "!! no SC103 lines; see " + str(log))
        print("xcodebuild:", "passed" if result.returncode == 0 else f"failed ({result.returncode})")


def udid_for(target: Target) -> str:
    """xcodebuild wants the hardware UDID, devicectl lists its own identifier."""
    if DRY_RUN:
        return "<UDID>"
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "devices.json"
        run(["xcrun", "devicectl", "list", "devices", "--json-output", str(out)], capture=True)
        for device in json.loads(out.read_text())["result"]["devices"]:
            if device["identifier"] == target.identifier:
                return device["hardwareProperties"]["udid"]
    sys.exit("device UDID not found")


def sc103_lines(log: str) -> dict:
    found = {}
    for m in re.finditer(r"SC103 (\S+) frames=(\d+) missed=(\d+) onTime=([\d.]+)", log):
        found[m.group(1)] = {"frames": int(m.group(2)), "missed": int(m.group(3)), "onTime": float(m.group(4))}
    return found


def cmd_entitlement(args) -> None:
    """T239: run after each manual step; the report says unlocked, offline and whether a pack preset plays."""
    target = target_from_args(args)
    steps = [
        ("purchase", "On the device: open projectM, tap a locked preset, Buy, and confirm with the "
                     "sandbox account (Settings › Developer › Sandbox Apple Account)."),
        ("relaunch", None),   # the app is relaunched and reads the unlock back from StoreKit
        ("offline", "Turn on Airplane Mode and turn Wi-Fi off on the device; keep the USB cable "
                    "connected so devicectl can still launch the app."),
        ("restore", "Turn the network back on. The script has reinstalled the app; open projectM, open "
                    "the purchase sheet (tap a locked preset) and tap Restore Purchases."),
    ]
    only = args.step
    for name, instruction in steps:
        if only and name != only:
            continue
        if name == "restore" and not only:
            target.uninstall()
            target.install(app_path(args, target))
        if instruction:
            person(instruction)
        report = run_mode(target, "entitlement", "automation-entitlement", 90)
        if report and not DRY_RUN:
            data = json.loads(report.read_text())
            # The app reads no network state (FR-068); the offline step is the person's Airplane Mode.
            renamed = report.with_name(f"entitlement-{name}-{report.name}")
            report.rename(renamed)
            print(f"{name}: unlocked={data.get('unlocked')} "
                  f"packPresetPlays={data.get('packPresetPlays')} storedUnlockKeys={data.get('storedUnlockKeys')}")


def cmd_privacy(args) -> None:
    """T241: scripted session, then the container listing and the stored keys."""
    target = target_from_args(args)
    if not args.no_install:
        args.reinstall = True
        install(args, target)
    report = run_mode(target, "privacy", "automation-privacy", 120)
    files = target.container_files()
    listing = target.out_dir / "privacy-container.txt"
    listing.parent.mkdir(parents=True, exist_ok=True)
    if not DRY_RUN:
        listing.write_text("\n".join(files) + "\n")
    prefs = f"Library/Preferences/{BUNDLE}.plist"
    target.pull(prefs, target.out_dir / "privacy-preferences.plist")
    if DRY_RUN:
        return
    keys = json.loads(report.read_text())["defaultsKeys"] if report else []
    problems = privacy_problems(files, keys)
    notes = {k: SYSTEM_KEYS[k] for k in keys if k in SYSTEM_KEYS}
    verdict = {"keys": keys, "systemKeys": notes, "problems": problems, "files": len(files)}
    (target.out_dir / "privacy-verdict.json").write_text(json.dumps(verdict, indent=2) + "\n")
    print("privacy:", "zero violations" if not problems else "\n".join(problems))
    for key, why in notes.items():
        print(f"note: {key} is written by {why}")


def privacy_problems(files: list[str], keys: list[str]) -> list[str]:
    """FR-060/FR-065/FR-123: only allowed keys; no files of the app's own besides its reports and,
    since AUD-001-R22, the imported audio library."""
    problems = [f"key not allowed: {k}" for k in sorted(set(keys) - ALLOWED_KEYS - set(SYSTEM_KEYS))]
    for path in files:
        parts = path.split("/")
        if parts[0] in ("Documents", "tmp") and len(parts) > 1:
            if not re.fullmatch(r"(automation-[\w-]+\.json|sc015\.json|sc101\.json|perf009\.json)", parts[-1]):
                problems.append(f"unexpected file: {path}")
        if "/com.apple.metal" in path:   # Metal's shader caches (".pcm" there is a precompiled module)
            continue
        if IMPORTED_AUDIO.fullmatch(path):   # the user's imported library (AUD-001-R22)
            continue
        if path.lower().endswith(AUDIO_SUFFIXES):
            problems.append(f"audio file: {path}")
    return problems


def cmd_size(args) -> None:
    """SC-108: App Thinning Size Reports of the 1.0 archive and a new archive, per device variant."""
    out = EXPORTS / "size"
    old_archive = Path(args.old_archive).expanduser()
    new_archive = BUILD / "projectM-iOS.xcarchive"
    if not args.new_archive:
        run(["xcodebuild", "archive", "-project", str(PROJECT), "-scheme", SCHEME, "-configuration", "Release",
             "-destination", "generic/platform=iOS", "-archivePath", str(new_archive), "-allowProvisioningUpdates"])
    else:
        new_archive = Path(args.new_archive).expanduser()
    options = out / "ExportOptions.plist"
    out.mkdir(parents=True, exist_ok=True)
    options.write_text(EXPORT_OPTIONS)
    reports = {}
    for name, archive in (("1.0", old_archive), ("new", new_archive)):
        dest = BUILD / "size" / name   # the exported .ipa files stay out of the repository
        run(["xcodebuild", "-exportArchive", "-archivePath", str(archive), "-exportPath", str(dest),
             "-exportOptionsPlist", str(options), "-allowProvisioningUpdates"])
        if not DRY_RUN:
            report = dest / "App Thinning Size Report.txt"
            shutil.copy2(report, out / f"thinning-{name}.txt")
            reports[name] = parse_thinning_report(report.read_text())
    if DRY_RUN:
        return
    result = size_growth(reports["1.0"], reports["new"])
    (out / "sc108.json").write_text(json.dumps(result, indent=2) + "\n")
    for model, row in result.items():
        print(f"SC-108 {model}: {row['oldMB']:.1f} MB → {row['newMB']:.1f} MB (+{row['growthMB']:.1f} MB), "
              f"{'pass' if row['growthMB'] <= 40 else 'FAIL'}")


EXPORT_OPTIONS = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>debugging</string>
    <key>thinning</key>
    <string>&lt;thin-for-all-variants&gt;</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
"""


def parse_thinning_report(text: str) -> dict[str, float]:
    """Device model → uncompressed app size in MB, from Xcode's App Thinning Size Report."""
    sizes: dict[str, float] = {}
    for block in re.split(r"\n(?=Variant: )", text):
        models = re.findall(r"device: ([A-Za-z]+\d+,\d+)", block)
        m = re.search(r"App size: ([\d.]+) (KB|MB|GB) compressed, ([\d.]+) (KB|MB|GB) uncompressed", block)
        if not m:
            continue
        mb = float(m.group(3)) * {"KB": 1 / 1000, "MB": 1, "GB": 1000}[m.group(4)]
        for model in models:
            sizes[model] = mb
    return sizes


def size_growth(old: dict[str, float], new: dict[str, float]) -> dict:
    rows = {}
    for label, model in DEVICES.items():
        if model in old and model in new:
            rows[f"{label} {model}"] = {"oldMB": old[model], "newMB": new[model], "growthMB": new[model] - old[model]}
    return rows


# MARK: - Verdicts

def summarize(directory: Path | None = None) -> dict:
    """Reads every pulled report and prints each criterion against its target."""
    dirs = [directory] if directory else sorted(p for p in EXPORTS.glob("*") if p.is_dir() and p.name != "size")
    verdicts = {}
    for d in dirs:
        verdicts[d.name] = verdicts_for(d)
        for sc, (ok, detail) in verdicts[d.name].items():
            print(f"{d.name} {sc}: {'pass' if ok else 'FAIL'} — {detail}")
    size = EXPORTS / "size/sc108.json"
    if size.exists():
        for model, row in json.loads(size.read_text()).items():
            print(f"{model} SC-108: {'pass' if row['growthMB'] <= 40 else 'FAIL'} — +{row['growthMB']:.1f} MB")
    return verdicts


def latest(d: Path, prefix: str) -> dict | None:
    files = sorted(d.glob(f"{prefix}*.json"))
    return json.loads(files[-1].read_text()) if files else None


def verdicts_for(d: Path) -> dict[str, tuple[bool, str]]:
    out: dict[str, tuple[bool, str]] = {}
    if (d / "sc101.json").exists():
        samples = json.loads((d / "sc101.json").read_text())
        worst = max(samples) if samples else float("inf")
        out["SC-101"] = (bool(samples) and worst <= 0.15, f"{len(samples)} launches, max {worst * 1000:.0f} ms (target 150 ms)")
    if (r := latest(d, "automation-sc102")) and "maxMs" in r:
        out["SC-102"] = (r["maxMs"] <= 50, f"{r['keystrokes']} keystrokes, median {r['medianMs']:.1f} ms, max {r['maxMs']:.1f} ms (target 50 ms; search only)")
    sc104 = [json.loads(f.read_text()) for f in sorted(d.glob("automation-sc104*.json"))]
    shipping = [r for r in sc104 if r.get("prewarm", True)]   # warm-up off runs are comparisons only
    if (r := (shipping or sc104 or [None])[-1]) and "fractionUnder1s" in r:
        warm = "" if "prewarm" not in r else f", warm-up {'on' if r['prewarm'] else 'off'}"
        if "dwellFpsMean" in r:
            warm += f", dwell {r['dwellFpsMean']:.1f} fps mean, {r['dwellFractionAtLeast55']:.0%} of 1 s windows ≥ 55 fps"
        out["SC-104"] = (r["fractionUnder1s"] >= 0.95, f"{r['fractionUnder1s']:.0%} under 1 s, p95 {r['p95Ms']:.0f} ms{warm}, packs {r['picksByPack']}")
    if (d / "sc103.json").exists():
        for name, row in json.loads((d / "sc103.json").read_text()).items():
            out[f"SC-103 {name}"] = (row["onTime"] >= 0.95, f"{row['onTime']:.1%} on time ({row['frames']} frames, {row['missed']} missed)")
    return out


# MARK: - PERF-009 startup warm cache (cold and warm launches)

def warmstart_summary(samples: list[dict], simulator: bool) -> dict:
    """Median of each timing per label (cold/warm) and the cache outcomes seen (PERF-009-R10)."""
    summary: dict = {"evidence": not simulator}
    for label in ("cold", "warm"):
        rows = [s for s in samples if s.get("cache") == label]
        entry: dict = {"launches": len(rows),
                       "libraryOutcomes": sorted({str(s.get("libraryOutcome")) for s in rows})}
        for field in ("chooserMs", "libraryReadyMs", "libraryLoadMs"):
            values = [float(s[field]) for s in rows if isinstance(s.get(field), (int, float)) and s[field] >= 0]
            entry[field] = round(statistics.median(values), 1) if values else None
        summary[label] = entry
    return summary


def cmd_warmstart(args) -> None:
    """PERF-009: `repeat` cold launches (cache cleared first) alternating with `repeat` warm ones, then a summary.
    A simulator rehearsal is never evidence."""
    target = target_from_args(args)
    if not args.no_install:
        install(args, target)
    target.launch("perf009")                          # a fresh install only acknowledges the notice
    time.sleep(0 if DRY_RUN else 8)
    for _ in range(args.repeat):
        for extra in ({"PROJECTM_WARMCACHE": "cold"}, None):
            target.launch("perf009", extra)
            time.sleep(0 if DRY_RUN else 6)
    dest = target.out_dir / "perf009.json"
    target.pull("Documents/perf009.json", dest)
    if DRY_RUN or not dest.exists():
        return
    summary = warmstart_summary(json.loads(dest.read_text()), target.simulator)
    (target.out_dir / "perf009-summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    note = "" if summary["evidence"] else " (simulator: not evidence)"
    for label in ("cold", "warm"):
        row = summary[label]
        print(f"{target.label} PERF-009 {label}{note}: {row['launches']} launches, library {row['libraryOutcomes']}, "
              f"chooser {row['chooserMs']} ms, library ready {row['libraryReadyMs']} ms, load {row['libraryLoadMs']} ms")


# MARK: - QA-010 performance budgets (on demand, final device stage)

def threshold_inputs(d: Path, extra: list[Path]) -> list[Path]:
    """The newest perf001 report, sc015.json and newest PERF-012 export in `d`, plus the named files."""
    chosen = []
    for pattern in ("automation-perf001-*.json", "performance-*.json"):
        files = sorted(p for p in d.glob(pattern) if p.name != "performance-verdict.json")
        if files:
            chosen.append(files[-1])
    if (d / "sc015.json").exists():
        chosen.append(d / "sc015.json")
    return chosen + [Path(p) for p in extra]


def judge_thresholds(d: Path, *, label: str, simulator: bool, extra: list[Path] | None = None,
                     pinned: int | None = None, write: bool = True) -> dict:
    """Judges the files in `d` against the budgets and writes performance-verdict.json there (QA-010-R9;
    not in a dry run)."""
    inputs = threshold_inputs(d, extra or [])
    if not inputs:
        verdict = cpt.error_verdict(f"no reports in {d.name}", None, [])
    else:
        verdict = cpt.check(inputs, pinned=pinned, simulator=simulator,
                            model=None if simulator else DEVICES.get(label))
    if write:
        d.mkdir(parents=True, exist_ok=True)
        (d / "performance-verdict.json").write_text(cpt.render_json(verdict), encoding="utf-8")
    print(cpt.render_text(verdict), end="")
    return verdict


def cmd_thresholds(args) -> int:
    target = target_from_args(args)
    if args.run:
        if not args.no_install:
            install(args, target)
        run_mode(target, "perf001", "automation-perf001", 120)
        launches(target, "sc015", args.repeat)
    verdict = judge_thresholds(target.out_dir, label=target.label, simulator=target.simulator,
                               extra=args.report, pinned=args.thresholds_version, write=not DRY_RUN)
    return cpt.exit_code(verdict)


def main(argv: list[str] | None = None) -> int:
    global DRY_RUN
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("devices")
    sub.add_parser("build")
    sub.add_parser("summarize")
    for name in ("perf", "scroll", "entitlement", "privacy", "install", "warmstart"):
        p = sub.add_parser(name)
        p.add_argument("--device", choices=sorted(DEVICES))
        p.add_argument("--simulator", metavar="UDID")
        p.add_argument("--app", help="the .app to install (default: the build step's output)")
        p.add_argument("--reinstall", action="store_true", help="remove the app first (an empty container)")
        p.add_argument("--no-install", action="store_true")
        p.add_argument("--repeat", type=int, default=10, help="recorded launches for SC-101 (warmstart: per label)")
        p.add_argument("--only", help="perf: a comma-separated subset of sc101,sc102,sc104")
        p.add_argument("--no-prewarm", action="store_true", help="perf: SC-104 with the preset warm-up off (comparison)")
        p.add_argument("--dwell", type=int, default=3, help="perf: seconds on each preset in SC-104")
        p.add_argument("--picks", type=int, default=200, help="perf: Random picks in SC-104")
        p.add_argument("--step", choices=["purchase", "relaunch", "offline", "restore"], help="entitlement: one step only")
    budgets = sub.add_parser("thresholds", help="QA-010: judge reports against docs/performance/thresholds.json")
    budgets.add_argument("--device", choices=sorted(DEVICES))
    budgets.add_argument("--simulator", metavar="UDID")
    budgets.add_argument("--app", help="the .app to install (default: the build step's output)")
    budgets.add_argument("--reinstall", action="store_true")
    budgets.add_argument("--no-install", action="store_true")
    budgets.add_argument("--run", action="store_true", help="run perf001 and sc015 first and pull their reports")
    budgets.add_argument("--repeat", type=int, default=10, help="recorded sc015 launches")
    budgets.add_argument("--report", type=Path, action="append", default=[], help="an exported PERF-012 report")
    budgets.add_argument("--thresholds-version", type=int, help="refuse any other thresholds version")
    size = sub.add_parser("size")
    size.add_argument("--old-archive", default="~/Library/Developer/Xcode/Archives/2026-11-10/ProjectMiOS 1.0 (1).xcarchive")
    size.add_argument("--new-archive", help="an existing archive instead of archiving now")
    args = parser.parse_args(argv)
    DRY_RUN = args.dry_run

    if args.command == "devices":
        found = {} if DRY_RUN else connected_devices()
        for label, model in DEVICES.items():
            print(f"{label} {model}: {found.get(label, 'not connected')}")
    elif args.command == "build":
        cmd_build(args)
    elif args.command == "install":
        install(args, target_from_args(args))
    elif args.command == "perf":
        cmd_perf(args)
    elif args.command == "warmstart":
        cmd_warmstart(args)
    elif args.command == "scroll":
        cmd_scroll(args)
    elif args.command == "entitlement":
        cmd_entitlement(args)
    elif args.command == "privacy":
        cmd_privacy(args)
    elif args.command == "size":
        cmd_size(args)
    elif args.command == "summarize":
        summarize()
    elif args.command == "thresholds":
        return cmd_thresholds(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
