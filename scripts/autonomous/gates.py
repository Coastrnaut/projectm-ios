#!/usr/bin/env python3
"""Compile-and-unit gate (AUTO-008) with failure categories for the remediation loop (AUTO-009).

A gate is one command with a working directory and a timeout. `plan_gates` picks the gates a
change needs from the files it touched; `run_gates` runs them in order, writes each command's
output to a log file and stops at the first failure. xcodebuild output goes to the log file,
never through a pipe, and tests always run with execution time limits (CLAUDE.md playbook).
"""
from __future__ import annotations

import re
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
PROJECT = "ProjectM-iOS.xcodeproj"
APP_SCHEME = "projectM-iOS"
TEST_LIMITS = ("-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "180")


@dataclass(frozen=True)
class Gate:
    name: str
    command: tuple[str, ...]
    cwd: str = "."                 # relative to the checkout being gated
    timeout: float = 1800
    kind: str = "static"           # static | unit | build | simulator


@dataclass
class GateResult:
    gate: Gate
    exit_code: int
    seconds: float
    log_path: str
    category: str | None = None
    timed_out: bool = False

    @property
    def ok(self) -> bool:
        return self.exit_code == 0

    def command_line(self) -> str:
        return " ".join(self.gate.command)


def packages(repo: Path) -> list[str]:
    return sorted(p.parent.name for p in (repo / "Packages").glob("*/Package.swift"))


def package_dependencies(repo: Path) -> dict[str, set[str]]:
    """Local package -> local packages it depends on (from `path: "../X"` in Package.swift)."""
    deps: dict[str, set[str]] = {}
    for name in packages(repo):
        text = (repo / "Packages" / name / "Package.swift").read_text(encoding="utf-8")
        deps[name] = set(re.findall(r'path:\s*"\.\./([A-Za-z0-9_]+)"', text))
    return deps


def affected_packages(repo: Path, changed: list[str]) -> list[str]:
    """Packages with a changed file, plus every package that depends on one (transitively)."""
    deps = package_dependencies(repo)
    hit = {parts[1] for parts in (Path(c).parts for c in changed)
           if len(parts) > 2 and parts[0] == "Packages" and parts[1] in deps}
    grew = True
    while grew:
        grew = False
        for name, needs in deps.items():
            if name not in hit and needs & hit:
                hit.add(name)
                grew = True
    return sorted(hit)


def needs_binaries(repo: Path, package: str) -> bool:
    """True for packages that link the prebuilt engine or ANGLE frameworks from Build/."""
    text = (repo / "Packages" / package / "Package.swift").read_text(encoding="utf-8")
    return "../../Build/" in text


def static_gates() -> list[Gate]:
    return [Gate("compliance", ("python3", "scripts/check_compliance.py")),
            Gate("docs", ("python3", "scripts/validate_docs.py"))]


def script_gates() -> list[Gate]:
    return [Gate("script-tests", ("python3", "scripts/test_scripts.py"), kind="unit"),
            Gate("autonomous-tests", ("python3", "scripts/autonomous/tests/test_autonomous.py"),
                 kind="unit")]


def host_testable(repo: Path, package: str) -> bool:
    """False for iOS-only packages (no macOS platform): `swift test` cannot build them."""
    text = (repo / "Packages" / package / "Package.swift").read_text(encoding="utf-8")
    return ".macOS(" in text or "platforms:" not in text


# Packages with more than one product get SwiftPM's "<Name>-Package" scheme.
PACKAGE_SCHEMES = {"Rendering": "Rendering-Package"}


def default_simulator(runner=subprocess.run) -> str | None:
    """An iPhone simulator on the newest installed iOS runtime, chosen by runtime, not name."""
    import json
    try:
        proc = runner(["xcrun", "simctl", "list", "devices", "available", "--json"],
                      capture_output=True, text=True, timeout=60)
        devices = json.loads(proc.stdout)["devices"]
    except Exception:
        return None
    def version(runtime: str) -> tuple[int, ...]:
        return tuple(int(n) for n in re.findall(r"\d+", runtime.rsplit("iOS-", 1)[-1]))
    for runtime in sorted((r for r in devices if "SimRuntime.iOS-" in r), key=version,
                          reverse=True):
        phones = sorted((d for d in devices[runtime] if d["name"].startswith("iPhone")),
                        key=lambda d: (d["state"] == "Booted", d["name"]))
        if phones:
            return phones[0]["udid"]
    return None


def package_gate(package: str, repo: Path | None = None, simulator_udid: str | None = None
                 ) -> Gate:
    if repo is not None and not host_testable(repo, package):
        scheme = PACKAGE_SCHEMES.get(package, package)
        return Gate(f"sim-test:{package}",
                    ("xcodebuild", "-scheme", scheme, "-destination",
                     f"id={simulator_udid or 'NO-SIMULATOR'}", "CODE_SIGNING_ALLOWED=NO",
                     *TEST_LIMITS, "test"),
                    cwd=f"Packages/{package}", kind="simulator", timeout=3600)
    return Gate(f"swift-test:{package}",
                ("swift", "test", "--package-path", f"Packages/{package}"), kind="unit",
                timeout=2400)


def app_build_gate(derived_data: str) -> list[Gate]:
    return [Gate("xcodegen", ("xcodegen", "generate"), kind="build", timeout=300),
            Gate("app-build:simulator",
                 ("xcodebuild", "-quiet", "-project", PROJECT, "-scheme", APP_SCHEME,
                  "-destination", "generic/platform=iOS Simulator", "-derivedDataPath",
                  derived_data, "CODE_SIGNING_ALLOWED=NO", "build"),
                 kind="build", timeout=3600)]


def simulator_test_gate(udid: str, derived_data: str, only: tuple[str, ...] = ()) -> Gate:
    cmd = ["xcodebuild", "-project", PROJECT, "-scheme", APP_SCHEME, "-destination",
           f"id={udid}", "-derivedDataPath", derived_data, "CODE_SIGNING_ALLOWED=NO",
           *TEST_LIMITS]
    for test in only:
        cmd += [f"-only-testing:{test}"]
    return Gate("app-tests:simulator", (*cmd, "test"), kind="simulator", timeout=5400)


def plan_gates(repo: Path, changed: list[str], *, derived_data: str | None = None,
               simulator_udid: str | None = None, in_worktree: bool = False) -> list[Gate]:
    """The gates a set of changed files needs.

    In a feature worktree only static checks and package tests run (the engine binaries and
    generated project live in the main checkout). On the integration checkout the app build
    and, when a simulator is given, the app's tests run too.
    """
    gates = static_gates()
    if any(c.startswith("scripts/") for c in changed):
        gates += script_gates()
    for package in affected_packages(repo, changed):
        if in_worktree and needs_binaries(repo, package) and not (repo / "Build").exists():
            continue
        gates.append(package_gate(package, repo, simulator_udid))
    touches_app = any(c.startswith(("Apps/", "Packages/")) or c in ("project.yml",)
                      for c in changed)
    if touches_app and not in_worktree:
        dd = derived_data or str(repo / ".autonomous" / "derived-data")
        gates += app_build_gate(dd)
        if simulator_udid and any(c.startswith("Apps/") for c in changed):
            gates.append(simulator_test_gate(simulator_udid, dd))
    return gates


def categorize(gate: Gate, output: str, timed_out: bool) -> str:
    """toolchain / compiler / test / platform / license / security, for the retry loop."""
    low = output.lower()
    if gate.name == "compliance":
        return "security"
    if gate.name == "docs":
        return "test"
    if timed_out or "command not found" in low or "no such file or directory" in low \
            or "unable to find a destination" in low or "xcode-select" in low:
        return "toolchain"
    if "error:" in low and ("test case" not in low and "xctassert" not in low
                            and "expectation failed" not in low):
        return "compiler"
    return "test"


def run_gate(gate: Gate, checkout: Path, log_dir: Path, runner=subprocess.run) -> GateResult:
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / (re.sub(r"[^A-Za-z0-9_.-]+", "_", gate.name) + ".log")
    started = time.monotonic()
    timed_out = False
    with open(log_path, "w", encoding="utf-8") as log:
        log.write(f"$ {' '.join(gate.command)}\n# cwd: {checkout / gate.cwd}\n")
        log.flush()
        try:
            proc = runner(list(gate.command), cwd=str(checkout / gate.cwd), stdout=log,
                          stderr=subprocess.STDOUT, timeout=gate.timeout,
                          stdin=subprocess.DEVNULL)
            code = proc.returncode
        except subprocess.TimeoutExpired:
            code, timed_out = 124, True
            log.write(f"\n# timed out after {gate.timeout:.0f} s\n")
        except FileNotFoundError as exc:
            code = 127
            log.write(f"\n# command not found: {exc}\n")
    result = GateResult(gate, code, time.monotonic() - started, str(log_path),
                        timed_out=timed_out)
    if code != 0:
        result.category = categorize(
            gate, log_path.read_text(encoding="utf-8", errors="replace")[-20000:], timed_out)
    return result


def run_gates(gates: list[Gate], checkout: Path, log_dir: Path, runner=subprocess.run
              ) -> list[GateResult]:
    """Run in order and stop at the first failure: a failed gate blocks what follows."""
    results: list[GateResult] = []
    for gate in gates:
        results.append(run_gate(gate, checkout, log_dir, runner))
        if not results[-1].ok:
            break
    return results


def all_passed(gates: list[Gate], results: list[GateResult]) -> bool:
    return len(results) == len(gates) and all(r.ok for r in results)
