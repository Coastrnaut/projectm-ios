#!/usr/bin/env python3
"""Scan a built app for networking code (FILE-012-R1 to R3; FR-068 as amended by ADR-0008). macOS only.

Inspects every Mach-O image in the bundle (executable, `<executable>.debug.dylib`, embedded frameworks,
app extensions), every architecture, with `otool -L` (linked libraries) and `nm -m -u` (imported
symbols and the library each comes from). It fails on:

* a forbidden library: CFNetwork, WebKit, JavaScriptCore, SafariServices, AuthenticationServices,
  MultipeerConnectivity, NetworkExtension, SystemConfiguration, CloudKit, PushKit, MapKit, GameKit,
  libresolv;
* an imported BSD socket or resolver function, or a URL-loading, socket-stream, reachability, Bonjour,
  web-view, browser or network MIDI (`MIDINetwork*`, MIDI-001-R14) symbol;
* any Network.framework import (or linkage) outside the image that defines the OSC transport
  (`NetworkDatagramTransport`), any C-level `nw_*` import, and any Network Swift API that is not on the
  listener-side allowlist. The outbound pair `NWConnection(host:port:using:)` and `NWConnection.send`
  passes only in an image that also defines the DEBUG-only `OSCLoopbackSender`; `--release` fails when
  any image defines it.

StoreKit linkage is reported as allowed: purchase and restore requests are made by iOS's store service.
What this scan cannot see (system daemons, URL-taking Foundation APIs) is listed in
docs/test-reports/no-telemetry.md.

    python3 scripts/check_network_symbols.py <path to projectM-iOS.app> [--release] [--json <out>]

The parsing and rule functions are pure and tested on any OS (scripts/test_scripts.py).
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

MACHO_MAGICS = {
    bytes.fromhex("feedface"), bytes.fromhex("cefaedfe"), bytes.fromhex("feedfacf"),
    bytes.fromhex("cffaedfe"), bytes.fromhex("cafebabe"), bytes.fromhex("bebafeca"),
    bytes.fromhex("cafebabf"), bytes.fromhex("bfbafeca"),
}

FORBIDDEN_LIBRARIES = {
    "CFNetwork", "WebKit", "JavaScriptCore", "SafariServices", "AuthenticationServices",
    "MultipeerConnectivity", "NetworkExtension", "SystemConfiguration", "CloudKit", "PushKit",
    "MapKit", "GameKit", "libresolv",
}
ALLOWED_LIBRARIES = {"StoreKit": "purchase and restore requests are made by iOS (feature 002 FR-122)"}
NETWORK_LIBRARY = "Network"

# Exact imported C functions (Mach-O names carry a leading underscore; `$...` variants are stripped).
FORBIDDEN_FUNCTIONS = {
    "socket", "connect", "connectx", "bind", "listen", "accept", "send", "sendto", "sendmsg", "sendmsg_x",
    "recv", "recvfrom", "recvmsg", "recvmsg_x", "getaddrinfo", "getnameinfo", "gethostbyname",
    "gethostbyname2", "gethostbyaddr", "res_query", "res_search", "res_9_query", "res_9_search",
    "DNSServiceQueryRecord", "DNSServiceGetAddrInfo", "DNSServiceBrowse", "DNSServiceRegister",
    "DNSServiceResolve",
}
# Substrings of imported symbol names (ObjC classes, CF functions, Swift mangled names).
FORBIDDEN_SUBSTRINGS = (
    "URLSession", "NSURLConnection", "NSURLDownload", "CFHTTPMessage", "CFHTTPStream",
    "CFReadStreamCreateForHTTPRequest", "CFSocket", "CFStreamCreatePairWithSocket", "SCNetworkReachability",
    "NSNetService", "WKWebView", "UIWebView", "SFSafariViewController", "ASWebAuthenticationSession",
    "MCSession", "MCNearbyService", "NEHotspot",
    "MIDINetwork",   # MIDI-001-R14 (ADR-0038): the network MIDI session, host and connection classes
)

# Network Swift APIs (demangled, simplified) that only listen or receive (OSC-001 listener).
LISTENER_SIDE_APIS = [re.compile(p) for p in (
    r"^NWListener(\.|$)",
    r"^NWParameters(\.|$)",
    r"^NWEndpoint(\.|$)",
    r"^NWInterface(\.|$)",
    r"^NWError(\.|$)",
    r"^IPv4Address(\.|$)",
    r"^IPv6Address(\.|$)",
    r"^NWConnection$",
    r"^NWConnection\.(State|ContentContext)(\.|$)",
    r"^NWConnection\.(receiveMessage|receive|start|cancel|forceCancel|stateUpdateHandler|endpoint|state)\b",
)]
# Outbound APIs used only by the DEBUG loopback sender (OSC-001-T14, R19).
DEBUG_LOOPBACK_APIS = [re.compile(p) for p in (
    r"^NWConnection\.(__allocating_init|init)\(host:port:using:\)",
    r"^NWConnection\.send\(",
    r"^NWConnection\.SendCompletion(\.|$)",
)]
OSC_TRANSPORT_MARKER = "NetworkDatagramTransport"
LOOPBACK_SENDER_MARKER = "OSCLoopbackSender"
DESCRIPTOR_PREFIX = re.compile(r"^.*? for (?=\S)")


@dataclass(frozen=True)
class Finding:
    image: str
    arch: str
    kind: str      # "library" or "symbol"
    name: str
    rule: str
    allowed: bool


def library_name(path: str) -> str:
    """`/System/Library/Frameworks/X.framework/X` → X; `/usr/lib/libresolv.9.dylib` → libresolv."""
    leaf = path.rsplit("/", 1)[-1]
    if ".framework/" in path:
        return path.split(".framework/")[0].rsplit("/", 1)[-1]
    return re.sub(r"(\.[A-Z0-9]+)?(\.\d+)*\.dylib$", "", leaf, flags=re.I)


def parse_otool_libraries(output: str) -> list[str]:
    """Library paths from `otool -L` output (the first line names the image and is skipped)."""
    libraries: list[str] = []
    for line in output.splitlines():
        if not line.startswith(("\t", " ")):
            continue
        path = line.strip().split(" (compatibility", 1)[0].strip()
        if path and path not in libraries:
            libraries.append(path)
    return libraries


NM_IMPORT = re.compile(r"^\s*\(undefined\)\s+(?:weak\s+)?external\s+(\S+)(?:\s+\(from ([^)]+)\))?")


def parse_nm_imports(output: str) -> list[tuple[str, str]]:
    """(symbol, source library) pairs from `nm -m -u`; the library is "" when nm does not say."""
    pairs: list[tuple[str, str]] = []
    for line in output.splitlines():
        match = NM_IMPORT.match(line)
        if match:
            pairs.append((match.group(1), match.group(2) or ""))
    return pairs


def network_api_name(demangled: str) -> str:
    """The API a demangled Network symbol refers to: descriptor prefixes and `static ` removed."""
    name = demangled.strip()
    if " for " in name:
        name = DESCRIPTOR_PREFIX.sub("", name, count=1)
    if name.startswith("static "):
        name = name[len("static "):]
    return name


def classify_library(path: str, image_has_osc: bool) -> tuple[str, bool] | None:
    """(rule, allowed) for a linked library that matters, else None."""
    name = library_name(path)
    if name in FORBIDDEN_LIBRARIES:
        return (f"forbidden library {name}", False)
    if name in ALLOWED_LIBRARIES:
        return (f"allowed: {ALLOWED_LIBRARIES[name]}", True)
    if name == NETWORK_LIBRARY:
        if image_has_osc:
            return ("allowed: Network.framework in the OSC transport's image (ADR-0008)", True)
        return ("Network.framework linked outside the OSC transport's image", False)
    return None


def classify_import(symbol: str, library: str, demangled: str, image_has_osc: bool,
                    image_has_loopback: bool) -> tuple[str, bool] | None:
    """(rule, allowed) for an imported symbol that matters, else None."""
    bare = symbol[1:] if symbol.startswith("_") else symbol
    bare = bare.split("$", 1)[0] if not bare.startswith("$s") else bare
    if bare in FORBIDDEN_FUNCTIONS:
        return (f"socket or resolver function {bare}", False)
    for needle in FORBIDDEN_SUBSTRINGS:
        if needle in symbol:
            return (f"URL-loading, socket-stream, Bonjour or web symbol ({needle})", False)
    if library == NETWORK_LIBRARY or bare.startswith("nw_"):
        if bare.startswith("nw_"):
            return ("C-level Network API (nw_*) is not on the allowlist", False)
        if not image_has_osc:
            return ("Network.framework symbol outside the OSC transport's image", False)
        api = network_api_name(demangled or symbol)
        if any(rule.search(api) for rule in LISTENER_SIDE_APIS):
            return ("allowed: OSC listener-side Network API", True)
        if any(rule.search(api) for rule in DEBUG_LOOPBACK_APIS):
            if image_has_loopback:
                return ("allowed: DEBUG-only loopback sender (OSC-001-R19)", True)
            return ("outbound Network API in a build without the DEBUG loopback sender", False)
        return (f"Network API not on the listener-side allowlist: {api}", False)
    return None


def evaluate_image(image: str, arch: str, libraries: list[str], imports: list[tuple[str, str]],
                   demangled: dict[str, str], defined: set[str]) -> list[Finding]:
    """Findings for one image and architecture. `defined` holds the image's defined symbol names."""
    has_osc = any(OSC_TRANSPORT_MARKER in name for name in defined)
    has_loopback = any(LOOPBACK_SENDER_MARKER in name for name in defined)
    findings: list[Finding] = []
    for path in libraries:
        verdict = classify_library(path, has_osc)
        if verdict:
            findings.append(Finding(image, arch, "library", library_name(path), verdict[0], verdict[1]))
    for symbol, library in imports:
        verdict = classify_import(symbol, library, demangled.get(symbol, ""), has_osc, has_loopback)
        if verdict:
            findings.append(Finding(image, arch, "symbol", demangled.get(symbol) or symbol, verdict[0], verdict[1]))
    return findings


def release_findings(image: str, arch: str, defined: set[str]) -> list[Finding]:
    """`--release`: the DEBUG loopback sender must not be in any image."""
    if any(LOOPBACK_SENDER_MARKER in name for name in defined):
        return [Finding(image, arch, "symbol", LOOPBACK_SENDER_MARKER,
                        "DEBUG-only loopback sender in a Release build (OSC-001-R19)", False)]
    return []


def is_macho(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            return handle.read(4) in MACHO_MAGICS
    except OSError:
        return False


def macho_images(app: Path) -> list[Path]:
    return sorted(p for p in app.rglob("*") if p.is_file() and not p.is_symlink() and is_macho(p))


def run(arguments: list[str]) -> str:
    return subprocess.run(arguments, capture_output=True, text=True, check=True).stdout


def architectures(image: Path) -> list[str]:
    return run(["lipo", "-archs", str(image)]).split()


def demangle(symbols: list[str]) -> dict[str, str]:
    swift = [s for s in symbols if s.startswith(("_$s", "$s"))]
    if not swift:
        return {}
    output = subprocess.run(["xcrun", "swift-demangle", "--simplified"], input="\n".join(swift),
                            capture_output=True, text=True, check=True).stdout.splitlines()
    return dict(zip(swift, output))


def scan_image(app: Path, image: Path, release: bool) -> list[Finding]:
    findings: list[Finding] = []
    name = str(image.relative_to(app))
    for arch in architectures(image):
        libraries = parse_otool_libraries(run(["otool", "-L", "-arch", arch, str(image)]))
        imports = parse_nm_imports(run(["nm", "-m", "-u", "-arch", arch, str(image)]))
        defined = set(run(["nm", "-U", "-j", "-arch", arch, str(image)]).split())
        network = [s for s, library in imports if library == NETWORK_LIBRARY]
        findings += evaluate_image(name, arch, libraries, imports, demangle(network), defined)
        if release:
            findings += release_findings(name, arch, defined)
    return findings


def summary_lines(findings: list[Finding], images: int) -> tuple[list[str], int]:
    """Printable lines and the number of violations. Allowed findings are grouped per image and rule."""
    lines: list[str] = []
    violations = [f for f in findings if not f.allowed]
    for f in violations:
        lines.append(f"error: {f.image} [{f.arch}]: {f.kind} {f.name}: {f.rule}")
    groups: dict[tuple[str, str], int] = {}
    for f in findings:
        if f.allowed:
            groups[(f.image, f.rule)] = groups.get((f.image, f.rule), 0) + 1
    for (image, rule), count in sorted(groups.items()):
        lines.append(f"{image}: {rule} ({count} finding(s) across architectures)")
    verdict = "OK" if not violations else f"{len(violations)} violation(s)"
    lines.append(f"check_network_symbols: {verdict} ({images} images scanned)")
    return lines, len(violations)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Scan a built app for networking code (FILE-012)")
    parser.add_argument("app", type=Path)
    parser.add_argument("--release", action="store_true", help="also fail on the DEBUG loopback sender")
    parser.add_argument("--json", type=Path, help="write every finding to this file")
    args = parser.parse_args(argv)
    if sys.platform != "darwin":
        print("check_network_symbols: macOS only (needs nm, otool, lipo)")
        return 2
    if not (args.app / "Info.plist").exists():
        print(f"check_network_symbols: {args.app} is not an app bundle")
        return 2
    images = macho_images(args.app)
    if not images:
        print(f"check_network_symbols: no Mach-O image in {args.app}")
        return 1
    findings = [f for image in images for f in scan_image(args.app, image, args.release)]
    lines, violations = summary_lines(findings, len(images))
    print("\n".join(lines))
    if args.json:
        args.json.write_text(json.dumps({"app": str(args.app), "images": [str(i.relative_to(args.app)) for i in images],
                                         "findings": [asdict(f) for f in findings]}, indent=2) + "\n")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
