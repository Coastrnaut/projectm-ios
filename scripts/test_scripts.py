#!/usr/bin/env python3
"""Tests for the repository scripts. Run: python scripts/test_scripts.py (Windows or macOS)."""
from __future__ import annotations

import hashlib
import json
import math
import re
import struct
import sys
import tempfile
import unittest
import wave
from unittest import mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_capturelab_export  # noqa: E402
import make_diagnostic_project  # noqa: E402
import build_angle_xcframework as bax  # noqa: E402
import build_projectm_xcframework as bpx  # noqa: E402
import check_compliance  # noqa: E402
import generate_gles_loader as ggl  # noqa: E402
import generate_reference_audio as gra  # noqa: E402
import run_device_tests as rdt  # noqa: E402
import setup_mac  # noqa: E402
import validate_docs  # noqa: E402
import verify_environment  # noqa: E402

FIXTURES = Path(__file__).resolve().parent / "fixtures"


class ValidateDocsTests(unittest.TestCase):
    def test_current_docs_pass(self):
        self.assertEqual(validate_docs.main([]), 0)

    def test_fixture_with_undefined_id_fails(self):
        self.assertEqual(validate_docs.main(["--include-fixtures"]), 1)


class PresetIndexTests(unittest.TestCase):
    """build_preset_index.py (feature 002, T204): priority, .milk only, blocklist, exclusions,
    Included ids and names, author parsing, --check, archive round trip."""

    def setUp(self):
        import build_preset_index as bpi
        self.bpi = bpi
        self.tmp = Path(tempfile.mkdtemp())
        inc = self.tmp / "Presets"
        (inc / "frontend-uwp").mkdir(parents=True)
        (inc / "frontend-uwp" / "Geiss - Dancer.milk").write_text("A")
        (inc / "LICENSES.md").write_text(
            "| File | Display name | Pack | Author | License | Source URL | Source version |\n"
            "|------|------|------|------|------|------|------|\n"
            "| frontend-uwp/Geiss - Dancer.milk | Geiss - Dancer | frontend-uwp | Geiss | X | u | v |\n")
        packs = self.tmp / "packs"
        for pack in ("cream-of-the-crop", "projectm-classic", "milkdrop-original", "en-d", "milkdrop-texture-pack"):
            (packs / pack).mkdir(parents=True)
        cream = packs / "cream-of-the-crop" / "Fractal" / "Nested"
        cream.mkdir(parents=True)
        (cream / "Martin - Spiral.milk").write_text("B")
        (cream / "Copy of included.milk").write_text("A")          # same content as Included
        (cream / "notes.txt").write_text("not a preset")
        classic = packs / "projectm-classic" / "tryptonaut"
        classic.mkdir(parents=True)
        (classic / "dup.MILK").write_text("B")                       # duplicate of cream
        (classic / "NoAuthor.milk").write_text("C")
        (classic / "Blocked - One.milk").write_text("D")
        orig = packs / "milkdrop-original" / "Milkdrop-Original"
        orig.mkdir(parents=True)
        (orig / "Krash - Flat.milk").write_text("E")
        (packs / "en-d" / "Excluded - Me.milk").write_text("F")
        res = self.tmp / "Resources"
        res.mkdir()
        (res / "PresetBlocklist.json").write_text(json.dumps({"hashes": [{"hash": bpi.blob_hash(b"D"), "reason": "t"}]}))
        (res / "PresetExclusions.txt").write_text("en-d/Excluded - Me.milk\n")
        self.out = self.tmp / "out"
        self.args = ["--included-dir", str(inc), "--packs-dir", str(packs), "--config", str(res), "--out", str(self.out)]
        self.res = res

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmp)

    def run_main(self, *extra):
        with mock.patch("builtins.print"), mock.patch("sys.stderr"):
            return self.bpi.main(self.args + list(extra))

    def index(self):
        return json.loads((self.out / "PresetIndex.json").read_text())["presets"]

    def test_priority_milk_only_blocklist_exclusions(self):
        self.assertEqual(self.run_main(), 0)
        ids = [r["id"] for r in self.index()]
        self.assertEqual(ids, ["frontend-uwp/Geiss - Dancer.milk",
                               "cream-of-the-crop/Fractal/Nested/Martin - Spiral.milk",
                               "projectm-classic/tryptonaut/NoAuthor.milk",
                               "milkdrop-original/Milkdrop-Original/Krash - Flat.milk"])

    def test_exclusion_also_drops_identical_copies_in_later_packs(self):
        # T237: excluding the cream copy must not let the identical classic file back in.
        (self.res / "PresetExclusions.txt").write_text("cream-of-the-crop/Fractal/Nested/Martin - Spiral.milk\n")
        self.assertEqual(self.run_main("--force"), 0)
        ids = [r["id"] for r in self.index()]
        self.assertNotIn("cream-of-the-crop/Fractal/Nested/Martin - Spiral.milk", ids)
        self.assertNotIn("projectm-classic/tryptonaut/dup.MILK", ids)
        self.assertEqual(self.run_main("--force", "--no-exclusions"), 0)   # RendererLab's sweep (T236)
        ids = [r["id"] for r in self.index()]
        self.assertIn("cream-of-the-crop/Fractal/Nested/Martin - Spiral.milk", ids)
        self.assertIn("en-d/Excluded - Me.milk", ids)

    def test_display_order_and_archive_positions(self):
        # SC-101: the index lists presets by pack, then name; "archive" maps the archive's order back.
        self.run_main("--force")
        data = json.loads((self.out / "PresetIndex.json").read_text())
        names = [r["name"] for r in data["presets"]]
        self.assertEqual(len(data["archive"]), len([r for r in data["presets"] if r["source"] != "included"]))
        self.assertEqual(sorted(data["archive"]), list(range(1, len(names))))
        key = self.bpi.display_key
        self.assertLess(key("Preset 2"), key("Preset 10"))
        self.assertLess(key("cafe b"), key("Café C"))
        self.assertLess(key("_x"), key("1"))

    def test_names_authors_folders(self):
        self.run_main()
        by_id = {r["id"]: r for r in self.index()}
        inc = by_id["frontend-uwp/Geiss - Dancer.milk"]
        self.assertEqual((inc["name"], inc["author"], inc["source"], inc["path"]),
                         ("Geiss - Dancer", "Geiss", "included", "Presets/frontend-uwp/Geiss - Dancer.milk"))
        spiral = by_id["cream-of-the-crop/Fractal/Nested/Martin - Spiral.milk"]
        self.assertEqual((spiral["name"], spiral["author"], spiral["folder"]), ("Spiral", "Martin", ["Fractal", "Nested"]))
        self.assertEqual(by_id["projectm-classic/tryptonaut/NoAuthor.milk"]["author"], "Unknown")
        self.assertEqual(by_id["milkdrop-original/Milkdrop-Original/Krash - Flat.milk"]["folder"], [])

    def test_stamp_skips_and_inputs_invalidate(self):
        self.run_main()
        (self.out / "PresetIndex.json").write_text("{}")
        self.run_main()                                           # unchanged inputs: skipped
        self.assertEqual((self.out / "PresetIndex.json").read_text(), "{}")
        (self.res / "PresetExclusions.txt").write_text("")         # inputs changed: rebuilt
        self.run_main()
        self.assertEqual(len(self.index()), 5)

    def test_archive_round_trip(self):
        import struct, zlib
        self.assertEqual(self.run_main(), 0)
        blob = (self.out / "PresetArchive.bin").read_bytes()
        magic, version, count, chunk_size, chunks = struct.unpack_from("<4sIIII", blob, 0)
        self.assertEqual((magic, version, count), (b"PMPA", 1, 3))
        off, clen, rlen = struct.unpack_from("<QII", blob, 20)
        raw = zlib.decompress(blob[off:off + clen], -15)
        self.assertEqual(len(raw), rlen)
        chunk, start, length = struct.unpack_from("<III", blob, 20 + 16 * chunks)   # first pack preset
        self.assertEqual(raw[start:start + length], b"B")


class LicensesManifestTests(unittest.TestCase):
    def test_committed_manifest_is_complete(self):
        import collect_licenses
        with mock.patch("builtins.print"):
            self.assertEqual(collect_licenses.check(), 0)


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


class ComplianceOSCExceptionTests(unittest.TestCase):
    """FR-068 as amended 2026-11-12: the Network framework only in the OSC transport folder."""

    def write(self, folder: Path, text: str) -> Path:
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / "File.swift"
        path.write_text(text, encoding="utf-8")
        return path

    def test_network_framework_allowed_only_in_the_osc_transport_folder(self):
        with tempfile.TemporaryDirectory() as d:
            allowed = Path(d) / "OSCTransport"
            with mock.patch.object(check_compliance, "OSC_ALLOWED", allowed):
                source = "import Network\nlet l = try NWListener(using: .udp)\n"
                self.assertEqual(check_compliance.check_file(self.write(allowed, source)), [])
                self.assertEqual(check_compliance.check_file(self.write(allowed / "Sub", source)), [])
                outside = check_compliance.check_file(self.write(Path(d) / "Elsewhere", source))
                self.assertEqual(len(outside), 1)
                self.assertIn("outside PerformanceControl/OSCTransport", outside[0])
                sibling = check_compliance.check_file(self.write(Path(d) / "OSCTransportX", source))
                self.assertEqual(len(sibling), 1)

    def test_other_networking_apis_stay_forbidden_inside_the_folder(self):
        with tempfile.TemporaryDirectory() as d:
            allowed = Path(d) / "OSCTransport"
            with mock.patch.object(check_compliance, "OSC_ALLOWED", allowed):
                for source in ("let s = URLSession.shared\n", "import WebKit\n",
                               "#include <sys/socket.h>\n", "import CFNetwork\n"):
                    found = check_compliance.check_file(self.write(allowed, source))
                    self.assertTrue(any("networking API (FR-068)" in f for f in found), source)

    def test_path_monitor_and_connections_are_flagged_elsewhere(self):
        with tempfile.TemporaryDirectory() as d:
            for source in ("let m = NWPathMonitor()\n", "var c: NWConnection?\n",
                           "let b = NWBrowser(for: x, using: .udp)\n"):
                self.assertTrue(check_compliance.check_file(self.write(Path(d), source)), source)

    def test_exception_folder_is_the_documented_one(self):
        self.assertEqual(check_compliance.OSC_ALLOWED.relative_to(check_compliance.ROOT).as_posix(),
                         "Packages/PerformanceControl/Sources/PerformanceControl/OSCTransport")


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


class UIStringsImportContractTests(unittest.TestCase):
    """AUD-001: every string in specs/003's ui-strings contract is in CaptureUI's UIStrings.swift."""

    ROOT = Path(__file__).resolve().parent.parent
    CONTRACT = ROOT / "specs" / "003-aud-001-import-drm-free-audio-files" / "contracts" / "ui-strings.md"
    SWIFT = ROOT / "Packages" / "CaptureUI" / "Sources" / "CaptureUI" / "UIStrings.swift"

    def contract_strings(self) -> list[str]:
        found: list[str] = []
        for line in self.CONTRACT.read_text(encoding="utf-8").splitlines():
            if not line.startswith("|"):
                continue
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) != 2 or set(cells[0]) <= set("-: ") or cells[1] == "String":
                continue
            found.append(cells[1])
        return found

    def test_every_contract_string_is_in_swift(self):
        swift = self.SWIFT.read_text(encoding="utf-8")
        strings = self.contract_strings()
        self.assertEqual(len(strings), 23)
        missing = []
        for text in strings:
            # A substituted value (‹name›) splits the string; each literal part must be present.
            parts = [part for part in re.split(r"‹[^›]*›", text) if len(part) >= 3] if "‹" in text else [f'"{text}"']
            self.assertTrue(parts, text)
            missing += [text for part in parts if part not in swift]
        self.assertEqual(missing, [])


class UIStringsContainerContractTests(unittest.TestCase):
    """AUD-002: every string in specs/006's ui-strings contract is in CaptureUI's UIStrings.swift."""

    ROOT = Path(__file__).resolve().parent.parent
    CONTRACT = ROOT / "specs" / "006-aud-002-support-common-audio-containers" / "contracts" / "ui-strings.md"
    SWIFT = ROOT / "Packages" / "CaptureUI" / "Sources" / "CaptureUI" / "UIStrings.swift"

    def test_every_contract_string_is_in_swift(self):
        rows = []
        for line in self.CONTRACT.read_text(encoding="utf-8").splitlines():
            if not line.startswith("|"):
                continue
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) != 2 or set(cells[0]) <= set("-: ") or cells[1] == "String":
                continue
            rows.append(cells)
        self.assertEqual([case for case, _ in rows], ["unsupportedFormat", "unsupportedEncoding", "noAudio"])
        swift = self.SWIFT.read_text(encoding="utf-8")
        for case, text in rows:
            needle = f'case .{case}: return "{text}"'
            self.assertTrue(needle in swift, needle)


class UIStringsTransportContractTests(unittest.TestCase):
    """AUD-006: every string in specs/007's ui-strings contract is in CaptureUI's UIStrings.swift."""

    ROOT = Path(__file__).resolve().parent.parent
    CONTRACT = ROOT / "specs" / "007-aud-006-seekable-transport" / "contracts" / "ui-strings.md"
    SWIFT = ROOT / "Packages" / "CaptureUI" / "Sources" / "CaptureUI" / "UIStrings.swift"

    def test_every_contract_string_is_in_swift(self):
        rows = []
        for line in self.CONTRACT.read_text(encoding="utf-8").splitlines():
            if not line.startswith("|"):
                continue
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) != 2 or set(cells[0]) <= set("-: ") or cells[1] == "String":
                continue
            rows.append(cells)
        self.assertEqual([name for name, _ in rows], ["play", "pause", "stop", "previousTrack", "nextTrack", "scrubber",
                                                     "referenceTrackTitle", "scrubberValue"])
        swift = self.SWIFT.read_text(encoding="utf-8")
        for name, text in rows:
            # A substituted value (‹elapsed›) splits the string; each literal part must be present.
            parts = [part for part in re.split(r"‹[^›]*›", text) if len(part) >= 3] if "‹" in text else [f'"{text}"']
            self.assertTrue(parts, name)
            for part in parts:
                self.assertIn(part, swift, name)


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
        # Device runs without lifecycle events: `--expect none` skips the order check.
        self.assertEqual(check_capturelab_export.check_export(self.export([]), ()), [])
        self.assertEqual(check_capturelab_export.parse_expect("none"), ())
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



class DiagnosticProjectTests(unittest.TestCase):
    """scripts/make_diagnostic_project.py (ADR-0001 ruling 12): variants never touch project.yml."""

    SPEC = (check_compliance.ROOT / "project.yml").read_text(encoding="utf-8")

    def test_no_usage_key_removes_only_the_key(self):
        out = make_diagnostic_project.variant_spec(self.SPEC, "no-usage-key")
        self.assertNotIn("NSScreenCaptureUsageDescription:", out)
        self.assertIn("NSMicrophoneUsageDescription", out)
        self.assertIn('CFBundleVersion: "9002"', out)
        self.assertIn("UIBackgroundModes: [screen-capture]", out, "keeps the normal build's mode")
        self.assertNotIn("projectM-iOS", out, "the diagnostic project is CaptureLab only")
        self.assertNotIn("ANGLERendering", out)
        self.assertIn("CaptureLabUITests:", out)

    def test_screen_capture_variant_retired(self):
        # ADR-0001 ruling 17 put the mode into the normal build, so the variant is gone.
        self.assertNotIn("screen-capture-mode", make_diagnostic_project.VARIANTS)

    def test_changed_spec_fails_loudly(self):
        with self.assertRaises(ValueError):
            make_diagnostic_project.variant_spec("name: Other\n", "no-usage-key")


class BackgroundModeExceptionTests(unittest.TestCase):
    """ADR-0001 ruling 17: project.yml may declare exactly UIBackgroundModes: [screen-capture]."""

    def check(self, yml: str) -> list[str]:
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "project.yml"
            p.write_text(yml, encoding="utf-8")
            return check_compliance.check_project_yml(p)

    def test_allowed_forms_pass(self):
        for line in ("UIBackgroundModes: [screen-capture]", 'UIBackgroundModes: ["screen-capture"]',
                     "'UIBackgroundModes': [ 'screen-capture' ]  # ruling 17"):
            self.assertEqual(self.check(f"info:\n  properties:\n    {line}\n"), [], line)

    def test_other_values_and_forms_flagged(self):
        for body in ("    UIBackgroundModes: [audio]\n",
                     "    UIBackgroundModes: [screen-capture, audio]\n",
                     "    UIBackgroundModes:\n      - screen-capture\n",
                     "    UIBackgroundModes: screen-capture\n"):
            found = self.check("info:\n  properties:\n" + body)
            self.assertTrue(any("UIBackgroundModes" in v for v in found), body)

    def test_project_yml_declares_the_mode(self):
        text = (check_compliance.ROOT / "project.yml").read_text(encoding="utf-8")
        self.assertIn("UIBackgroundModes: [screen-capture]", text)
        self.assertEqual(check_compliance.check_project_yml(check_compliance.ROOT / "project.yml"), [])

class DeviceTestRunnerTests(unittest.TestCase):
    """run_device_tests.py (feature 002 T238, T239, T241): device mapping, privacy check, size
    report parsing, SC-103 log lines and verdicts. The device steps themselves need devices."""

    def test_devices_from_listing_maps_models_to_labels(self):
        listing = {"result": {"devices": [
            {"identifier": "A", "hardwareProperties": {"productType": "iPhone15,4", "reality": "physical"}},
            {"identifier": "B", "hardwareProperties": {"productType": "iPad15,7", "reality": "physical"}},
            {"identifier": "C", "hardwareProperties": {"productType": "iPhone18,3", "reality": "physical"}},
        ]}}
        self.assertEqual(rdt.devices_from_listing(listing), {"D1": "A", "D3": "B"})

    def test_privacy_allows_fr065_keys_reports_others(self):
        keys = ["favorites", "settings.presetScope", "SKTransactionUpdatesLastChecked", "unlocked"]
        files = ["Documents/automation-privacy-2026.json", "Documents/recording.wav", "tmp/x.bin",
                 "Library/Caches/org.projectmios.ProjectMiOS/com.apple.metalfe/A/monolithic_metal.pcm"]
        self.assertEqual(rdt.privacy_problems(files, keys),
                         ["key not allowed: unlocked", "unexpected file: Documents/recording.wav",
                          "audio file: Documents/recording.wav", "unexpected file: tmp/x.bin"])

    def test_privacy_allows_only_the_imported_audio_library(self):
        # AUD-001-R22: audio the user imported lives in the library's own folders, nowhere else.
        digest = "ab" * 32
        library = "Library/Application Support/AudioLibrary"
        allowed = [f"{library}/index.json", f"{library}/index.damaged.json", f"{library}/assets/{digest}.wav",
                   f"{library}/assets/{digest}.mp3", f"{library}/incoming/5F0C1E0A-0000-4000-8000-000000000000.m4a"]
        self.assertEqual(rdt.privacy_problems(allowed, []), [])
        elsewhere = ["Library/Application Support/recording.wav", f"Library/Caches/AudioLibrary/assets/{digest}.wav",
                     f"{library}/assets/sub/{digest}.wav", f"{library}/capture.caf",
                     f"Documents/AudioLibrary/assets/{digest}.wav", f"{library}/assets/not-a-hash.wav"]
        problems = rdt.privacy_problems(elsewhere, [])
        for path in elsewhere:
            self.assertIn(f"audio file: {path}", problems)

    def test_thinning_report_and_growth(self):
        old = rdt.parse_thinning_report(
            "App Thinning Size Report for All Variants of projectM\n\n"
            "Variant: projectM-1.ipa\nSupported variant descriptors: [device: iPhone15,4, os-version: 26.0]\n"
            "App + On Demand Resources size: 20 MB compressed, 60 MB uncompressed\n"
            "App size: 20 MB compressed, 60 MB uncompressed\n\n"
            "Variant: projectM-2.ipa\nSupported variant descriptors: [device: iPad15,7, os-version: 26.0], "
            "[device: iPad17,3, os-version: 26.0]\nApp size: 21 MB compressed, 61,5 MB uncompressed\n")
        self.assertEqual(old, {"iPhone15,4": 60.0})   # an unparseable size is skipped, not guessed
        new = rdt.parse_thinning_report("Variant: v\n[device: iPhone15,4, os-version: 26.0]\n"
                                        "App size: 30 MB compressed, 86.5 MB uncompressed\n")
        self.assertEqual(rdt.size_growth(old, new), {"D1 iPhone15,4": {"oldMB": 60.0, "newMB": 86.5, "growthMB": 26.5}})

    def test_sc103_lines_and_verdicts(self):
        log = "noise\nSC103 all frames=600 missed=12 onTime=0.9804\nSC103 largest-folder frames=500 missed=40 onTime=0.9259\n"
        lines = rdt.sc103_lines(log)
        self.assertEqual(lines["all"], {"frames": 600, "missed": 12, "onTime": 0.9804})
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            (d / "sc103.json").write_text(json.dumps(lines))
            (d / "sc101.json").write_text(json.dumps([0.02, 0.09]))
            (d / "automation-sc102-1.json").write_text(json.dumps({"keystrokes": 9, "medianMs": 2.0, "maxMs": 51.0}))
            (d / "automation-sc104-1.json").write_text(json.dumps({"fractionUnder1s": 0.96, "p95Ms": 800, "picksByPack": {}}))
            verdicts = {k: ok for k, (ok, _) in rdt.verdicts_for(d).items()}
        self.assertEqual(verdicts, {"SC-101": True, "SC-102": False, "SC-104": True,
                                    "SC-103 all": True, "SC-103 largest-folder": False})


class ProjectMXCFrameworkTests(unittest.TestCase):
    """T065: the engine build flags (ADR-0004) and the pinned engine version."""

    def args(self, name):
        s = next(s for s in bpx.SLICES if s["name"] == name)
        return bpx.cmake_args(s, Path("src"), Path("b"))

    def test_device_and_simulator_slices(self):
        self.assertEqual({s["name"]: s["archs"] for s in bpx.SLICES},
                         {"iphoneos": ("arm64",), "iphonesimulator": ("arm64", "x86_64")})
        self.assertIn("-DCMAKE_OSX_SYSROOT=iphoneos", self.args("iphoneos"))
        self.assertIn("-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64", self.args("iphonesimulator"))

    def test_flags_build_a_shared_gles_framework_from_vendored_sources(self):
        a = self.args("iphoneos")
        for flag in ("-DCMAKE_SYSTEM_NAME=iOS", "-DBUILD_SHARED_LIBS=ON", "-DENABLE_MACOS_FRAMEWORK=ON",
                     "-DENABLE_GLES=ON", "-DENABLE_SYSTEM_PROJECTM_EVAL=OFF", "-DENABLE_SYSTEM_GLM=OFF",
                     "-DENABLE_PLAYLIST=OFF", "-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0", "-DCMAKE_BUILD_TYPE=Release"):
            self.assertIn(flag, a)

    def test_engine_version_is_read_from_cmake(self):
        with tempfile.TemporaryDirectory() as d:
            Path(d, "CMakeLists.txt").write_text("project(libprojectM\n    LANGUAGES C CXX\n    VERSION 4.2.0\n)\n",
                                                 encoding="utf-8")
            self.assertEqual(bpx.engine_version(Path(d)), "4.2.0")

    def test_submodule_tracks_the_fork_ios_branch(self):
        text = (Path(__file__).resolve().parent.parent / ".gitmodules").read_text(encoding="utf-8")
        self.assertIn("url = https://github.com/Coastrnaut/projectm.git", text)
        self.assertIn("branch = ios", text)


class GLESLoaderTests(unittest.TestCase):
    """T068/T069: the static OpenGL ES load-proc table (no dlsym, Constitution I)."""

    HEADER = """
GL_API void           GL_APIENTRY glActiveTexture (GLenum texture) OPENGLES_DEPRECATED(ios(3.0, 12.0));
GL_API const GLubyte* GL_APIENTRY glGetString (GLenum name)  OPENGLES_DEPRECATED(ios(3.0, 12.0));
GL_API void           GL_APIENTRY glActiveTexture (GLenum texture);
#define GL_APIENTRY_NOT_A_FUNCTION 1
/* GL_API void GL_APIENTRY glCommentedOut (void); */
"""

    def test_parses_declarations_sorted_and_unique(self):
        names = ggl.function_names(self.HEADER)
        self.assertEqual(names, ["glActiveTexture", "glGetString"])

    def test_rendered_table_is_sorted_and_has_no_dlsym(self):
        text = ggl.render(["glActiveTexture", "glGetString"], "27.2")
        self.assertLess(text.index('"glActiveTexture"'), text.index('"glGetString"'))
        self.assertIn("bsearch", text)
        self.assertNotRegex(text, r"\b(dlsym|dlopen)\s*\(")

    def test_committed_table_has_no_dynamic_lookup(self):
        text = ggl.OUTPUT.read_text(encoding="utf-8")
        self.assertNotRegex(text, r"\b(dlsym|dlopen)\s*\(")
        self.assertGreaterEqual(text.count('{"gl'), 200)


class ANGLEXCFrameworkTests(unittest.TestCase):
    """T076: ANGLE build arguments, output location and the deletion guard."""

    def test_metal_only_release_build_for_ios(self):
        for s in bax.SLICES:
            a = bax.gn_args(s)
            for arg in ('target_os="ios"', "is_debug=false", "angle_enable_metal=true", "angle_enable_gl=false",
                        "angle_enable_vulkan=false", "angle_enable_swiftshader=false", "angle_build_tests=false",
                        "ios_enable_code_signing=false", 'ios_deployment_target="26.0"'):
                self.assertIn(arg, a)
        self.assertEqual({(s["environment"], s["cpu"]) for s in bax.SLICES},
                         {("device", "arm64"), ("simulator", "arm64"), ("simulator", "x64")})

    def test_output_never_shares_a_case_insensitive_name_with_the_source(self):
        names = {p.resolve().as_posix().lower() for p in (bax.SOURCE, bax.DEPOT_TOOLS)}
        for out in (bax.OUTPUT, bax.STAGING):
            low = out.resolve().as_posix().lower()
            self.assertFalse(any(n == low or n.startswith(low + "/") for n in names), out)

    def test_remove_tree_refuses_folders_holding_the_source(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            source = root / "Build" / "angle"
            source.mkdir(parents=True)
            with mock.patch.object(bax, "SOURCE", source), mock.patch.object(bax, "DEPOT_TOOLS", root / "none"):
                with self.assertRaises(SystemExit):
                    bax.remove_tree(root / "Build")
                with self.assertRaises(SystemExit):
                    bax.remove_tree(source)
                # A differently-cased spelling of the same folder (case-insensitive volumes).
                spelled = root / "Build" / "ANGLE"
                if spelled.exists():
                    with self.assertRaises(SystemExit):
                        bax.remove_tree(spelled)
                other = root / "Build" / "ANGLEFrameworks"
                other.mkdir()
                bax.remove_tree(other)
                self.assertFalse(other.exists())
                self.assertTrue(source.exists())

    def test_pins_are_full_commits_and_submodule_tracks_the_fork(self):
        self.assertRegex(bax.ANGLE_COMMIT, r"^[0-9a-f]{40}$")
        self.assertRegex(bax.DEPOT_TOOLS_COMMIT, r"^[0-9a-f]{40}$")
        text = (Path(__file__).resolve().parent.parent / ".gitmodules").read_text(encoding="utf-8")
        self.assertIn("url = https://github.com/Coastrnaut/angle.git", text)


class SetupMacTests(unittest.TestCase):
    def test_memory_dir_matches_claudes_folder_name(self):
        got = setup_mac.memory_dir(Path("/Users/coast/Documents/GIT/projectm-ios"), Path("/Users/coast"))
        self.assertEqual(str(got), "/Users/coast/.claude/projects/-Users-coast-Documents-GIT-projectm-ios/memory")
        dotted = setup_mac.memory_dir(Path("/Users/a.b/my repo"), Path("/h"))
        self.assertEqual(dotted.parent.name, "-Users-a-b-my-repo")

    def test_latest_feature_is_the_highest_number(self):
        with tempfile.TemporaryDirectory() as tmp:
            specs = Path(tmp) / "specs"
            self.assertIsNone(setup_mac.latest_feature(specs))
            for name in ("001-first", "002-second", "notes"):
                (specs / name).mkdir(parents=True)
            self.assertEqual(setup_mac.latest_feature(specs), "specs/002-second")
        # The repository's own specs: the highest-numbered directory, whatever it is now (the
        # autonomous roadmap adds one per feature; PERF-011 added 004).
        numbered = sorted(d.name for d in (setup_mac.ROOT / "specs").iterdir() if d.is_dir() and d.name[:3].isdigit())
        self.assertGreaterEqual(numbered[-1], "002-preset-library-unlock")
        self.assertEqual(setup_mac.latest_feature(setup_mac.ROOT / "specs"), f"specs/{numbered[-1]}")

    def test_angle_ready_needs_both_libraries(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            self.assertFalse(setup_mac.angle_ready(folder))
            (folder / "libEGL.xcframework").mkdir()
            self.assertFalse(setup_mac.angle_ready(folder))
            (folder / "libGLESv2.xcframework").mkdir()
            self.assertTrue(setup_mac.angle_ready(folder))

    def test_missing_tools_names_each_absent_command(self):
        self.assertEqual(setup_mac.missing_tools(lambda name: "/bin/" + name), [])
        missing = setup_mac.missing_tools(lambda name: None if name == "xcodegen" else "/bin/" + name)
        self.assertEqual(len(missing), 1)
        self.assertTrue(missing[0].startswith("xcodegen: brew install xcodegen"))

    def test_restore_memory_copies_the_export_and_never_overwrites(self):
        exported = sorted(p.name for p in setup_mac.MEMORY_EXPORT.glob("*.md") if p.name != "README.md")
        self.assertIn("MEMORY.md", exported)
        self.assertEqual(len(exported), 4)
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            target = setup_mac.memory_dir(setup_mac.ROOT, home)
            target.mkdir(parents=True)
            (target / "MEMORY.md").write_text("mine\n", encoding="utf-8")
            with mock.patch("builtins.print"):
                setup_mac.restore_memory(setup_mac.Runner(dry_run=False), home)
            self.assertEqual(sorted(p.name for p in target.iterdir()), exported)
            self.assertEqual((target / "MEMORY.md").read_text(encoding="utf-8"), "mine\n")

    def test_dry_run_changes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            with mock.patch("builtins.print"):
                setup_mac.restore_memory(setup_mac.Runner(dry_run=True), home)
                self.assertEqual(setup_mac.Runner(dry_run=True).run(["false"]), 0)
            self.assertEqual(list(home.iterdir()), [])

    def test_setup_never_writes_the_signing_file(self):
        source = (setup_mac.ROOT / "scripts" / "setup_mac.py").read_text(encoding="utf-8")
        self.assertNotIn("SIGNING.write", source)
        self.assertNotIn("DEVELOPMENT_TEAM =", source.replace("`DEVELOPMENT_TEAM = <team ID>`", ""))


if __name__ == "__main__":
    unittest.main(verbosity=2)
