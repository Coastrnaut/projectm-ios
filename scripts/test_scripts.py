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
from unittest import mock
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


class ComplianceImportKindTests(unittest.TestCase):
    """ADR-0001 owner ruling 13a: kind-qualified Swift imports, with or without attributes."""

    KINDS = ("typealias", "struct", "class", "enum", "protocol", "let", "var", "func")
    ATTRS = ("", "@_implementationOnly ", "@_exported ", "@preconcurrency ")

    def check(self, source: str, name: str = "Main.swift") -> list[str]:
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / name
            p.write_text(source, encoding="utf-8")
            return check_compliance.check_file(p)

    def test_kind_qualified_replaykit_flagged(self):
        for attr in self.ATTRS:
            for kind in self.KINDS:
                src = f"{attr}import {kind} ReplayKit.RPScreenRecorder\n"
                self.assertTrue(any("ReplayKit" in v for v in self.check(src)), src)

    def test_kind_qualified_screencapturekit_flagged_outside_allowed_folder(self):
        for attr in self.ATTRS:
            for kind in self.KINDS:
                src = f"{attr}import {kind} ScreenCaptureKit.SCStream\n"
                self.assertTrue(any("ScreenCaptureKit imported outside" in v for v in self.check(src)), src)

    def test_plain_and_attributed_imports_still_flagged(self):
        for attr in self.ATTRS:
            self.assertTrue(self.check(f"{attr}import ReplayKit\n"), attr)
            self.assertTrue(self.check(f"{attr}import ScreenCaptureKit\n"), attr)
        self.assertTrue(self.check("#import <ReplayKit/ReplayKit.h>\n", "X.m"))
        self.assertTrue(self.check("#import <ScreenCaptureKit/ScreenCaptureKit.h>\n", "X.m"))

    def test_kind_qualified_screencapturekit_allowed_in_screen_capture_folder(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "Driver.swift"
            p.write_text("@preconcurrency import class ScreenCaptureKit.SCStream\n", encoding="utf-8")
            with mock.patch.object(check_compliance, "SCK_ALLOWED", Path(d)):
                self.assertEqual(check_compliance.check_file(p), [])

    def test_similar_names_and_comments_not_flagged(self):
        self.assertEqual(self.check("import struct ReplayKitty.Thing\nimport class Foundation.NSObject\n"), [])
        self.assertEqual(self.check("// import struct ReplayKit.RPScreenRecorder\n"), [])


class ComplianceProjectYmlTests(unittest.TestCase):
    """ADR-0001 owner ruling 13b and Decision 6: project.yml key forms and CODE_SIGN_ENTITLEMENTS."""

    ALLOWED = check_compliance.ALLOWED_CODE_SIGN_ENTITLEMENTS

    def check(self, yml: str) -> list[str]:
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "project.yml"
            p.write_text(yml, encoding="utf-8")
            return check_compliance.check_project_yml(p)

    def test_every_forbidden_key_in_every_form_flagged(self):
        keys = ("UIBackgroundModes", "entitlements", "com.apple.security.application-groups")
        forms = (
            "    {k}:\n      - audio\n",
            '    "{k}":\n      - audio\n',
            "    '{k}':\n      - audio\n",
            "    '{k}' : [audio]\n",
            "    properties: {{{k}: [audio]}}\n",
            '    properties: {{"{k}": [audio]}}\n',
            "    properties: {{UILaunchScreen: {{}}, {k}: [audio]}}\n",
            "    properties: {{UILaunchScreen: {{}},'{k}': [audio]}}\n",
            "    properties:\n      - {k}: x\n",
        )
        for key in keys:
            for form in forms:
                yml = "targets:\n  App:\n" + form.format(k=key)
                found = self.check(yml)
                self.assertTrue(any(key in v for v in found), yml)

    def test_comments_and_values_ignored(self):
        self.assertEqual(self.check("# no entitlements: here\nname: X  # UIBackgroundModes: [audio]\n"), [])
        self.assertEqual(self.check('name: "a # entitlements: b"\ndesc: no UIBackgroundModes here\n'), [])
        self.assertEqual(self.check("settings: {MY_entitlements: x, ENTITLEMENTS_X: y}\n"), [])

    def test_current_project_yml_passes(self):
        self.assertEqual(check_compliance.check_project_yml(check_compliance.ROOT / "project.yml"), [])

    def test_code_sign_entitlements_allowed_value(self):
        for line in (f"CODE_SIGN_ENTITLEMENTS: {self.ALLOWED}",
                     f'CODE_SIGN_ENTITLEMENTS: "{self.ALLOWED}"',
                     f"'CODE_SIGN_ENTITLEMENTS': '{self.ALLOWED}'  # Decision 6",
                     f'"CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]": {self.ALLOWED}',
                     f"CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]: {self.ALLOWED}"):
            yml = f"targets:\n  CaptureLab:\n    settings:\n      base:\n        {line}\n"
            self.assertEqual(self.check(yml), [], yml)
        self.assertEqual(self.check(f"settings: {{base: {{CODE_SIGN_ENTITLEMENTS: {self.ALLOWED}, X: y}}}}\n"), [])

    def test_code_sign_entitlements_other_value_flagged(self):
        for line in ("CODE_SIGN_ENTITLEMENTS: Apps/CaptureLab/Other.entitlements",
                     'CODE_SIGN_ENTITLEMENTS: "Apps/CaptureLab/CaptureLab.entitlements2"',
                     "CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]: App.entitlements",
                     "CODE_SIGN_ENTITLEMENTS: $(SRCROOT)/Apps/CaptureLab/CaptureLab.entitlements",
                     "CODE_SIGN_ENTITLEMENTS:",
                     "'CODE_SIGN_ENTITLEMENTS': ''"):
            yml = f"targets:\n  CaptureLab:\n    settings:\n      base:\n        {line}\n"
            self.assertTrue(any("CODE_SIGN_ENTITLEMENTS" in v for v in self.check(yml)), yml)
        self.assertTrue(self.check("settings: {base: {X: y, CODE_SIGN_ENTITLEMENTS: Other.entitlements}}\n"))

    def test_code_sign_entitlements_stacked_conditions(self):
        base = "targets:\n  CaptureLab:\n    settings:\n      base:\n        "
        self.assertEqual(self.check(base + f"CODE_SIGN_ENTITLEMENTS[config=Debug][sdk=iphoneos*]: {self.ALLOWED}\n"), [])
        found = self.check(base + "CODE_SIGN_ENTITLEMENTS[config=Debug][sdk=iphoneos*]: Other.entitlements\n")
        self.assertTrue(any("must be" in v for v in found), found)

    def test_code_sign_entitlements_unrecognized_form_flagged(self):
        for yml in ("settings:\n  base:\n    OTHER_SETTING: $(CODE_SIGN_ENTITLEMENTS)\n",
                    "settings: [CODE_SIGN_ENTITLEMENTS]\n",
                    "settings:\n  base:\n    ? CODE_SIGN_ENTITLEMENTS\n    : Other.entitlements\n"):
            found = self.check(yml)
            self.assertTrue(any("cannot verify" in v for v in found), yml)


    def test_xcodegen_entitlements_key_still_forbidden_with_setting(self):
        yml = (f"targets:\n  CaptureLab:\n    settings:\n      base:\n        CODE_SIGN_ENTITLEMENTS: {self.ALLOWED}\n"
               f"    entitlements:\n      path: {self.ALLOWED}\n")
        self.assertTrue(any("'entitlements'" in v for v in self.check(yml)))


class ComplianceEntitlementsFileTests(unittest.TestCase):
    """ADR-0001 Decision 6: every *.entitlements file holds only allowlisted keys and values."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def write(self, rel: str, data) -> Path:
        import plistlib
        p = self.root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(data, (bytes, str)):
            p.write_bytes(data.encode("utf-8") if isinstance(data, str) else data)
        else:
            with p.open("wb") as f:
                plistlib.dump(data, f)
        return p

    def test_no_entitlements_file_passes(self):
        self.assertEqual(check_compliance.check_entitlements(self.root), [])

    def test_capturelab_entitlements_passes(self):
        import plistlib
        self.write("Apps/CaptureLab/CaptureLab.entitlements", {"com.apple.developer.screen-recording": True})
        self.write("Other/Binary.entitlements", plistlib.dumps({"com.apple.developer.screen-recording": True},
                                                               fmt=plistlib.FMT_BINARY))
        self.assertEqual(check_compliance.check_entitlements(self.root), [])
        self.assertEqual(len(check_compliance.entitlements_files(self.root)), 2)

    def test_disallowed_key_flagged(self):
        self.write("Apps/X/X.entitlements", {"com.apple.developer.screen-recording": True,
                                             "com.apple.security.application-groups": ["group.x"]})
        found = check_compliance.check_entitlements(self.root)
        self.assertEqual(len(found), 1)
        self.assertIn("application-groups", found[0])

    def test_wrong_value_flagged(self):
        for value in (False, 1, "YES", [True]):
            self.write("A.entitlements", {"com.apple.developer.screen-recording": value})
            self.assertTrue(check_compliance.check_entitlements(self.root), value)

    def test_unparseable_and_non_dict_flagged(self):
        self.write("Bad.entitlements", "<plist><dict><key>x</key>")
        self.write("Empty.entitlements", b"")
        self.write("List.entitlements", ["com.apple.developer.screen-recording"])
        self.assertEqual(len(check_compliance.check_entitlements(self.root)), 3)

    def test_skipped_folders(self):
        bad = {"com.apple.developer.icloud-services": ["CloudKit"]}
        for rel in (".git/x/A.entitlements", "Vendor/projectM/A.entitlements", "build/A.entitlements",
                    "Build/A.entitlements", "Apps/.build/A.entitlements", "DerivedData/A.entitlements",
                    ".claude/worktrees/wf/A.entitlements"):
            self.write(rel, bad)
        self.assertEqual(check_compliance.check_entitlements(self.root), [])
        self.write("Packages/Vendor/A.entitlements", bad)   # only the root Vendor/ is skipped
        self.assertEqual(len(check_compliance.check_entitlements(self.root)), 1)

    def test_main_passes_with_main_session_target_state(self):
        # Apps/CaptureLab/CaptureLab.entitlements plus CODE_SIGN_ENTITLEMENTS in project.yml.
        import contextlib
        import io
        allowed = check_compliance.ALLOWED_CODE_SIGN_ENTITLEMENTS
        self.write(allowed, {"com.apple.developer.screen-recording": True})
        yml = (check_compliance.ROOT / "project.yml").read_text(encoding="utf-8").replace(
            "        GENERATE_INFOPLIST_FILE: NO\n",
            f"        GENERATE_INFOPLIST_FILE: NO\n        CODE_SIGN_ENTITLEMENTS: {allowed}\n", 1)
        (self.root / "project.yml").write_text(yml, encoding="utf-8")
        with mock.patch.object(check_compliance, "ROOT", self.root), \
                mock.patch.object(check_compliance, "SOURCE_DIRS", [self.root / "Apps"]), \
                contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(check_compliance.main([]), 0, out.getvalue())

    def test_main_flags_entitlements_file(self):
        import contextlib
        import io
        self.write("Apps/X/X.entitlements", {"get-task-allow": True})
        with mock.patch.object(check_compliance, "ROOT", self.root), \
                mock.patch.object(check_compliance, "SOURCE_DIRS", [self.root / "Apps"]), \
                contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(check_compliance.main([]), 1)
        self.assertIn("get-task-allow", out.getvalue())


class VerifyEnvironmentTests(unittest.TestCase):
    def test_non_mac_exits_zero(self):
        if sys.platform == "darwin":
            self.skipTest("macOS host")
        self.assertEqual(verify_environment.main(), 0)

    def test_pins_parse(self):
        pins = verify_environment.read_pins()
        self.assertEqual(set(pins), set(verify_environment.TOOLS))

    ADR_TEXT = ("# ADR\n\n- **Toolchain pin** (recorded): Xcode `27.2` (build 27B52), SDK `27.2`\n"
                "  (iOS), Swift `6.4.2`.\n\n- **Other**: Xcode `9.9` (build 9Z9).\n")

    def test_build_pin_parses_from_adr(self):
        self.assertRegex(verify_environment.read_build_pin() or "", r"^\d+[A-Z]\d+[a-z]?$")
        self.assertEqual(verify_environment.read_build_pin(self.ADR_TEXT), "27B52")
        self.assertEqual(verify_environment.read_pins(self.ADR_TEXT)["Xcode"], "27.2")

    def test_build_pin_missing(self):
        self.assertIsNone(verify_environment.read_build_pin(
            "- **Toolchain pin**: Xcode `27.2`, SDK `27.2`.\n\nXcode `27.2` (build 27B52)\n"))
        self.assertIsNone(verify_environment.read_build_pin("no pin paragraph\n"))

    def test_check_build(self):
        ok, msg = verify_environment.check_build("27B52", "27B52")
        self.assertTrue(ok)
        self.assertIn("OK", msg)
        for pin, found, word in (("27B52", "27B53", "does not match"), ("27B52", "27B5", "does not match"),
                                 ("27B52", None, "missing"), (None, "27B52", "unpinned")):
            ok, msg = verify_environment.check_build(pin, found)
            self.assertFalse(ok, (pin, found))
            self.assertIn(word, msg)

    def test_main_fails_on_build_mismatch(self):
        import contextlib
        import io

        def fake_version(cmd, pattern):
            if cmd == verify_environment.XCODE_BUILD_CMD and pattern == verify_environment.XCODE_BUILD_PATTERN:
                return "27A1"
            return verify_environment.read_pins()[next(n for n, (c, _) in verify_environment.TOOLS.items()
                                                       if c == cmd)]

        with mock.patch.object(verify_environment.platform, "system", return_value="Darwin"), \
                mock.patch.object(verify_environment, "tool_version", side_effect=fake_version), \
                contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(verify_environment.main(), 1)
        self.assertIn("Xcode build: 27A1 does not match pin", out.getvalue())

        def fake_match(cmd, pattern):
            if pattern == verify_environment.XCODE_BUILD_PATTERN:
                return verify_environment.read_build_pin()
            return fake_version(cmd, pattern)

        with mock.patch.object(verify_environment.platform, "system", return_value="Darwin"), \
                mock.patch.object(verify_environment, "tool_version", side_effect=fake_match), \
                contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(verify_environment.main(), 0)
        self.assertIn("Xcode build:", out.getvalue())


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
    def export(events, schema_version=2):
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
        data = self.export([("background", 1.0), ("foreground", 2.0)], schema_version=1)
        self.assertTrue(check_capturelab_export.check_export(data))
        self.assertTrue(check_capturelab_export.check_export({"schemaVersion": 2}))

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
