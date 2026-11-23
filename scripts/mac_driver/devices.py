#!/usr/bin/env python3
"""QA-011 Batch 8: device facts and file copies for the Mac-side drivers (devicectl and dscacheutil, both read-only
except the copies into and out of the test app's own container).

* `DEVICES`: D1-D3 by product type, with their Bonjour names on the test Wi-Fi.
* `identifiers()`: name → devicectl identifier and hardware UDID (xcodebuild's -destination needs the UDID).
* `resolve(host)`: an IPv4 address for `<name>.local` (Python's resolver misses Bonjour names here; dscacheutil works).
* `documents(device)`, `pull(device, name, dest)`, `push(device, src, name)`: the app's Documents.
"""
from __future__ import annotations

import json
import socket
import subprocess
import tempfile
from pathlib import Path

BUNDLE = "org.projectmios.ProjectMiOS"
DEVICES = {
    "D1": {"productType": "iPhone15,4", "host": "iPhone77.local"},
    "D2": {"productType": "iPad17,3", "host": "iPad77.local"},
    "D3": {"productType": "iPad15,7", "host": "iPadC.local"},
}


def parse_device_list(listing: dict) -> dict[str, dict[str, str]]:
    """devicectl's `list devices` JSON → {"D1": {"identifier": …, "udid": …}}."""
    by_type = {}
    for d in listing.get("result", {}).get("devices", []):
        hw = d.get("hardwareProperties", {})
        by_type[hw.get("productType")] = {"identifier": d.get("identifier", ""), "udid": hw.get("udid", "")}
    return {name: by_type[info["productType"]] for name, info in DEVICES.items() if info["productType"] in by_type}


def identifiers() -> dict[str, dict[str, str]]:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "devices.json"
        subprocess.run(["xcrun", "devicectl", "list", "devices", "--json-output", str(out)], check=True, capture_output=True)
        return parse_device_list(json.loads(out.read_text()))


def parse_dscacheutil_all(out: str) -> list[str]:
    return [line.split(":", 1)[1].strip() for line in out.splitlines() if line.startswith("ip_address:") and "." in line]


def parse_dscacheutil(out: str) -> str | None:
    return prefer_lan(parse_dscacheutil_all(out))


def prefer_lan(addresses: list[str]) -> str | None:
    """The first address another device can reach: never a link-local 169.254.x.x, which a device plugged in by USB
    also has (D2 after its iPadOS 27.2.1 update, 2026-11-23: the peer on Wi-Fi was given D2's USB address)."""
    lan = [a for a in addresses if not a.startswith("169.254.")]
    return (lan or addresses or [None])[0]


def resolve(host: str) -> str:
    """The resolver, else macOS's Bonjour cache (`dscacheutil`), which resolves `<name>.local` when Python's
    resolver does not (seen 2026-11-16)."""
    found: list[str] = []
    try:
        found += socket.gethostbyname_ex(host)[2]
    except OSError:
        pass
    out = subprocess.run(["dscacheutil", "-q", "host", "-a", "name", host], capture_output=True, text=True).stdout
    found += [a for a in parse_dscacheutil_all(out) if a not in found]
    address = prefer_lan(found)
    if address:
        return address
    raise OSError(f"cannot resolve {host}")


def mac_address_toward(peer_ip: str) -> str:
    """This Mac's LAN address on the route to `peer_ip` (a UDP socket's local end; nothing is sent)."""
    route = subprocess.run(["/sbin/route", "-n", "get", peer_ip], capture_output=True, text=True).stdout
    interface = next((line.split(":", 1)[1].strip() for line in route.splitlines()
                      if line.strip().startswith("interface:")), "")
    if interface:
        address = subprocess.run(["/usr/sbin/ipconfig", "getifaddr", interface], capture_output=True, text=True).stdout.strip()
        if address:
            return address
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.connect((peer_ip, 9))
        return s.getsockname()[0]


def documents(identifier: str) -> list[str]:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "files.json"
        subprocess.run(["xcrun", "devicectl", "device", "info", "files", "--device", identifier,
                        "--domain-type", "appDataContainer", "--domain-identifier", BUNDLE,
                        "--subdirectory", "Documents", "--json-output", str(out)], check=True, capture_output=True)
        return sorted(f["relativePath"] for f in json.loads(out.read_text())["result"]["files"])


def pull(identifier: str, name: str, destination: Path) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["xcrun", "devicectl", "device", "copy", "from", "--device", identifier, "--domain-type",
                    "appDataContainer", "--domain-identifier", BUNDLE, "--source", f"Documents/{name}",
                    "--destination", str(destination)], check=True, capture_output=True)
    return destination


def push(identifier: str, source: Path, name: str) -> None:
    subprocess.run(["xcrun", "devicectl", "device", "copy", "to", "--device", identifier, "--domain-type",
                    "appDataContainer", "--domain-identifier", BUNDLE, "--source", str(source),
                    "--destination", f"Documents/{name}"], check=True, capture_output=True)


def newest(names: list[str], prefix: str, suffix: str) -> str | None:
    """The last name (names carry a sortable UTC time) with `prefix` and `suffix`, in the folder itself."""
    picked = sorted(n.rsplit("/", 1)[-1] for n in names
                    if n.rsplit("/", 1)[-1].startswith(prefix) and n.endswith(suffix))
    return picked[-1] if picked else None
