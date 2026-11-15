#!/usr/bin/env python3
"""QA-011: run the final physical device matrix on D1-D3 (or rehearse it on a simulator) and write a signed,
hashed run record per device (specs/313-qa-011-final-device-matrix).

    python3 scripts/run_device_matrix.py --device D1 --dry-run         # print every command; writes nothing
    python3 scripts/run_device_matrix.py --device D1 [--build]         # the device run (owner present, unlocked)
    python3 scripts/run_device_matrix.py --device all                  # D1, D2, D3 in turn
    python3 scripts/run_device_matrix.py --simulator <udid> --app <Debug simulator .app>   # rehearsal, not evidence
    python3 scripts/run_device_matrix.py verify docs/test-reports/qa-011/runs/D1/<run-id>/record.json
    python3 scripts/run_device_tests.py matrix --device D1             # the same, through the device runner

The cases (CASES) are the category (a) work of docs/test-reports/qa-011/device-inventory.json: AutomationRunner
modes, launch modes, the QA-010 threshold judge, and on-device XCTest suites and benches. Each case runs on the
devices of the tasks it closes (read from the inventory). Order: one fresh install of the measurement build, the
app's automation cases, package XCTest, and last the app-hosted XCTest suite (it replaces the installed app).

The record (docs/test-reports/qa-011/runs/<label>/<run-id>/record.json, contract in the spec's
contracts/run-record.md) carries the device model, OS version and build, the app's version, build and commit, the
code signature's identity and team as `codesign -dv` reports them, every case's status, commands and artifacts with
SHA-256 hashes, and its own hash (also in record.json.sha256). Small JSON reports are copied next to the record
(committed); xcresult bundles and logs stay under --work-dir (default Build/qa-011, gitignored).

Never changes signing: package suites use Configs/Signing.xcconfig, which only includes the owner's gitignored
local file. A simulator rehearsal is never evidence (Constitution X).
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_device_tests as rdt  # noqa: E402
import check_performance_thresholds as cpt  # noqa: E402

ROOT = rdt.ROOT
RUNS = ROOT / "docs/test-reports/qa-011/runs"
INVENTORY = ROOT / "docs/test-reports/qa-011/device-inventory.json"
SIGNING_XCCONFIG = ROOT / "Configs/Signing.xcconfig"
RECORD_KIND = "projectM-iOS.qa011.deviceRun"
LABELS = ("D1", "D2", "D3")
STATUSES = ("pass", "fail", "timeout", "blocked", "error", "skipped", "not-run")
LOCK_RE = re.compile(r"(?i)(device is locked|is locked|passcode[- ]protected|unlock (?:the|your|this) device|"
                     r"\bLocked\b)")
COMMIT_LIMIT = 1_000_000   # pulled reports up to this size are copied next to the record (committed)


def case(id: str, kind: str, title: str, closes: list[str], timeout: int, **params) -> dict:
    return {"id": id, "kind": kind, "title": title, "closes": closes, "timeoutSeconds": timeout, **params}


# In run order. `closes`: the tasks the case fully closes (category a); `partOf`: tasks of which it scripts a part.
CASES: list[dict] = [
    case("autorun-perf001", "autorun", "AutomationRunner perf001: per-stage frame timings, 1 s frame-rate windows, "
         "PERF-007 drops", ["PERF-001-T16", "PERF-002-T13", "QA-010-T12"], 300, mode="perf001",
         prefix="automation-perf001", wait=240),
    case("launches-sc015", "launches", "sc015 cold launches (10 recorded) for the QA-010 launch budget",
         ["QA-010-T12"], 400, mode="sc015", repeat=10),
    case("warmstart-perf009", "warmstart", "PERF-009 cold and warm launches (10 each), medians",
         ["PERF-009-T16"], 600, repeat=10),
    case("autorun-sc009", "autorun", "AutomationRunner sc009: In-App Playback and Microphone lifecycle scripts",
         ["AUD-014-T32"], 600, mode="sc009", prefix="automation-sc009", wait=540, permission="microphone"),
    case("autorun-perf012", "autorun", "AutomationRunner perf012: a 1-minute overlay session, then the PERF-012 "
         "report (frame-interval percentiles, peak memory, audio age) for the QA-010 judge", [], 300,
         partOf=["QA-010-T12"], mode="perf012", prefix="performance-perf012", wait=180),
    case("thresholds", "thresholds", "QA-010 judge over the pulled perf001 and sc015 reports (plus any PERF-012 "
         "export given with --perf012-report)", ["QA-010-T12"], 120),
    case("xctest-goldens", "xctest", "RenderGoldens suite on the device GPU (goldens report pending without a "
         "device golden class; short soak included)", ["QA-003-T17"], 900, package="RenderGoldens"),
    case("xctest-soak-600", "xctest", "QA-006 long scene soak, 600 s simulated", ["QA-006-T13"], 1200,
         package="RenderGoldens", only=["RenderGoldensTests/RenderSoakTests/testOnDemandLongSoak"],
         env={"QA006_SOAK_SECONDS": "600"}),
    case("xctest-materials", "xctest", "SHD-004 material variants on the device GPU family (Detailed needs "
         "family 9; Standard fallback with the notice)", ["SHD-004-T20"], 900, package="Compositor",
         only=["ProceduralMaterialsTests/MaterialVariantSwitchTests"]),
    case("xctest-angle-layer", "xctest", "CMP-001 ProjectMLayerTests and the client-buffer spike tests on the "
         "device", [], 900, partOf=["CMP-001-T20"], package="ANGLERendering",
         only=["ANGLERenderingTests/ProjectMLayerTests", "ANGLERenderingTests/ClientBufferSpikeTests"]),
    case("bench-shd002", "xctest", "SHD-002 12-node graph GPU cost (SHD002_BENCH)", ["SHD-002-T24"], 900,
         package="Compositor", only=["GeneratorGraphTests/GraphCostBench"], env={"SHD002_BENCH": "1"},
         configuration="Release"),
    case("bench-cmp008", "xctest", "CMP-008 full-screen gradient layer GPU time (CMP008_BENCH)", ["CMP-008-T19"],
         900, package="Compositor", only=["CompositorTests/LayerGradientCompositeTests/testGradientGPUTimeBench"],
         env={"CMP008_BENCH": "1"}, configuration="Release"),
    case("bench-cmp009", "xctest", "CMP-009 full-screen luma-keyed layer GPU time (CMP009_BENCH)", ["CMP-009-T19"],
         900, package="Compositor", only=["CompositorTests/LayerLumaKeyCompositeTests/testLumaKeyGPUTimeBench"],
         env={"CMP009_BENCH": "1"}, configuration="Release"),
    case("bench-cmp010", "xctest", "CMP-010 full-screen colour-keyed layer GPU time (CMP010_BENCH)",
         ["CMP-010-T19"], 900, package="Compositor",
         only=["CompositorTests/LayerColorKeyCompositeTests/testColorKeyGPUTimeBench"],
         env={"CMP010_BENCH": "1"}, configuration="Release"),
    case("bench-expression", "xctest", "SHD-010 per-frame expression cost, Release (PARAMETER_EXPRESSION_BENCH)",
         ["SHD-010-T13"], 900, package="ParameterGraph",
         only=["ParameterExpressionTests/ExpressionCompileWorkTests/testInformationalHostCost"],
         env={"PARAMETER_EXPRESSION_BENCH": "1"}, configuration="Release"),
    case("xctest-offline-export", "xctest", "REC-013 two offline exports of the fixture match frame checksums "
         "(app-hosted; replaces the installed app, so it runs last)", ["REC-013-T14"], 900, app=True,
         only=["projectM-iOSTests/OfflineExportAcceptanceTests"]),
]
CASE_IDS = [c["id"] for c in CASES]
DEFAULT_DEVICES = {"autorun-perf001": LABELS, "launches-sc015": LABELS, "thresholds": LABELS}


# MARK: - Which cases run where (from the inventory)

def case_devices(inventory: dict | None) -> dict[str, list[str]]:
    """Case id → sorted devices: the union of the devices of the open or optional tasks that list the case."""
    out: dict[str, set[str]] = {c["id"]: set(DEFAULT_DEVICES.get(c["id"], ())) for c in CASES}
    for task in (inventory or {}).get("tasks", []):
        if task.get("status") == "waived":
            continue
        for cid in task.get("matrixCases", []):
            if cid in out:
                out[cid].update(task.get("devices", []))
    if not inventory:   # no inventory: every case on D1 (the reference device) at least
        for cid, devices in out.items():
            devices.add("D1")
    return {cid: sorted(devices) for cid, devices in out.items()}


def load_inventory(path: Path = INVENTORY) -> dict | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def plan(label: str | None, devices_by_case: dict[str, list[str]], only: set[str] | None = None) -> list[dict]:
    """The cases for one device (label None: a rehearsal runs every case), in run order."""
    chosen = []
    for c in CASES:
        if only and c["id"] not in only:
            continue
        if label is None or label in devices_by_case.get(c["id"], []):
            chosen.append(c)
    return chosen


# MARK: - Hashing and the record

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def sha256_path(path: Path) -> str:
    """A file's SHA-256, or for a folder the SHA-256 of its sorted `relpath NUL sha256 LF` lines."""
    if path.is_file():
        return sha256_file(path)
    lines = []
    for p in sorted(q for q in path.rglob("*") if q.is_file()):
        lines.append(f"{p.relative_to(path).as_posix()}\0{sha256_file(p)}\n")
    return hashlib.sha256("".join(lines).encode("utf-8")).hexdigest()


def path_bytes(path: Path) -> int:
    if path.is_file():
        return path.stat().st_size
    return sum(p.stat().st_size for p in path.rglob("*") if p.is_file())


def display_path(path: Path) -> str:
    """Repository-relative when inside the repository (symlinks not resolved), else absolute."""
    try:
        return path.absolute().relative_to(ROOT).as_posix()
    except ValueError:
        return str(path.absolute())


def artifact(path: Path, committed: bool) -> dict:
    return {"path": display_path(path), "kind": "folder" if path.is_dir() else "file", "bytes": path_bytes(path),
            "sha256": sha256_path(path), "committed": committed}


def canonical(record: dict) -> str:
    return json.dumps(record, sort_keys=True, indent=2, ensure_ascii=False) + "\n"


def record_hash(record: dict) -> str:
    body = {k: v for k, v in record.items() if k != "recordSha256"}
    return hashlib.sha256(canonical(body).encode("utf-8")).hexdigest()


def summarize_cases(cases: list[dict]) -> dict[str, int]:
    counts = {s: 0 for s in STATUSES}
    for c in cases:
        counts[c["status"]] = counts.get(c["status"], 0) + 1
    return counts


def relative_paths(record: dict) -> dict:
    """Paths inside the repository are written relative to it: the records are public and the checkout's absolute
    path names the Mac's user (owner ruling 2026-11-15)."""
    text = json.dumps(record, ensure_ascii=False)
    root = str(ROOT)
    text = text.replace(root + "/", "").replace(root, ".")
    return json.loads(text)


def write_record(record: dict, directory: Path) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    clean = relative_paths(record)
    record.clear()
    record.update(clean)
    record["summary"] = summarize_cases(record["cases"])
    record["recordSha256"] = record_hash(record)
    path = directory / "record.json"
    path.write_text(canonical(record), encoding="utf-8")
    (directory / "record.json.sha256").write_text(f"{record['recordSha256']}  record.json\n", encoding="utf-8")
    (directory / "record.md").write_text(render_markdown(record), encoding="utf-8")
    return path


def render_markdown(record: dict) -> str:
    t, app, s = record["target"], record["app"], record["signing"]
    lines = [f"# QA-011 device run {record['label']} {record['runId']}", ""]
    if not record["evidence"]:
        lines += [f"**{record['evidenceNote'].upper()}.** Nothing here is device evidence (Constitution X).", ""]
    lines += [
        f"- Target: {t.get('kind')} {t.get('name')} `{t.get('productType')}`, OS {t.get('osVersion')} "
        f"({t.get('osBuild')}), state {t.get('state')}",
        f"- App: `{app.get('bundleID')}` {app.get('version')} ({app.get('build')}), {app.get('configuration')}, "
        f"commit `{app.get('commit')}`{' (dirty tree)' if app.get('dirty') else ''}",
        f"- Signing: {s.get('identity') or s.get('note') or 'not signed'}; team {s.get('team') or '-'}"
        f"{'; ad hoc' if s.get('adhoc') else ''}",
        f"- Host: {record['host'].get('xcode')}, macOS {record['host'].get('macOS')}",
        f"- Started {record['startedAt']}, finished {record['finishedAt']}"
        + (f"; stopped: {record['stopReason']}" if record.get("stopReason") else ""),
        f"- Summary: " + ", ".join(f"{k} {v}" for k, v in record["summary"].items() if v),
        f"- Record SHA-256: `{record['recordSha256']}`", "",
        "| Case | Status | Seconds | Closes | Detail |", "|---|---|---|---|---|"]
    for c in record["cases"]:
        closes = ", ".join(c.get("closes", []) + [f"part of {x}" for x in c.get("partOf", [])])
        detail = (c.get("detail") or "").replace("|", "/").replace("\n", " ")[:300]
        lines.append(f"| `{c['id']}` | {c['status']} | {c.get('durationSeconds', 0):.1f} | {closes} | {detail} |")
    lines += ["", "## Artifacts", "", "| Case | Path | Bytes | SHA-256 | Committed |", "|---|---|---|---|---|"]
    for c in record["cases"]:
        for a in c.get("artifacts", []):
            lines.append(f"| `{c['id']}` | `{a['path']}` | {a['bytes']} | `{a['sha256']}` | "
                         f"{'yes' if a['committed'] else 'no'} |")
    return "\n".join(lines) + "\n"


def verify_record(path: Path) -> list[str]:
    """Problems with a record: a wrong record hash, or a committed artifact missing or changed. Artifacts kept
    outside the repository (xcresults) are not checked: they are local working files, not committed evidence."""
    record = json.loads(path.read_text(encoding="utf-8"))
    problems = []
    if record.get("recordSha256") != record_hash(record):
        problems.append("record hash does not match its content")
    sidecar = path.with_name("record.json.sha256")
    if sidecar.exists() and sidecar.read_text(encoding="utf-8").split()[0] != record.get("recordSha256"):
        problems.append("record.json.sha256 does not match the record")
    for c in record.get("cases", []):
        for a in c.get("artifacts", []):
            p = Path(a["path"]) if Path(a["path"]).is_absolute() else ROOT / a["path"]
            if not p.exists():
                if a.get("committed"):
                    problems.append(f"missing artifact {a['path']}")
                continue
            if sha256_path(p) != a["sha256"] and a.get("committed"):
                problems.append(f"artifact changed: {a['path']}")
            # An uncommitted artifact (an xcresult under Build/) is not evidence that can be checked later: Xcode
            # keeps rewriting a result bundle's database after the run, so its folder hash drifts (D1, 2026-11-15).
    return problems


# MARK: - Target, app and signing facts

def device_entry(listing: dict, label: str) -> dict | None:
    model = rdt.DEVICES[label]
    for device in listing.get("result", {}).get("devices", []):
        hw = device.get("hardwareProperties", {})
        if hw.get("productType") == model and hw.get("reality", "physical") == "physical":
            return device
    return None


def device_facts(device: dict | None) -> dict:
    if not device:
        return {"kind": "device", "state": "not listed"}
    hw, dp = device.get("hardwareProperties", {}), device.get("deviceProperties", {})
    state = device.get("connectionProperties", {}).get("tunnelState", "unknown")
    return {"kind": "device", "identifier": device.get("identifier"), "udid": hw.get("udid"),
            "name": dp.get("name"), "productType": hw.get("productType"), "osVersion": dp.get("osVersionNumber"),
            "osBuild": dp.get("osBuildUpdate"), "state": state}


def simulator_facts(devices_json: dict, runtimes_json: dict, udid: str) -> dict:
    builds = {r.get("identifier"): r for r in runtimes_json.get("runtimes", [])}
    for runtime, devices in devices_json.get("devices", {}).items():
        for d in devices:
            if d.get("udid") == udid:
                r = builds.get(runtime, {})
                return {"kind": "simulator", "identifier": udid, "udid": udid, "name": d.get("name"),
                        "productType": d.get("deviceTypeIdentifier", "").rsplit(".", 1)[-1],
                        "osVersion": r.get("version"), "osBuild": r.get("buildversion"),
                        "state": d.get("state", "unknown").lower()}
    return {"kind": "simulator", "identifier": udid, "udid": udid, "state": "not listed"}


def parse_codesign(text: str) -> dict:
    """`codesign -dv --verbose=4` output (stderr) → signed, identity (first Authority), team, adhoc."""
    if "not signed at all" in text:
        return {"signed": False, "identity": None, "team": None, "adhoc": False, "raw": ["code object is not signed at all"]}
    authorities = re.findall(r"^Authority=(.+)$", text, re.M)
    team = re.search(r"^TeamIdentifier=(.+)$", text, re.M)
    adhoc = bool(re.search(r"^Signature=adhoc$", text, re.M))
    team_value = team.group(1).strip() if team else None
    if team_value == "not set":
        team_value = None
    raw = [line for line in text.splitlines() if line.startswith(("Authority=", "TeamIdentifier=", "Signature="))]
    return redact_signing({"signed": bool(authorities) or adhoc, "identity": authorities[0] if authorities else None,
                           "team": team_value, "adhoc": adhoc, "raw": raw})


# Owner ruling 2026-11-15: records are public, so a signing identity keeps only the certificate type and the team ID.
# The certificate's holder name and personal certificate ID ("Apple Development: NAME (ABCDE12345)") are dropped.
REDACTION_NOTE = "certificate holder name and certificate ID withheld; team ID kept (owner ruling 2026-11-15)"


def redact_identity(value: str | None) -> str | None:
    """'Apple Development: NAME (ID)' → 'Apple Development'; Apple's own CA names are kept."""
    if value is None:
        return None
    kind, sep, _ = value.partition(":")
    return kind.strip() if sep else value


def redact_signing(signing: dict) -> dict:
    out = dict(signing)
    out["identity"] = redact_identity(signing.get("identity"))
    raw = []
    for line in signing.get("raw", []):
        if line.startswith("Authority="):
            raw.append("Authority=" + redact_identity(line[len("Authority="):]))
        else:
            raw.append(line)
    out["raw"] = raw
    if out["identity"] != signing.get("identity"):
        out["redaction"] = REDACTION_NOTE
    return out


def redact_record_file(path: Path) -> bool:
    """Rewrite a committed-to-be record with its signing identity redacted; a new record hash. True if changed."""
    record = json.loads(path.read_text(encoding="utf-8"))
    before = canonical(record)
    record["signing"] = redact_signing(record.get("signing") or {})
    record = relative_paths(record)
    if canonical(record) == before:
        return False
    write_record(record, path.parent)
    return True


def capture(cmd: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess:
    """Run for facts only; a missing tool (xcodebuild, codesign and xcrun on Linux CI) gives an empty result."""
    try:
        return subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, check=False)
    except FileNotFoundError:
        return subprocess.CompletedProcess(cmd, 127, stdout="", stderr=f"{cmd[0]}: not found")


def app_facts(app: Path, configuration: str) -> dict:
    facts = {"bundleID": rdt.BUNDLE, "path": display_path(app), "configuration": configuration,
             "commit": capture(["git", "rev-parse", "HEAD"], ROOT).stdout.strip(),
             "dirty": bool(capture(["git", "status", "--porcelain", "--untracked-files=no"], ROOT).stdout.strip())}
    plist = app / "Info.plist"
    for key, field in (("CFBundleShortVersionString", "version"), ("CFBundleVersion", "build"),
                       ("CFBundleIdentifier", "bundleID")):
        out = capture(["plutil", "-extract", key, "raw", "-o", "-", str(plist)]) if plist.exists() else None
        if out and out.returncode == 0:
            facts[field] = out.stdout.strip()
        elif field != "bundleID":
            facts[field] = None
    return facts


def signing_facts(app: Path) -> dict:
    if not app.exists():
        return {"signed": False, "identity": None, "team": None, "adhoc": False, "raw": [],
                "note": f"app not found: {display_path(app)}"}
    out = capture(["codesign", "-dv", "--verbose=4", str(app)])
    return parse_codesign(out.stderr + out.stdout)


def host_facts() -> dict:
    xcode = capture(["xcodebuild", "-version"]).stdout.strip().replace("\n", " ")
    return {"xcode": xcode or None, "macOS": platform.mac_ver()[0] or None}


# MARK: - Running cases

class MatrixTarget(rdt.Target):
    """run_device_tests' Target, with pulled reports going next to the run record."""

    def __init__(self, label: str, identifier: str, simulator: bool, out_dir: Path, udid: str | None):
        super().__init__(label, identifier, simulator)
        self._out_dir, self.udid = out_dir, udid

    @property
    def out_dir(self) -> Path:
        return self._out_dir

    @property
    def destination(self) -> str:
        return f"id={self.identifier}" if self.simulator else f"platform=iOS,id={self.udid or '<UDID>'}"


class Blocked(Exception):
    """The device stayed locked past --locked-wait."""


class NoDeviceHost(Exception):
    """A package suite with no app-hosted twin in DeviceTests.yml: it cannot run on a device yet."""


# Xcode cannot run a package's own test target on a device ("Tool-hosted testing is unavailable on device
# destinations"; D1, 2026-11-15). On a device, package suites run from DeviceTests.yml: the same sources compiled
# into bundles hosted in the signed app. A package test bundle without a twin there cannot run on a device yet.
DEVICE_TEST_SPEC = ROOT / "DeviceTests.yml"
DEVICE_TEST_PROJECT = ROOT / "ProjectM-DeviceTests.xcodeproj"
DEVICE_TEST_SCHEME = "DeviceTests"
DEVICE_TEST_BUNDLES = {
    "CompositorTests": "CompositorDeviceTests",
    "ProceduralMaterialsTests": "MaterialsDeviceTests",
    "GeneratorGraphTests": "GeneratorGraphDeviceTests",
    "ParameterExpressionTests": "ExpressionDeviceTests",
    "RenderGoldensTests": "RenderGoldensDeviceTests",
    "ANGLERenderingTests": "ANGLEDeviceTests",
}


PACKAGE_DEVICE_BUNDLES = {"RenderGoldens": ["RenderGoldensDeviceTests"], "ParameterGraph": ["ExpressionDeviceTests"]}


def device_only_testing(only: list[str], package: str | None = None) -> list[str] | None:
    """The device-hosted `-only-testing` ids, or None when a bundle has no device host. A case without `only` runs
    its package's bundles, never the whole scheme (D1, 2026-11-15: an unfiltered case ran every bundle)."""
    if not only:
        return PACKAGE_DEVICE_BUNDLES.get(package or "")
    out = []
    for o in only:
        bundle, _, rest = o.partition("/")
        if bundle not in DEVICE_TEST_BUNDLES:
            return None
        out.append(DEVICE_TEST_BUNDLES[bundle] + ("/" + rest if rest else ""))
    return out


def xctest_command(c: dict, target: MatrixTarget, derived: Path, bundle: Path) -> tuple[list[str], Path]:
    only = list(c.get("only", []))
    hosted = not c.get("app") and not target.simulator
    if c.get("app"):
        cmd, cwd = ["xcodebuild", "test", "-project", str(rdt.PROJECT), "-scheme", rdt.SCHEME], ROOT
    elif hosted:
        mapped = device_only_testing(only, c.get("package"))
        if mapped is None:
            raise NoDeviceHost(f"{', '.join(only)}: no app-hosted device bundle (DeviceTests.yml)")
        only = mapped
        cmd, cwd = ["xcodebuild", "test", "-project", str(DEVICE_TEST_PROJECT), "-scheme", DEVICE_TEST_SCHEME], ROOT
    else:
        cmd, cwd = ["xcodebuild", "test", "-scheme", c["package"]], ROOT / "Packages" / c["package"]
    cmd += ["-destination", target.destination,
            "-derivedDataPath", str(derived / ("device-tests" if hosted else (c.get("package") or "app"))),
            "-resultBundlePath", str(bundle), "-test-timeouts-enabled", "YES",
            "-default-test-execution-time-allowance", str(c["timeoutSeconds"])]
    if c.get("configuration") or hosted:
        cmd += ["-configuration", c.get("configuration") or "Debug", "ENABLE_TESTABILITY=YES"]
    for o in only:
        cmd.append(f"-only-testing:{o}")
    if target.simulator:
        cmd.append("CODE_SIGNING_ALLOWED=NO")
    else:
        cmd.append("-allowProvisioningUpdates")
        if not c.get("app") and not hosted:
            cmd += ["-xcconfig", str(SIGNING_XCCONFIG)]   # the owner's team via the include-only file
    return cmd, cwd


def test_counts(log: str) -> str:
    found = re.findall(r"Executed (\d+) tests?, with (?:\d+ tests? skipped and )?(\d+) failures?(?: \((\d+) unexpected\))?", log)
    skipped = len(re.findall(r"Test Case .* skipped", log))
    if not found:
        return "no test summary in the log"
    n, f, _ = max(found, key=lambda t: int(t[0]))   # the whole run's total, not the last sub-suite (D1, 2026-11-15)
    return f"{n} tests, {f} failures, {skipped} skipped"


def is_locked(text: str) -> bool:
    return bool(LOCK_RE.search(text)) and "Executed " not in text


class Runner:
    def __init__(self, target: MatrixTarget, work: Path, locked_wait: float, perf012: list[Path],
                 dry_run: bool):
        self.target, self.work, self.locked_wait, self.perf012, self.dry_run = target, work, locked_wait, perf012, dry_run
        self.derived = work / "derived-data"

    def run_case(self, c: dict) -> dict:
        result = {"id": c["id"], "kind": c["kind"], "title": c["title"], "closes": c["closes"],
                  "partOf": c.get("partOf", []), "status": "not-run", "commands": [], "artifacts": [],
                  "detail": "", "durationSeconds": 0.0}
        start = time.monotonic()
        try:
            getattr(self, "case_" + c["kind"])(c, result)
        except Blocked as e:
            result["status"], result["detail"] = "blocked", str(e)
        except subprocess.TimeoutExpired:
            result["status"], result["detail"] = "timeout", f"over the {c['timeoutSeconds']} s limit"
        except SystemExit as e:   # run_device_tests exits on a launch that never succeeded
            text = str(e)
            if "Locked" in text:
                result["status"], result["detail"] = "blocked", self.locked_message()
            else:
                result["status"], result["detail"] = "error", text[-600:]
        except Exception as e:  # noqa: BLE001 - recorded, and the next case runs
            result["status"], result["detail"] = "error", f"{type(e).__name__}: {e}"
        result["durationSeconds"] = round(time.monotonic() - start, 1)
        return result

    def locked_message(self) -> str:
        return (f"{self.target.label} stayed locked for {self.locked_wait:.0f} s: unlock it and set Auto-Lock to "
                f"Never, then rerun with --only for the remaining cases")

    def add(self, result: dict, path: Path | None, committed: bool) -> None:
        if path and path.exists() and not self.dry_run:
            result["artifacts"].append(artifact(path, committed))

    # Each case_* fills result["status"], ["detail"], ["artifacts"]; commands are printed by rdt.run.

    def case_autorun(self, c: dict, result: dict) -> None:
        result["commands"].append(["PROJECTM_AUTORUN=" + c["mode"], "launch", rdt.BUNDLE])
        if c.get("permission"):
            if self.target.simulator:   # a rehearsal grants it; on a device a person taps Allow once
                rdt.run(["xcrun", "simctl", "privacy", self.target.identifier, "grant", c["permission"], rdt.BUNDLE],
                        check=False)
            else:
                print(f">>> {self.target.label}: the fresh install asks for {c['permission']} access during this "
                      f"case; tap Allow on the device (one tap; the case waits up to {c['wait']} s)", flush=True)
        report = rdt.run_mode(self.target, c["mode"], c["prefix"], c["wait"])
        if self.dry_run:
            result["status"] = "skipped"
            return
        if not report:
            result["status"], result["detail"] = "fail", f"no {c['prefix']} report within {c['wait']} s"
            return
        self.add(result, report, report.stat().st_size <= COMMIT_LIMIT)
        data = json.loads(report.read_text())
        error = data.get("error") if isinstance(data, dict) else None
        result["status"] = "fail" if error else "pass"
        result["detail"] = error or f"report {report.name}"

    def case_launches(self, c: dict, result: dict) -> None:
        dest = rdt.launches(self.target, c["mode"], c["repeat"])
        if self.dry_run:
            result["status"] = "skipped"
            return
        samples = json.loads(dest.read_text()) if dest.exists() else []
        self.add(result, dest, True)
        result["status"] = "pass" if samples else "fail"
        result["detail"] = f"{len(samples)} launches recorded" if samples else "no samples"

    def case_warmstart(self, c: dict, result: dict) -> None:
        t = self.target
        t.launch("perf009")                       # a fresh install only acknowledges the notice
        time.sleep(0 if self.dry_run else 8)
        for _ in range(c["repeat"]):
            for extra in ({"PROJECTM_WARMCACHE": "cold"}, None):
                t.launch("perf009", extra)
                time.sleep(0 if self.dry_run else 6)
        dest = t.out_dir / "perf009.json"
        t.pull("Documents/perf009.json", dest)
        if self.dry_run:
            result["status"] = "skipped"
            return
        if not dest.exists():
            result["status"], result["detail"] = "fail", "perf009.json not pulled"
            return
        summary = rdt.warmstart_summary(json.loads(dest.read_text()), t.simulator)
        out = t.out_dir / "perf009-summary.json"
        out.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
        self.add(result, dest, True)
        self.add(result, out, True)
        ok = summary["cold"]["launches"] > 0 and summary["warm"]["launches"] > 0
        result["status"] = "pass" if ok else "fail"
        result["detail"] = (f"cold {summary['cold']['launches']} launches, library ready "
                            f"{summary['cold']['libraryReadyMs']} ms; warm {summary['warm']['launches']}, "
                            f"{summary['warm']['libraryReadyMs']} ms")

    def case_thresholds(self, c: dict, result: dict) -> None:
        t = self.target
        result["commands"].append(["check_performance_thresholds", str(t.out_dir)] + [str(p) for p in self.perf012])
        verdict = rdt.judge_thresholds(t.out_dir, label=t.label, simulator=t.simulator, extra=self.perf012,
                                       write=not self.dry_run)
        if self.dry_run:
            result["status"] = "skipped"
            return
        self.add(result, t.out_dir / "performance-verdict.json", True)
        code = cpt.exit_code(verdict)
        result["status"] = {0: "pass", 1: "fail"}.get(code, "error")
        result["detail"] = f"QA-010 overall {verdict.get('overall')}" + (
            f": {verdict.get('error')}" if verdict.get("error") else "")

    def case_xctest(self, c: dict, result: dict) -> None:
        bundle = self.work / "xcresult" / f"{c['id']}.xcresult"
        log = self.work / "logs" / f"{c['id']}.log"
        if not self.dry_run:
            bundle.parent.mkdir(parents=True, exist_ok=True)
            log.parent.mkdir(parents=True, exist_ok=True)
            if bundle.exists():
                shutil.rmtree(bundle)
        try:
            cmd, cwd = xctest_command(c, self.target, self.derived, bundle)
        except NoDeviceHost as e:
            result["status"], result["detail"] = "not-run", str(e)
            print(f"!! {c['id']}: {e}", flush=True)
            return
        if cwd == ROOT and DEVICE_TEST_PROJECT.name in " ".join(cmd) and not DEVICE_TEST_PROJECT.exists() \
                and not self.dry_run:
            subprocess.run(["xcodegen", "generate", "--spec", str(DEVICE_TEST_SPEC)], cwd=ROOT, check=True,
                           capture_output=True)
        env = {f"TEST_RUNNER_{k}": v for k, v in c.get("env", {}).items()}
        result["commands"].append([f"(cd {display_path(cwd)})"] + [f"{k}={v}" for k, v in env.items()] + cmd)
        deadline = time.monotonic() + self.locked_wait
        while True:
            print(f"$ (cd {display_path(cwd)}) " + " ".join(f"{k}={v}" for k, v in env.items()) + " "
                  + " ".join(cmd), flush=True)
            if self.dry_run:
                result["status"] = "skipped"
                return
            proc = subprocess.run(cmd, cwd=cwd, env={**os.environ, **env}, text=True, capture_output=True,
                                  timeout=c["timeoutSeconds"] + 900)   # the limit covers the test run; + build time
            text = proc.stdout + proc.stderr
            log.write_text(text)
            if proc.returncode != 0 and not self.target.simulator and is_locked(text):
                if time.monotonic() > deadline:
                    raise Blocked(self.locked_message())
                print(f"!! {self.target.label} is locked: unlock it (and set Auto-Lock to Never); retrying in 15 s",
                      flush=True)
                time.sleep(15)
                if bundle.exists():
                    shutil.rmtree(bundle)
                continue
            break
        self.add(result, log, False)
        self.add(result, bundle, False)
        for exported in self.export_attachments(bundle, c["id"]):
            self.add(result, exported, True)
        bench = [line for line in text.splitlines() if re.search(r"(?i)\b(bench|gpu time|QA-006 qa006)\b", line)
                 and "Test Case" not in line][:6]
        result["status"] = "pass" if proc.returncode == 0 else "fail"
        result["detail"] = test_counts(text) + (f"; exit {proc.returncode}" if proc.returncode else "") + (
            "; " + " / ".join(x.strip()[:160] for x in bench) if bench else "")

    def export_attachments(self, bundle: Path, case_id: str) -> list[Path]:
        """JSON attachments (for example the QA-006 soak report) copied next to the record."""
        if not bundle.exists():
            return []
        out = self.work / "attachments" / case_id
        proc = capture(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle),
                        "--output-path", str(out)])
        if proc.returncode != 0 or not out.exists():
            return []
        copied = []
        for p in sorted(out.rglob("*.json")):
            if p.name == "manifest.json" or p.stat().st_size > COMMIT_LIMIT:
                continue
            dest = self.target.out_dir / f"{case_id}-{p.name}"
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, dest)
            copied.append(dest)
        return copied


# MARK: - One device (or a simulator)

def now() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def run_target(label: str, args, devices_by_case: dict[str, list[str]], listing: dict | None) -> int:
    simulator = label == "sim"
    run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    record_dir = RUNS / label / run_id
    work = (Path(args.work_dir) if args.work_dir else ROOT / "Build/qa-011") / label / run_id
    only = set(args.only.split(",")) if args.only else None
    cases = plan(None if simulator and not args.as_device else (args.as_device or label), devices_by_case, only)

    if simulator:
        listing_sim = json.loads(capture(["xcrun", "simctl", "list", "devices", "--json"]).stdout or "{}")
        runtimes = json.loads(capture(["xcrun", "simctl", "list", "runtimes", "--json"]).stdout or "{}")
        facts = simulator_facts(listing_sim, runtimes, args.simulator)
        identifier, udid = args.simulator, args.simulator
    elif rdt.DRY_RUN:
        facts = {"kind": "device", "identifier": f"<{label} identifier>", "udid": "<UDID>", "state": "dry run"}
        identifier, udid = facts["identifier"], facts["udid"]
    else:
        facts = device_facts(device_entry(listing or {}, label))
        identifier, udid = facts.get("identifier"), facts.get("udid")

    app = Path(args.app) if args.app else rdt.BUILD / (
        f"Build/Products/{'Debug-iphonesimulator' if simulator else 'Release-iphoneos'}/{rdt.SCHEME}.app")
    configuration = args.configuration or ("Debug (simulator rehearsal)" if simulator else "Release+PROJECTM_AUTOMATION")
    evidence = not simulator
    record = {"kind": RECORD_KIND, "schemaVersion": 1, "runId": run_id, "label": label, "evidence": evidence,
              "evidenceNote": "physical device run" if evidence else "simulator rehearsal, not evidence",
              "dryRun": rdt.DRY_RUN, "target": facts, "startedAt": now(), "stopReason": None, "cases": []}

    print(f"\n=== QA-011 matrix: {label} ({facts.get('name') or identifier}), {len(cases)} cases"
          + ("" if evidence else " — SIMULATOR REHEARSAL, NOT EVIDENCE") + " ===", flush=True)
    target = MatrixTarget(label, identifier or "", simulator, record_dir / "artifacts", udid)
    runner = Runner(target, work, args.locked_wait, [Path(p) for p in args.perf012_report], rdt.DRY_RUN)

    unavailable = (not simulator and not rdt.DRY_RUN and facts.get("state") in ("not listed", "unavailable"))
    if args.build:
        rdt.cmd_build(args)
    record["app"], record["signing"], record["host"] = app_facts(app, configuration), signing_facts(app), host_facts()
    if unavailable:
        record["stopReason"] = "unavailable"
        print(f"!! {label} ({rdt.DEVICES[label]}) is {facts.get('state')}: connect the cable, unlock it and trust "
              f"this Mac; nothing ran", flush=True)
        record["cases"] = [dict(runner_result_stub(c), detail=f"device {facts.get('state')}") for c in cases]
    else:
        if simulator and not rdt.DRY_RUN:
            capture(["xcrun", "simctl", "boot", identifier])
        if not args.no_install and any(c["kind"] in ("autorun", "launches", "warmstart") for c in cases):
            try:
                target.uninstall()
                target.install(app)
            except subprocess.CalledProcessError as e:
                record["stopReason"] = "install failed"
                print(f"!! install failed on {label}: {e}", flush=True)
        stopped = record["stopReason"]
        for c in cases:
            if stopped:
                record["cases"].append(dict(runner_result_stub(c), detail=f"not run: {stopped}"))
                continue
            result = runner.run_case(c)
            record["cases"].append(result)
            print(f"--> {c['id']}: {result['status']} {result['detail'][:200]}", flush=True)
            if result["status"] == "blocked":
                stopped = record["stopReason"] = "locked"
                print(f"!! {result['detail']}", flush=True)
            target.terminate()
    record["finishedAt"] = now()
    if rdt.DRY_RUN:
        print(f"(dry run: {len(cases)} cases planned for {label}; nothing written)")
        return 0
    path = write_record(record, record_dir)
    print(f"record: {display_path(path)} sha256 {record['recordSha256']}")
    print(", ".join(f"{k} {v}" for k, v in record["summary"].items() if v))
    return 0 if record["summary"]["pass"] == len(cases) else 1


def runner_result_stub(c: dict) -> dict:
    return {"id": c["id"], "kind": c["kind"], "title": c["title"], "closes": c["closes"],
            "partOf": c.get("partOf", []), "status": "not-run", "commands": [], "artifacts": [], "detail": "",
            "durationSeconds": 0.0}


def main(argv: list[str] | None = None) -> int:
    raw = list(sys.argv[1:] if argv is None else argv)
    if raw[:1] == ["verify"]:
        problems = []
        for p in raw[1:]:
            found = verify_record(Path(p))
            problems += [f"{p}: {x}" for x in found]
            print(f"{p}: {'ok' if not found else 'FAILED'}")
        print("\n".join(problems))
        return 1 if problems or len(raw) < 2 else 0
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--device", action="append", choices=[*LABELS, "all"], help="D1, D2, D3 or all (repeatable)")
    parser.add_argument("--simulator", metavar="UDID", help="rehearse on this simulator (not evidence)")
    parser.add_argument("--as-device", choices=LABELS, help="simulator: run only this device's cases")
    parser.add_argument("--dry-run", action="store_true", help="print every command; write nothing")
    parser.add_argument("--build", action="store_true", help="build the measurement build first (run_device_tests build)")
    parser.add_argument("--app", help="the .app to install (default: the measurement build's output)")
    parser.add_argument("--configuration", help="how --app was built, for the record")
    parser.add_argument("--no-install", action="store_true", help="keep the installed app")
    parser.add_argument("--only", help=f"comma-separated case ids ({', '.join(CASE_IDS)})")
    parser.add_argument("--perf012-report", action="append", default=[], help="an exported PERF-012 report for QA-010")
    parser.add_argument("--locked-wait", type=float, default=600, help="seconds a locked device is waited for")
    parser.add_argument("--work-dir", help="where xcresults and logs go (default Build/qa-011)")
    parser.add_argument("--inventory", default=str(INVENTORY))
    args = parser.parse_args(raw)
    if bool(args.device) == bool(args.simulator):
        parser.error("give --device D1|D2|D3|all or --simulator <udid>")
    if args.only and (bad := set(args.only.split(",")) - set(CASE_IDS)):
        parser.error(f"unknown case ids: {', '.join(sorted(bad))}")
    rdt.DRY_RUN = args.dry_run
    rdt.LOCKED_WAIT = args.locked_wait
    devices_by_case = case_devices(load_inventory(Path(args.inventory)))
    if args.simulator:
        return run_target("sim", args, devices_by_case, None)
    labels = list(LABELS) if "all" in args.device else list(dict.fromkeys(args.device))
    listing = None
    if not args.dry_run:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "devices.json"
            capture(["xcrun", "devicectl", "list", "devices", "--json-output", str(out)])
            listing = json.loads(out.read_text()) if out.exists() else {}
    return max(run_target(label, args, devices_by_case, listing) for label in labels)


if __name__ == "__main__":
    sys.exit(main())
