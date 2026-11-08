#!/usr/bin/env python3
"""Tests for the repository scripts. Run: python scripts/test_scripts.py (Windows or macOS)."""
from __future__ import annotations

import hashlib
import json
import math
import struct
import sys
import tempfile
import unittest
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_capturelab_export  # noqa: E402
import check_compliance  # noqa: E402
import generate_reference_audio as gra  # noqa: E402
import validate_docs  # noqa: E402
import verify_environment  # noqa: E402

FIXTURES = Path(__file__).resolve().parent / "fixtures"


class ValidateDocsTests(unittest.TestCase):
    def test_current_docs_pass(self):
        self.assertEqual(validate_docs.main([]), 0)

    def test_fixture_with_undefined_id_fails(self):
        self.assertEqual(validate_docs.main(["--include-fixtures"]), 1)


class ComplianceTests(unittest.TestCase):
    def test_clean_tree_passes(self):
        self.assertEqual(check_compliance.main([]), 0)

    def test_fixture_flags_every_rule(self):
        found = check_compliance.check_file(FIXTURES / "Violations.swift.txt")
        text = "\n".join(found)
        for expected in ["ReplayKit", "networking", "dynamic symbol", "class/selector", "ScreenCaptureKit imported outside"]:
            self.assertIn(expected, text)
        self.assertEqual(check_compliance.main(["--paths", str(FIXTURES / "Violations.swift.txt")]), 1)

    def test_comments_are_ignored(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "Ok.swift"
            p.write_text("// import ReplayKit\n/* URLSession */\nlet x = 1\n", encoding="utf-8")
            self.assertEqual(check_compliance.check_file(p), [])

    def test_entitlements_in_project_yml_flagged(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "project.yml"
            p.write_text("targets:\n  App:\n    entitlements:\n      path: x\n", encoding="utf-8")
            self.assertTrue(check_compliance.check_project_yml(p))


class VerifyEnvironmentTests(unittest.TestCase):
    def test_non_mac_exits_zero(self):
        if sys.platform == "darwin":
            self.skipTest("macOS host")
        self.assertEqual(verify_environment.main(), 0)

    def test_pins_parse(self):
        pins = verify_environment.read_pins()
        self.assertEqual(set(pins), set(verify_environment.TOOLS))


class ReferenceAudioTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        a, b = Path(cls.tmp.name) / "a", Path(cls.tmp.name) / "b"
        gra.write(a)
        gra.write(b)
        cls.a, cls.b = a, b

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def digest(self, p: Path) -> str:
        return hashlib.sha256(p.read_bytes()).hexdigest()

    def test_byte_identical_runs(self):
        for name in ("reference.wav", "reference-clicks.json"):
            self.assertEqual(self.digest(self.a / name), self.digest(self.b / name))

    def test_format(self):
        with wave.open(str(self.a / "reference.wav"), "rb") as w:
            self.assertEqual((w.getnchannels(), w.getsampwidth(), w.getframerate()), (2, 2, 44_100))
            self.assertEqual(w.getnframes(), 44_100 * 60)

    def test_segments(self):
        with wave.open(str(self.a / "reference.wav"), "rb") as w:
            def peak(start, end):
                w.setpos(int(start * 44_100))
                raw = w.readframes(int((end - start) * 44_100))
                vals = struct.unpack(f"<{len(raw) // 2}h", raw)
                return max(abs(v) for v in vals) / 32767
            self.assertAlmostEqual(20 * math.log10(peak(1, 2)), -12, delta=0.1)
            self.assertEqual(peak(11, 19), 0.0)
            self.assertGreater(peak(40, 40.01), 0.9)
            self.assertEqual(peak(40.01, 40.99), 0.0)

    def test_clicks_json(self):
        data = json.loads((self.a / "reference-clicks.json").read_text(encoding="utf-8"))
        self.assertEqual(len(data["clickTimesSeconds"]), 20)
        self.assertEqual(data["clickTimesSeconds"][0], 40.0)


class UIStringsContractTests(unittest.TestCase):
    """CaptureUI's UIStrings.swift must contain every user-visible string in the ui-states contract."""

    ROOT = Path(__file__).resolve().parent.parent
    CONTRACT = ROOT / "specs" / "001-ios-projectm-visualizer" / "contracts" / "ui-states.md"
    SWIFT = ROOT / "Packages" / "CaptureUI" / "Sources" / "CaptureUI" / "UIStrings.swift"

    def contract_strings(self) -> list[str]:
        import re
        text = self.CONTRACT.read_text(encoding="utf-8")
        found: list[str] = []
        section = None
        for line in text.splitlines():
            if line.startswith("## "):
                section = line[3:].strip()
                continue
            cells = [c.strip() for c in line.strip().strip("|").split("|")] if line.startswith("|") else []
            if not cells or set(cells[0]) <= set("-: "):
                continue
            if section and section.startswith("Source labels") and cells[0] != "Mode":
                found += [cells[1]] + ([cells[2]] if cells[2] not in ("—", "Unavailable text") else [])
            elif section and section.startswith("Source chooser") and cells[0] != "Mode":
                found.append(cells[1])
            elif section and section.startswith("Stop/failure") and cells[0] != "StopReason":
                msg = cells[1]
                if "‹description›" in msg:
                    msg = msg.split("‹")[0]
                found.append(msg)
        states = re.search(r"## Audio states \(FR-010\)\s+(.+?)\n\n", text, re.S).group(1)
        found += [s.strip() for s in states.replace("\n", " ").split("·")]
        found += re.findall(r'→ "([^"]+)"', text)                       # hints
        found.append(re.search(r'reads: "(.+?)"', text, re.S).group(1).replace("\n", " "))  # mic explainer
        found.append(re.search(r'Note field placeholder: "(.+?)"', text, re.S).group(1).replace("\n", " "))
        return [s for s in found if s]

    def test_every_contract_string_is_in_swift(self):
        swift = self.SWIFT.read_text(encoding="utf-8")
        missing = [s for s in self.contract_strings() if s not in swift]
        self.assertEqual(missing, [])

    def test_info_plist_mic_text_matches_explainer(self):
        import re
        yml = (self.ROOT / "project.yml").read_text(encoding="utf-8")
        plist_text = re.search(r'NSMicrophoneUsageDescription: "(.+?)"', yml).group(1)
        swift = self.SWIFT.read_text(encoding="utf-8")
        self.assertIn(f'"{plist_text}"', swift)   # FR-019

    def test_info_plist_capture_text_matches_contract(self):
        import re
        yml = (self.ROOT / "project.yml").read_text(encoding="utf-8")
        plist_text = re.search(r'NSScreenCaptureUsageDescription: "(.+?)"', yml).group(1)
        contract = self.CONTRACT.read_text(encoding="utf-8")
        row = re.search(r"^\| `NSScreenCaptureUsageDescription` \| (.+?) \|$", contract, re.M).group(1)
        self.assertEqual(plist_text, row)   # FR-019


class CaptureLabExportCheckTests(unittest.TestCase):
    """scripts/check_capturelab_export.py on small exports written to a fake CoreSimulator tree."""

    UDID = "59AF55BD-E946-45A1-BADB-6977B13BE8A1"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "Devices"

    @staticmethod
    def export(events, schema_version=1):
        return {
            "schemaVersion": schema_version,
            "session": {"sourceMode": "inAppPlayback", "finalState": "active",
                        "lifecycleEvents": [{"event": e, "atSeconds": t} for e, t in events]},
        }

    def container(self, name: str, bundle_id: str) -> Path:
        import plistlib
        c = self.root / self.UDID / "data" / "Containers" / "Data" / "Application" / name
        (c / "tmp").mkdir(parents=True)
        with (c / check_capturelab_export.METADATA_PLIST).open("wb") as f:
            plistlib.dump({"MCMMetadataIdentifier": bundle_id}, f)
        return c

    def write(self, path: Path, data) -> Path:
        path.write_text(json.dumps(data), encoding="utf-8")
        return path

    def run_main(self, *argv: str) -> int:
        import contextlib
        import io
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return check_capturelab_export.main(list(argv), devices_root=self.root)

    def test_background_then_foreground_passes(self):
        data = self.export([("background", 1.79), ("foreground", 2.04)])
        self.assertEqual(check_capturelab_export.check_export(data), [])

    def test_equal_times_pass(self):
        # iPadOS 26.5 simulator: both events handled on resume, so they carry the same time.
        data = self.export([("background", 2.552), ("foreground", 2.552)])
        self.assertEqual(check_capturelab_export.check_export(data), [])

    def test_other_events_in_between_pass(self):
        data = self.export([("background", 1.0), ("routeChange", 1.5), ("foreground", 2.0)])
        self.assertEqual(check_capturelab_export.check_export(data), [])

    def test_wrong_order_fails(self):
        data = self.export([("foreground", 1.0), ("background", 2.0)])
        self.assertTrue(check_capturelab_export.check_export(data))

    def test_missing_events_fail(self):
        self.assertTrue(check_capturelab_export.check_export(self.export([])))
        self.assertTrue(check_capturelab_export.check_export(self.export([("background", 1.0)])))

    def test_decreasing_times_fail(self):
        data = self.export([("background", 2.0), ("foreground", 1.0)])
        problems = check_capturelab_export.check_export(data)
        self.assertTrue(any("earlier" in p for p in problems), problems)

    def test_bad_times_fail(self):
        for bad in (-0.1, "1.0", None, True):
            data = self.export([("background", bad), ("foreground", 2.0)])
            self.assertTrue(check_capturelab_export.check_export(data), bad)

    def test_wrong_schema_version_fails(self):
        data = self.export([("background", 1.0), ("foreground", 2.0)], schema_version=2)
        self.assertTrue(check_capturelab_export.check_export(data))
        self.assertTrue(check_capturelab_export.check_export({"schemaVersion": 1}))

    def test_custom_expect(self):
        data = self.export([("interruptionBegan", 1.0), ("interruptionEnded", 2.0)])
        self.assertEqual(check_capturelab_export.check_export(data, ("interruptionBegan", "interruptionEnded")), [])
        self.assertTrue(check_capturelab_export.check_export(data))

    def test_finds_newest_export_in_capturelab_container_only(self):
        lab = self.container("A", check_capturelab_export.BUNDLE_ID)
        other = self.container("B", "com.example.Other")
        good = self.export([("background", 1.0), ("foreground", 2.0)])
        bad = self.export([("foreground", 1.0)])
        self.write(lab / "tmp" / "CaptureLab-20261108-120000.json", bad)
        newest = self.write(lab / "tmp" / "CaptureLab-20261108-130000.json", good)
        self.write(lab / "tmp" / "Other-20261108-140000.json", bad)
        self.write(other / "tmp" / "CaptureLab-20261108-150000.json", bad)
        self.assertEqual(check_capturelab_export.newest_export(self.UDID, self.root), newest)
        self.assertEqual(self.run_main("--udid", self.UDID), 0)

    def test_udid_exit_codes(self):
        lab = self.container("A", check_capturelab_export.BUNDLE_ID)
        self.assertEqual(self.run_main("--udid", self.UDID), 2)            # no export yet
        self.write(lab / "tmp" / "CaptureLab-20261108-120000.json", self.export([("foreground", 1.0)]))
        self.assertEqual(self.run_main("--udid", self.UDID), 1)            # check fails
        self.assertEqual(self.run_main("--udid", "../../etc"), 2)          # not a UDID
        self.assertEqual(self.run_main("--udid", "00000000-0000-0000-0000-000000000000"), 2)

    def test_json_path(self):
        d = Path(self.tmp.name)
        ok = self.write(d / "ok.json", self.export([("background", 1.0), ("foreground", 2.0)]))
        self.assertEqual(self.run_main("--json", str(ok)), 0)
        (d / "broken.json").write_text("{", encoding="utf-8")
        self.assertEqual(self.run_main("--json", str(d / "broken.json")), 2)
        self.assertEqual(self.run_main("--json", str(d / "missing.json")), 2)


class SchemaCopyTests(unittest.TestCase):
    def test_diagnostics_schema_copy_matches_contract(self):
        root = Path(__file__).resolve().parent.parent
        contract = root / "specs" / "001-ios-projectm-visualizer" / "contracts" / "diagnostics-export.schema.json"
        copy = root / "Packages" / "Diagnostics" / "Tests" / "DiagnosticsTests" / "Resources" / "diagnostics-export.schema.json"
        self.assertEqual(json.loads(contract.read_text(encoding="utf-8")), json.loads(copy.read_text(encoding="utf-8")))


if __name__ == "__main__":
    unittest.main(verbosity=2)
