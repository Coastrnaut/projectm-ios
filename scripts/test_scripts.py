#!/usr/bin/env python3
"""Tests for the repository scripts. Run: python scripts/test_scripts.py (Windows or macOS)."""
from __future__ import annotations

import hashlib
import contextlib
import io
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
import check_privacy_manifest as cpm  # noqa: E402
import check_permission_catalog as cpc  # noqa: E402
import check_network_symbols as cns  # noqa: E402
import check_motion_policy as cmp  # noqa: E402
import check_status_events as cse  # noqa: E402
import observe_app_network as oan  # noqa: E402
import generate_gles_loader as ggl  # noqa: E402
import generate_reference_audio as gra  # noqa: E402
import run_device_tests as rdt  # noqa: E402
import check_performance_thresholds as cpt  # noqa: E402
import setup_mac  # noqa: E402
import validate_docs  # noqa: E402
import qa009_manifest_check as qa009  # noqa: E402
import qa011_inventory as qa011  # noqa: E402
import run_device_matrix as rdm  # noqa: E402
import release_manifest as rmf  # noqa: E402
import verify_environment  # noqa: E402
import mac_device_driver as mdd  # noqa: E402
import mac_driver  # noqa: E402
import make_media_fixtures as mmf  # noqa: E402
import install_test_fixtures as itf  # noqa: E402

FIXTURES = Path(__file__).resolve().parent / "fixtures"


class PrivacyManifestTests(unittest.TestCase):
    """check_privacy_manifest.py (REC-015-T13): reasons per category; undeclared uses flagged."""

    def manifest(self, entries):
        return {"NSPrivacyTracking": False, "NSPrivacyTrackingDomains": [], "NSPrivacyCollectedDataTypes": [],
                "NSPrivacyAccessedAPITypes": [{"NSPrivacyAccessedAPIType": c, "NSPrivacyAccessedAPITypeReasons": r}
                                              for c, r in entries]}

    def test_app_manifest_declares_disk_space_e174(self):
        import plistlib
        path = Path(__file__).resolve().parent.parent / "Apps" / "projectM-iOS" / "PrivacyInfo.xcprivacy"
        manifest = plistlib.loads(path.read_bytes())
        used = {"projectM-iOS": {"NSPrivacyAccessedAPICategoryDiskSpace", "NSPrivacyAccessedAPICategoryUserDefaults",
                                 "NSPrivacyAccessedAPICategorySystemBootTime"},
                "libEGL": {"NSPrivacyAccessedAPICategoryFileTimestamp"}}
        self.assertEqual(cpm.manifest_problems(manifest, used), [])

    def test_disk_space_with_e174_is_accepted(self):
        m = self.manifest([("NSPrivacyAccessedAPICategoryDiskSpace", ["E174.1"])])
        self.assertEqual(cpm.manifest_problems(m, {"app": {"NSPrivacyAccessedAPICategoryDiskSpace"}}), [])

    def test_undeclared_disk_space_is_flagged(self):
        m = self.manifest([("NSPrivacyAccessedAPICategoryUserDefaults", ["CA92.1"])])
        problems = cpm.manifest_problems(m, {"app": {"NSPrivacyAccessedAPICategoryDiskSpace"}})
        self.assertEqual(problems, ["app uses NSPrivacyAccessedAPICategoryDiskSpace but the manifest has no reason for it"])

    def test_other_disk_space_reasons_are_flagged(self):
        m = self.manifest([("NSPrivacyAccessedAPICategoryDiskSpace", ["E174.1", "85F4.1"])])
        problems = cpm.manifest_problems(m, {"app": {"NSPrivacyAccessedAPICategoryDiskSpace"}})
        self.assertEqual(len(problems), 1)
        self.assertIn("85F4.1", problems[0])

    def test_debug_dylib_is_scanned(self):
        import plistlib
        with tempfile.TemporaryDirectory() as tmp:
            app = Path(tmp) / "X.app"
            app.mkdir()
            (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "X"}))
            (app / "X").write_bytes(b"stub")
            self.assertEqual([p.name for p in cpm.binaries(app)], ["X"])
            (app / "X.debug.dylib").write_bytes(b"code")
            self.assertEqual([p.name for p in cpm.binaries(app)], ["X", "X.debug.dylib"])

    def test_empty_reasons_and_tracking_are_flagged(self):
        m = self.manifest([("NSPrivacyAccessedAPICategoryDiskSpace", [])])
        m["NSPrivacyTracking"] = True
        problems = cpm.manifest_problems(m, {"app": {"NSPrivacyAccessedAPICategoryDiskSpace"}})
        self.assertIn("NSPrivacyTracking must be false", problems)
        self.assertTrue(any("has no reason" in p for p in problems))


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


FLASH_FIXTURES = Path(__file__).resolve().parent.parent / "Packages" / "PresetLibrary" / "Tests" / "PresetLibraryTests" / "FlashFixtures"


class FlashRiskTests(unittest.TestCase):
    """preset_flash_risk.py (ACC-002-T03, T07, T08): the shared fixtures' verdicts (the Swift twin
    checks the same expected.json), the index field and the schema."""

    def test_fixtures_match_expected(self):
        import preset_flash_risk
        expected = json.loads((FLASH_FIXTURES / "expected.json").read_text())
        files = sorted(p.name for p in FLASH_FIXTURES.glob("*.milk"))
        self.assertEqual(files, sorted(expected))
        for name, rules in expected.items():
            with self.subTest(name):
                self.assertEqual(preset_flash_risk.classify((FLASH_FIXTURES / name).read_text(encoding="utf-8")), rules)

    def test_known_high_flash_fixture_is_flagged_and_calm_is_not(self):
        import preset_flash_risk
        self.assertTrue(preset_flash_risk.may_flash((FLASH_FIXTURES / "high-flash.milk").read_text()))
        self.assertFalse(preset_flash_risk.may_flash((FLASH_FIXTURES / "calm.milk").read_text()))

    def test_shader_strobe_rule_matches_the_swift_cases(self):
        """QA-011 2026-11-19: the same cases as PresetFlashRiskTests.testShaderSwitchesNeedAFastUniformClockDrivingRet."""
        import preset_flash_risk as r

        def rules(comp, warp=()):
            lines = ["MILKDROP_PRESET_VERSION=201", "[preset00]", "per_frame_1=wave_r = 0.5 + 0.5*sin(time*0.7);"]
            lines += [f"warp_{i + 1}=`{s}" for i, s in enumerate(warp)] + [f"comp_{i + 1}=`{s}" for i, s in enumerate(comp)]
            return r.classify("\n".join(lines))

        flagged = ["shader-strobe"]
        self.assertEqual(rules(["ret = lerp(ret, 1 - ret, step(0.5, frac(time * 1.5)));"]), flagged)
        self.assertEqual(rules(["if (frame%2 == 0) ret.x = .71 - ret.y;"]), flagged)
        self.assertEqual(rules(["ret *= 1 + step(1.2, bass);"]), flagged)
        self.assertEqual(rules(["ret = lerp(ret, 1 - ret, step(0.5, frac(time * 0.5)));"]), [])
        self.assertEqual(rules(["ret *= 1 + step(0.5, frac(time/4));"]), [])
        self.assertEqual(rules(["ret += step(0.5, frac(uv.x*10 + time*4));"]), [])
        self.assertEqual(rules(["ret = tex2D(sampler_main, uv + 0.02*step(0.5, frac(time*8))).xyz;"]), [])
        self.assertEqual(rules(["ret += 0.05*step(0.5, frac(time*8));"]), [])
        self.assertEqual(rules(["float s = step(0.5, frac(time*4)) * GetBlur1(uv).x;", "ret *= 1 + s;"]), [])
        self.assertEqual(rules(["ret = tex2D(sampler_main, uv).xyz;"], ["if (frame%2 == 0) ret = 1 - ret;"]), flagged)
        self.assertEqual(rules(["ret = tex2D(sampler_main, uv).xyz;"], ["if (frame%2 == 0) ret *= 2;"]), [])
        self.assertEqual(rules(["// ret = 1 - ret*step(0.5, frac(time*4));", "/* ret = 1 - ret*step(0.5, frac(time*4)); */ ret = ret;"]), [])
        self.assertEqual([p for _, _, p in r._fmod_periods("step(1, fmod(time*3, 2))")], [2.0])
        self.assertEqual(r._clock_rate("step(1, fmod(time*3, 2))", r.CLOCK_HZ), 1.5)
        self.assertEqual(r._clock_rate("frame%4", r.CLOCK_HZ), 15.0)

    def test_index_carries_flash_only_for_flagged_records(self):
        import build_preset_index as bpi
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            inc = tmp / "Presets"
            inc.mkdir()
            (inc / "LICENSES.md").write_text("| File | Display name | Pack | Author |\n|---|---|---|---|\n")
            (inc / "Calm.milk").write_bytes((FLASH_FIXTURES / "calm.milk").read_bytes())
            packs = tmp / "packs"
            for pack in ("cream-of-the-crop", "projectm-classic", "milkdrop-original", "en-d", "milkdrop-texture-pack"):
                (packs / pack).mkdir(parents=True)
            (packs / "en-d" / "Fixture - Strobe.milk").write_bytes((FLASH_FIXTURES / "high-flash.milk").read_bytes())
            out = tmp / "out"
            with mock.patch("builtins.print"):
                self.assertEqual(bpi.main(["--included-dir", str(inc), "--packs-dir", str(packs),
                                           "--config", str(tmp / "none"), "--out", str(out)]), 0)
            data = json.loads((out / "PresetIndex.json").read_text())
            self.assertEqual(data["version"], 1)
            by_name = {r["name"]: r for r in data["presets"]}
            self.assertNotIn("flash", by_name["Calm"])
            self.assertEqual(by_name["Strobe"]["flash"], ["toggle-driven", "luma-flicker"])
            schema = json.loads((Path(__file__).resolve().parent.parent / "specs/002-preset-library-unlock/contracts/preset-index.schema.json").read_text())
            item = schema["properties"]["presets"]["items"]
            for record in data["presets"]:
                self.assertTrue(set(item["required"]) <= set(record))
                self.assertTrue(set(record) <= set(item["properties"]), record.keys())
            self.assertEqual(sorted(item["properties"]["flash"]["items"]["enum"]), sorted(["toggle-driven", "toggle-flip", "luma-flicker", "shader-strobe"]))

    def test_stamp_covers_the_classifier(self):
        import build_preset_index as bpi
        self.assertIn("preset_flash_risk.__file__", Path(bpi.__file__).read_text())


class LicensesManifestTests(unittest.TestCase):
    def test_committed_manifest_is_complete(self):
        import collect_licenses
        with mock.patch("builtins.print"):
            self.assertEqual(collect_licenses.check(), 0)


class QA009ManifestTests(unittest.TestCase):
    """QA-009-R8: the primary-screen manifest's identifiers exist in the app's source (contract M4)."""

    MANIFEST = (
        "        PrimaryScreen(name: \"x\", feature: \"X\", auditKey: \"x\", route: .settings, controls: [\n"
        "            RequiredControl(\"plainRow\", .button),\n"
        "            RequiredControl(\"quality.max\", .button),\n"
        "            RequiredControl(\"license:app\", .button),\n"
        "            RequiredControl(\"cue3\", .any),\n"
        "        ]),\n"
    )
    VIEW = (
        'Text("A").accessibilityIdentifier("plainRow")\n'
        'Text("B").accessibilityIdentifier("quality." + raw)\n'
        'Text("C").accessibilityIdentifier("license:\\(id)")\n'
        'Text("D").accessibilityIdentifier("cue\\(n)")\n'
    )

    def make_repo(self, view: str) -> Path:
        root = Path(tempfile.mkdtemp())
        (root / "Apps/projectM-iOS/UITests").mkdir(parents=True)
        (root / "Apps/projectM-iOS/Views").mkdir(parents=True)
        (root / qa009.MANIFEST).write_text(self.MANIFEST, encoding="utf-8")
        (root / "Apps/projectM-iOS/Views/V.swift").write_text(view, encoding="utf-8")
        # An identifier only in a test target does not count.
        (root / "Apps/projectM-iOS/UITests/T.swift").write_text('app.buttons["renamedRow"]', encoding="utf-8")
        return root

    def test_repository_manifest_identifiers_all_exist(self) -> None:
        self.assertEqual(qa009.missing(qa009.ROOT), [])
        self.assertGreaterEqual(len(qa009.manifest_identifiers((qa009.ROOT / qa009.MANIFEST).read_text(encoding="utf-8"))), 40)

    def test_literal_and_dynamic_identifiers_are_found(self) -> None:
        self.assertEqual(qa009.missing(self.make_repo(self.VIEW)), [])

    def test_a_renamed_identifier_fails_by_name(self) -> None:
        root = self.make_repo(self.VIEW.replace('"plainRow"', '"renamedRow"').replace('"quality." + raw', '"profile." + raw'))
        self.assertEqual(qa009.missing(root), ["plainRow", "quality.max"])
        with mock.patch("sys.stdout", new=io.StringIO()) as out:
            self.assertEqual(qa009.main(["qa009", str(root)]), 1)
        self.assertIn("plainRow", out.getvalue())


class ComplianceTests(unittest.TestCase):
    def test_clean_tree_passes(self):
        self.assertEqual(check_compliance.main([]), 0)

    def test_fixture_flags_every_rule(self):
        found = check_compliance.check_file(FIXTURES / "Violations.swift.txt")
        text = "\n".join(found)
        for expected in ["ReplayKit", "networking", "dynamic symbol", "class/selector", "ScreenCaptureKit imported outside"]:
            self.assertIn(expected, text)
        self.assertEqual(check_compliance.main(["--paths", str(FIXTURES / "Violations.swift.txt")]), 1)

    def test_network_and_bluetooth_midi_are_flagged(self):
        """MIDI-001-R2, R14 (ADR-0038): network MIDI and Bluetooth pairing in source fail; discovery passes."""
        with tempfile.TemporaryDirectory() as d:
            bad = Path(d) / "Bad.swift"
            bad.write_text("let s = MIDINetworkSession.default()\nlet v = CABTMIDICentralViewController()\n", encoding="utf-8")
            text = "\n".join(check_compliance.check_file(bad))
            self.assertIn("network MIDI", text)
            self.assertIn("Bluetooth MIDI pairing", text)
            ok = Path(d) / "Ok.swift"
            ok.write_text("import CoreMIDI\nlet n = MIDIGetNumberOfSources()\n// MIDINetworkSession is not used\n",
                          encoding="utf-8")
            self.assertEqual(check_compliance.check_file(ok), [])

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


class ComplianceNotesPrivacyTests(unittest.TestCase):
    """PRE-011-R6, S2: a diagnostics source that names the notes store fails; the same text elsewhere passes."""

    def test_notes_in_a_diagnostics_source_are_flagged(self):
        with tempfile.TemporaryDirectory() as d:
            diagnostics = Path(d) / "Diagnostics"
            diagnostics.mkdir()
            bad = diagnostics / "Report.swift"
            bad.write_text("let text = presets.noteStore.note(for: id)\n", encoding="utf-8")
            literal = diagnostics / "Path.swift"
            literal.write_text('let url = folder.appendingPathComponent("notes.json")\n', encoding="utf-8")
            comment = diagnostics / "Comment.swift"
            comment.write_text("// never reads PresetNoteStore\nlet x = 1\n", encoding="utf-8")
            elsewhere = Path(d) / "Elsewhere.swift"
            elsewhere.write_text("let store = PresetNoteStore(directory: url)\n", encoding="utf-8")
            with mock.patch.object(check_compliance, "NOTES_PRIVATE_SOURCES", [diagnostics]):
                for path in (bad, literal):
                    self.assertIn("preset notes in a diagnostics source", "\n".join(check_compliance.check_file(path)))
                self.assertEqual(check_compliance.check_file(comment), [])
                self.assertEqual(check_compliance.check_file(elsewhere), [])

    def test_the_listed_sources_exist(self):
        for source in check_compliance.NOTES_PRIVATE_SOURCES:
            self.assertTrue(source.exists(), source)


class ComplianceDiscoveryTests(unittest.TestCase):
    """OSC-011-T15 (ADR-0100): reviewed discovery files, one Bonjour type, no other endpoint, NSBonjourServices."""

    BROWSER = ("import Network\nlet b = NWBrowser(for: .bonjour(type: OSCDiscovery.serviceType, domain: OSCDiscovery.domain),"
               " using: p)\nif case let .hostPort(_, port) = remote {}\n")

    def write(self, folder: Path, name: str, text: str) -> Path:
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / name
        path.write_text(text, encoding="utf-8")
        return path

    def test_reviewed_files_pass_and_others_fail(self):
        with tempfile.TemporaryDirectory() as d:
            allowed = Path(d) / "OSCTransport"
            with mock.patch.object(check_compliance, "OSC_ALLOWED", allowed):
                self.assertEqual(check_compliance.check_file(self.write(allowed, "NetworkOSCPeerBrowser.swift", self.BROWSER)), [])
                listener = "import Network\nlet s = NWListener.Service(name: n, type: OSCDiscovery.serviceType)\n"
                self.assertEqual(check_compliance.check_file(self.write(allowed, "NetworkDatagramTransport.swift", listener)), [])
                other = check_compliance.check_file(self.write(allowed, "Other.swift", self.BROWSER + listener))
                self.assertEqual(sum("local discovery" in f for f in other), 2, other)

    def test_browser_names_no_host_address_url_or_other_type(self):
        with tempfile.TemporaryDirectory() as d:
            allowed = Path(d) / "OSCTransport"
            with mock.patch.object(check_compliance, "OSC_ALLOWED", allowed):
                for extra in ('let h = NWEndpoint.Host("relay.example.com")\n', 'let e = NWEndpoint.hostPort(host: h, port: p)\n',
                              'let a = "203.0.113.5"\n', 'let u = URL(string: s)\n', 'let r = DNSServiceBrowse()\n',
                              'let t = ".bonjour(type: \\"_x._tcp\\", domain: nil)"\nlet d2 = NWBrowser.Descriptor.bonjour(type: t, domain: nil)\n'):
                    found = check_compliance.check_file(self.write(allowed, "NetworkOSCPeerBrowser.swift", self.BROWSER + extra))
                    self.assertTrue(any("local discovery" in f for f in found), extra)
                no_descriptor = "import Network\nlet b = NWBrowser(for: d, using: p)\n"
                found = check_compliance.check_file(self.write(allowed, "NetworkOSCPeerBrowser.swift", no_descriptor))
                self.assertTrue(any("must browse exactly" in f for f in found))

    def test_only_one_bonjour_type_anywhere(self):
        with tempfile.TemporaryDirectory() as d:
            ok = self.write(Path(d), "A.swift", 'static let serviceType = "_projectm-osc._udp"\n')
            self.assertEqual(check_compliance.check_file(ok), [])
            bad = check_compliance.check_file(self.write(Path(d), "B.swift", 'let t = "_airplay._tcp"\n'))
            self.assertTrue(any("Bonjour type _airplay._tcp" in f for f in bad), bad)

    def test_bonjour_services_in_project_yml(self):
        path = Path("project.yml")
        good = "    info:\n      properties:\n        NSBonjourServices:\n          - _projectm-osc._udp\n        NSOther: x\n"
        self.assertEqual(check_compliance.check_bonjour_services(good, path), [])
        self.assertEqual(check_compliance.check_bonjour_services("NSBonjourServices: [_projectm-osc._udp]\n", path), [])
        self.assertEqual(check_compliance.check_bonjour_services("NSFoo: 1\n", path), [])
        for bad in ("        NSBonjourServices:\n          - _projectm-osc._udp\n          - _http._tcp\n",
                    "NSBonjourServices: [_http._tcp]\n", "        NSBonjourServices:\n        NSOther: x\n"):
            self.assertEqual(len(check_compliance.check_bonjour_services(bad, path)), 1, bad)


class ComplianceCueNotesPrivacyTests(unittest.TestCase):
    """SHOW-012-R11: a source outside the show editor that names a cue's note fails; the editor and tests pass."""

    def test_cue_notes_outside_the_editor_are_flagged(self):
        with tempfile.TemporaryDirectory() as d:
            hud = Path(d) / "SceneHUD.swift"
            hud.write_text("let line = cue.operatorNote ?? \"\"\n", encoding="utf-8")
            comment = Path(d) / "Comment.swift"
            comment.write_text("// never reads operatorNote\nlet x = 1\n", encoding="utf-8")
            tests = Path(d) / "Tests"
            tests.mkdir()
            test = tests / "NoteTests.swift"
            test.write_text("let n = ShowCueNote.maximumCharacters\n", encoding="utf-8")
            self.assertIn("private cue note", "\n".join(check_compliance.check_file(hud)))
            self.assertEqual(check_compliance.check_file(comment), [])
            self.assertEqual(check_compliance.check_file(test), [])
            editor = check_compliance.ROOT / "Apps" / "projectM-iOS" / "Views" / "ShowEditorView.swift"
            self.assertTrue(check_compliance.is_cue_note_allowed(editor))
            osc = check_compliance.ROOT / "Apps" / "projectM-iOS" / "Coordinators" / "OSCSendCoordinator.swift"
            self.assertFalse(check_compliance.is_cue_note_allowed(osc))

    def test_the_allowed_sources_exist(self):
        for source in check_compliance.CUE_NOTES_ALLOWED:
            self.assertTrue(source.exists(), source)


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


class ComplianceCodeExecutionTests(unittest.TestCase):
    """SHD-011 (ADR-0024; contracts/compliance-rules.md): no source may load bundles or libraries, run a
    script engine or format-string expression, spawn a process, map executable memory, or compile
    Metal outside the reviewed files. Each rule is shown firing and staying quiet."""

    def check(self, source: str, name: str = "Main.swift", folder: Path | None = None) -> list[str]:
        with tempfile.TemporaryDirectory() as d:
            base = folder if folder is not None else Path(d)
            base.mkdir(parents=True, exist_ok=True)
            p = base / name
            p.write_text(source, encoding="utf-8")
            try:
                return check_compliance.check_file(p)
            finally:
                if folder is not None:
                    p.unlink()

    def assertRule(self, rule: str, sources: list[str], name: str = "Main.swift"):
        for src in sources:
            found = self.check(src, name)
            self.assertTrue(any(rule in v for v in found), f"{rule} not flagged: {src!r} -> {found}")

    def assertClean(self, sources: list[str], name: str = "Main.swift"):
        for src in sources:
            self.assertEqual(self.check(src, name), [], src)

    def test_bundle_and_library_loading(self):
        self.assertRule("bundle or library loading (SHD-011)", [
            'let b = Bundle(path: folder)\n', 'let b = Bundle( url : picked)\n', 'let ok = try bundle.loadAndReturnError()\n',
            'pluginBundle.load()\n', 'Bundle.main.load()\n', 'let b = CFBundleCreate(nil, url)\n',
            'let ok = dlopen_preflight(p)\n', 'let x = NSCreateObjectFileImageFromMemory(a, b, c)\n'])
        self.assertRule("bundle or library loading (SHD-011)",
                        ['NSBundle *b = [NSBundle bundleWithPath:p];\n'], "Loader.m")
        self.assertClean(['let b = Bundle.main.url(forResource: "x", withExtension: nil)\n',
                          'let b = Bundle(for: Self.self)\n', 'await library.load()\n', 'store.load()\n',
                          'let s = "Bundle(path: x) and bundle.load()"\n'])

    def test_script_engines_and_expression_evaluation(self):
        self.assertRule("script engine or expression evaluation (SHD-011)", [
            'import JavaScriptCore\n', '@preconcurrency import class JavaScriptCore.JSContext\n',
            'let c = JSContext()\n', 'let v: JSValue? = nil\n', 'let e = NSExpression(format: text)\n',
            'let p = NSPredicate(format: userText)\n', 'let p = NSPredicate(format:userText)\n'])
        self.assertRule("script engine or expression evaluation (SHD-011)",
                        ['#import <JavaScriptCore/JavaScriptCore.h>\n',
                         'NSPredicate *p = [NSPredicate predicateWithFormat:text];\n'], "X.m")
        self.assertClean(['let p = NSPredicate(format: "label BEGINSWITH %@", title)\n',
                          'let p = NSPredicate(format:"value == \'2\'")\n',
                          'let words = ["NSExpression", "JSContext", "JavaScriptCore"]\n'])
        self.assertClean(['NSPredicate *p = [NSPredicate predicateWithFormat:@"label == %@", x];\n'], "X.m")

    def test_process_spawning(self):
        self.assertRule("process spawning (SHD-011)", [
            'let p = Process()\n', 'posix_spawn(&pid, path, nil, nil, argv, envp)\n', 'let t = NSTask()\n',
            'system("rm -rf /")\n', 'let r = system(command)\n', 'execv(path, argv)\n', 'let pid = fork()\n',
            'let f = popen(cmd, "r")\n'])
        self.assertClean(['Text("x").font(.system(.caption))\n', 'public static func system() -> OSCReceiver { x }\n',
                          'let r = OSCReceiver.system()\n', 'let info = ProcessInfo.processInfo\n',
                          'let list = ["Process", "system(", "posix_spawn"]\n'])

    def test_executable_memory(self):
        self.assertRule("executable memory (SHD-011)", [
            'let p = mmap(nil, n, PROT_READ | PROT_EXEC, MAP_PRIVATE, -1, 0)\n', 'let f = MAP_JIT\n',
            'mprotect(p, n, 7)\n', 'pthread_jit_write_protect_np(0)\n'])
        self.assertClean(['let words = ["PROT_EXEC", "MAP_JIT"]\n'])

    def test_metal_libraries_from_files_data_or_dynamic_libraries(self):
        self.assertRule("Metal library from outside the reviewed sources (SHD-011)", [
            'let l = try device.makeLibrary(URL: picked)\n', 'let l = try device.makeLibrary(data: bytes)\n',
            'let l = try device.makeLibrary(filepath: p)\n', 'let l = try device.makeDefaultLibrary(bundle: b)\n',
            'let d = try device.makeDynamicLibrary(url: u)\n', 'var d: MTLDynamicLibrary?\n',
            'let a = try device.makeBinaryArchive(descriptor: x)\n',
            'let l = try device.makeLibrary(source: text, options: nil)\n'])
        self.assertRule("Metal library from outside the reviewed sources (SHD-011)",
                        ['id<MTLLibrary> l = [device newLibraryWithURL:url error:&e];\n',
                         'id<MTLLibrary> l = [device newLibraryWithSource:s options:nil error:&e];\n'], "X.m")
        self.assertClean(['let l = device.makeDefaultLibrary()\n', 'let f = library.makeFunction(name: "main")\n',
                          'XCTAssertTrue(line.contains("makeLibrary(source: Self.source,"))\n',
                          'let forbidden = ["makeLibrary(URL", "makeLibrary(data"]\n'])

    def test_metal_source_allowed_only_in_reviewed_files(self):
        source = 'let library = try device.makeLibrary(source: Self.shaderSource, options: nil)\n'
        for rel in sorted(check_compliance.METAL_SOURCE_ALLOWED):
            path = check_compliance.ROOT / rel
            self.assertTrue(path.is_file(), rel)
            text = check_compliance.strip_strings(check_compliance.strip_comments(path.read_text(encoding="utf-8")))
            self.assertTrue(check_compliance.METAL_SOURCE.search(text), f"{rel} no longer compiles source; drop it")
            self.assertEqual(check_compliance.check_code_execution(path, source), [], rel)
        outside = check_compliance.ROOT / "Packages" / "Compositor" / "Sources" / "GeneratorGraphImport" / "X.swift"
        self.assertEqual(len(check_compliance.check_code_execution(outside, source)), 1)

    def test_binary_archives_only_in_the_reviewed_file(self):
        # PERF-009 / ADR-0062: one file may open Metal binary archives; everywhere else it stays forbidden.
        code = 'let a = try device.makeBinaryArchive(descriptor: d)\n'
        for rel in sorted(check_compliance.BINARY_ARCHIVE_ALLOWED):
            path = check_compliance.ROOT / rel
            self.assertTrue(path.is_file(), rel)
            self.assertEqual(check_compliance.check_code_execution(path, code), [], rel)
        outside = check_compliance.ROOT / "Packages" / "Compositor" / "Sources" / "Compositor" / "X.swift"
        self.assertEqual(len(check_compliance.check_code_execution(outside, code)), 1)

    def test_string_literals_are_removed_before_matching(self):
        stripped = check_compliance.strip_strings('a("x\\"y") + """\nJSContext()\n""" + #"Process()"# + b\n')
        self.assertNotIn("JSContext", stripped)
        self.assertNotIn("Process", stripped)
        self.assertIn("a(", stripped)
        self.assertIn("+ b", stripped)

    def test_fixture_flags_every_shd011_rule(self):
        text = "\n".join(check_compliance.check_file(FIXTURES / "Violations.swift.txt"))
        for name, _ in check_compliance.CODE_EXECUTION_RULES:
            if name.startswith("Metal library"):
                continue
            self.assertIn(name, text)
        self.assertIn("makeLibrary(source:) outside METAL_SOURCE_ALLOWED", text)


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


class UIStringsInterruptionContractTests(unittest.TestCase):
    """AUD-014: every string in specs/009's ui-strings contract is in CaptureUI's UIStrings.swift."""

    ROOT = Path(__file__).resolve().parent.parent
    CONTRACT = ROOT / "specs" / "009-aud-014-audio-session-interruption-recovery" / "contracts" / "ui-strings.md"
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
        self.assertEqual([name for name, _ in rows], ["interrupted", "audioRouteChanged"])
        swift = self.SWIFT.read_text(encoding="utf-8")
        for name, text in rows:
            self.assertIn(f'"{text}"', swift, name)


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

    def test_performance_report_schema_copy_matches_contract(self):
        # PERF-012-T07: the package test copy equals the contract, and the reused sections equal the diagnostics schema's.
        root = Path(__file__).resolve().parent.parent
        contract = root / "specs" / "209-perf-012-performance-report" / "contracts" / "performance-report.schema.json"
        copy = root / "Packages" / "Diagnostics" / "Tests" / "DiagnosticsTests" / "Resources" / "performance-report.schema.json"
        report = json.loads(contract.read_text(encoding="utf-8"))
        self.assertEqual(report, json.loads(copy.read_text(encoding="utf-8")))
        diagnostics = json.loads((root / "specs" / "001-ios-projectm-visualizer" / "contracts" / "diagnostics-export.schema.json").read_text(encoding="utf-8"))
        for key in ("frameDrops", "frameTimings"):
            self.assertEqual(report["properties"][key], diagnostics["properties"][key], key)



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

    def test_warmstart_summary_medians_per_label(self):
        # PERF-009-R10: cold and warm samples are summarized apart; a simulator run is never evidence.
        samples = [
            {"cache": "cold", "libraryOutcome": "miss", "chooserMs": 90, "libraryReadyMs": 200, "libraryLoadMs": 110},
            {"cache": "cold", "libraryOutcome": "miss", "chooserMs": 80, "libraryReadyMs": 180, "libraryLoadMs": 100},
            {"cache": "warm", "libraryOutcome": "hit", "chooserMs": 85, "libraryReadyMs": 120, "libraryLoadMs": 30},
            {"cache": "warm", "libraryOutcome": "hit", "chooserMs": 85, "libraryReadyMs": 120, "libraryLoadMs": -1},
        ]
        summary = rdt.warmstart_summary(samples, simulator=True)
        self.assertFalse(summary["evidence"])
        self.assertEqual(summary["cold"], {"launches": 2, "libraryOutcomes": ["miss"], "chooserMs": 85.0,
                                           "libraryReadyMs": 190.0, "libraryLoadMs": 105.0})
        self.assertEqual(summary["warm"]["libraryLoadMs"], 30.0)   # a missing (-1) value is left out
        self.assertEqual(summary["warm"]["libraryOutcomes"], ["hit"])
        self.assertTrue(rdt.warmstart_summary([], simulator=False)["evidence"])

    def test_warmstart_dry_run_alternates_cold_and_warm(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rdt.main(["--dry-run", "warmstart", "--simulator", "FAKE", "--no-install", "--repeat", "2"])
        launches = [line for line in out.getvalue().splitlines() if "simctl launch" in line]
        self.assertEqual(len(launches), 5)   # the notice launch, then cold, warm, cold, warm
        self.assertEqual(["PROJECTM_WARMCACHE=cold" in line for line in launches], [False, True, False, True, False])
        self.assertEqual(rdt.privacy_problems(["Documents/perf009.json", "Library/Caches/WarmStart/preset-library.bin"], []), [])

    def test_privacy_allows_fr065_keys_reports_others(self):
        keys = ["favorites", "settings.presetScope", "SKTransactionUpdatesLastChecked", "unlocked"]
        files = ["Documents/automation-privacy-2026.json", "Documents/recording.wav", "tmp/x.bin",
                 "Library/Caches/org.projectmios.ProjectMiOS/com.apple.metalfe/A/monolithic_metal.pcm"]
        self.assertEqual(rdt.privacy_problems(files, keys),
                         ["key not allowed: unlocked", "unexpected file: Documents/recording.wav",
                          "audio file: Documents/recording.wav", "unexpected file: tmp/x.bin"])

    def test_every_stored_defaults_key_is_allowed(self):
        # The app's UserDefaults keys are `static let <name>Key = "<key>"` constants (plus
        # `static let key = ...` in single-key stores). The privacy check must allow each one, or a
        # device privacy run fails on a key the app is meant to store.
        app = Path(__file__).resolve().parent.parent / "Apps" / "projectM-iOS"
        pattern = re.compile(r'static let (?:[A-Za-z]*Key|key) = "([^"]+)"')
        not_defaults = {"photo", "video", "text"}   # scene snapshot field names, not defaults keys
        found = set()
        for path in app.rglob("*.swift"):
            if "Tests" in path.parts or "UITests" in path.parts:
                continue
            found.update(pattern.findall(path.read_text(encoding="utf-8")))
        self.assertIn("settings.visual", found, "the scan finds the app's keys")
        self.assertEqual(sorted(found - not_defaults - rdt.ALLOWED_KEYS), [])

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
        # The index plus one file per memory it lists (a fixed count broke when a memory was added).
        listed = re.findall(r"\]\(([^)]+\.md)\)", (setup_mac.MEMORY_EXPORT / "MEMORY.md").read_text())
        self.assertEqual(sorted(listed + ["MEMORY.md"]), exported)
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


class LinuxPortabilityTests(unittest.TestCase):
    """Swift package code must build on CI's Linux runner, where Swift 6 rejects the C stdio
    globals (`stdout`, `stderr`, `stdin`) as not concurrency-safe. macOS accepts them, so only CI
    caught `fflush(stdout)` in a test (run 43432992539). Use print() or FileHandle.standardError."""

    def test_no_c_stdio_globals_in_package_swift(self):
        pattern = re.compile(r"\b(stdout|stderr|stdin)\b")
        found = []
        for path in sorted((check_compliance.ROOT / "Packages").rglob("*.swift")):
            if ".build" in path.parts:
                continue
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                code = line.split("//", 1)[0]
                if pattern.search(code.replace("FileHandle.standard", "")):
                    found.append(f"{path.relative_to(check_compliance.ROOT)}:{number}")
        self.assertEqual(found, [], "C stdio globals break the Linux build")


class ReferenceToneGoldensTests(unittest.TestCase):
    """AUD-016: an independent Python port reproduces the Swift generator's golden hashes."""

    def test_python_port_matches_the_swift_goldens(self):
        import check_reference_tone_goldens as crtg
        with mock.patch("builtins.print"):
            self.assertEqual(crtg.main(), 0)


class NetworkSymbolScanTests(unittest.TestCase):
    """check_network_symbols.py (FILE-012-T02; FILE-012-R2 to R4, S2): rules from recorded tool output."""

    OTOOL = ("/tmp/x.app/x:\n"
             "\t/System/Library/Frameworks/Foundation.framework/Foundation (compatibility version 300.0.0)\n"
             "\t/System/Library/Frameworks/StoreKit.framework/StoreKit (compatibility version 1.0.0)\n"
             "\t/usr/lib/libresolv.9.dylib (compatibility version 1.0.0)\n")
    NM = ("                 (undefined) external _$s7Network10NWListenerC5startyy...(from Network)\n"
          "                 (undefined) weak external _socket (from libSystem)\n"
          "                 (undefined) external _OBJC_CLASS_$_NSURLSession (from Foundation)\n"
          "0000000000001000 (__TEXT,__text) external _main\n")

    def findings(self, imports, demangled=None, defined=frozenset(), libraries=()):
        return cns.evaluate_image("img", "arm64", list(libraries), imports, demangled or {}, set(defined))

    def test_parsers_read_otool_and_nm_output(self):
        libraries = cns.parse_otool_libraries(self.OTOOL)
        self.assertEqual([cns.library_name(path) for path in libraries], ["Foundation", "StoreKit", "libresolv"])
        imports = cns.parse_nm_imports(self.NM)
        self.assertEqual(imports[1], ("_socket", "libSystem"))
        self.assertEqual(imports[2], ("_OBJC_CLASS_$_NSURLSession", "Foundation"))
        self.assertEqual(len(imports), 3, "defined symbols are not imports")

    def test_forbidden_libraries_fail_and_storekit_is_allowed(self):
        found = self.findings([], libraries=["/System/Library/Frameworks/StoreKit.framework/StoreKit",
                                             "/System/Library/Frameworks/CFNetwork.framework/CFNetwork",
                                             "/System/Library/Frameworks/WebKit.framework/WebKit",
                                             "/usr/lib/libresolv.9.dylib"])
        self.assertEqual({(f.name, f.allowed) for f in found},
                         {("StoreKit", True), ("CFNetwork", False), ("WebKit", False), ("libresolv", False)})

    def test_each_forbidden_symbol_class_fails(self):
        symbols = ["_socket", "_connect", "_getaddrinfo", "_sendto", "_OBJC_CLASS_$_NSURLSession",
                   "_$sSo12NSURLSessionC10FoundationE4data3for8delegate", "_CFSocketCreate",
                   "_CFStreamCreatePairWithSocketToHost", "_SCNetworkReachabilityCreateWithName",
                   "_OBJC_CLASS_$_NSNetServiceBrowser", "_OBJC_CLASS_$_WKWebView", "_DNSServiceBrowse",
                   "_connect$UNIX2003"]
        found = self.findings([(s, "") for s in symbols])
        self.assertEqual(len(found), len(symbols))
        self.assertTrue(all(not f.allowed for f in found))

    def test_harmless_lookalikes_pass(self):
        self.assertEqual(self.findings([("_socketpair", ""), ("_OBJC_CLASS_$_NSURL", ""), ("_connectionCount", "")]), [])

    def test_network_midi_fails_and_local_coremidi_passes(self):
        """MIDI-001-R14 (ADR-0038): the network MIDI session fails; discovery calls pass."""
        bad = ["_OBJC_CLASS_$_MIDINetworkSession", "_OBJC_CLASS_$_MIDINetworkHost", "_OBJC_CLASS_$_MIDINetworkConnection"]
        found = self.findings([(s, "CoreMIDI") for s in bad])
        self.assertEqual(len(found), 3)
        self.assertTrue(all(not f.allowed for f in found))
        local = ["_MIDIClientCreateWithBlock", "_MIDIGetNumberOfSources", "_MIDIGetSource", "_MIDIObjectGetIntegerProperty",
                 "_kMIDIPropertyUniqueID", "_MIDIEndpointGetEntity"]
        self.assertEqual(self.findings([(s, "CoreMIDI") for s in local]), [])

    def test_network_symbols_need_the_osc_image_and_the_allowlist(self):
        imports = [("_$sListenerStart", "Network"), ("_$sConnOut", "Network"), ("_$sBrowser", "Network"),
                   ("_nw_connection_create", "Network")]
        demangled = {"_$sListenerStart": "NWListener.start(queue:)",
                     "_$sConnOut": "NWConnection.__allocating_init(host:port:using:)",
                     "_$sBrowser": "type metadata accessor for NWBrowser"}
        outside = self.findings(imports, demangled)
        self.assertTrue(all(not f.allowed for f in outside), "Network outside the OSC image fails")
        release = {f.name: f.allowed for f in self.findings(imports, demangled, {"_$s18PerformanceControl24NetworkDatagramTransportC"})}
        self.assertTrue(release["NWListener.start(queue:)"])
        self.assertFalse(release["NWConnection.__allocating_init(host:port:using:)"], "outbound without the DEBUG sender")
        self.assertFalse(release["type metadata accessor for NWBrowser"])
        self.assertFalse(release["_nw_connection_create"], "C-level nw_* is never allowed")
        debug = {f.name: f.allowed for f in self.findings(imports, demangled, {"NetworkDatagramTransport", "OSCLoopbackSender"})}
        self.assertTrue(debug["NWConnection.__allocating_init(host:port:using:)"], "the DEBUG loopback sender")
        self.assertFalse(debug["type metadata accessor for NWBrowser"])
        # OSC-005 (ADR-0088): the reviewed sender allows the outbound pair, also in Release, and nothing more.
        sender = {f.name: f.allowed for f in self.findings(imports, demangled, {"NetworkDatagramTransport", "_$s18PerformanceControl16NetworkOSCSenderC"})}
        self.assertTrue(sender["NWConnection.__allocating_init(host:port:using:)"], "the OSC-005 sender")
        self.assertFalse(sender["type metadata accessor for NWBrowser"])
        self.assertFalse(sender["_nw_connection_create"])
        alone = {f.name: f.allowed for f in self.findings(imports, demangled, {"NetworkOSCSender"})}
        self.assertFalse(alone["NWConnection.__allocating_init(host:port:using:)"], "the sender marker outside the OSC image")
        self.assertEqual(cns.release_findings("img", "arm64", {"NetworkDatagramTransport", "NetworkOSCSender"}), [])

    def test_discovery_apis_pass_only_next_to_the_reviewed_browser(self):
        """OSC-011-T16 (ADR-0100): NWBrowser, service announcing and resolution need the browser's image."""
        apis = ["NWBrowser.__allocating_init(for:using:)", "NWBrowser.Descriptor.bonjour(_:)",
                "type metadata accessor for NWListener.Service", "NWListener.service.setter",
                "NWConnection.__allocating_init(to:using:)", "NWConnection.currentPath.getter",
                "NWPath.remoteEndpoint.getter", "dispatch thunk of NWProtocolIP.Options.version.setter"]
        imports = [(f"_$sD{i}", "Network") for i in range(len(apis))]
        demangled = {f"_$sD{i}": api for i, api in enumerate(apis)}
        osc_only = self.findings(imports, demangled, {"NetworkDatagramTransport", "NetworkOSCSender"})
        self.assertEqual(len(osc_only), len(apis))
        self.assertTrue(all(not f.allowed for f in osc_only), "the receiver and sender images may not browse or announce")
        reviewed = self.findings(imports, demangled, {"NetworkDatagramTransport", "_$s18PerformanceControl21NetworkOSCPeerBrowserC"})
        self.assertTrue(all(f.allowed for f in reviewed), [f.name for f in reviewed if not f.allowed])
        alone = self.findings(imports, demangled, {"NetworkOSCPeerBrowser"})
        self.assertTrue(all(not f.allowed for f in alone), "the browser marker outside the OSC image")
        # Other Network APIs stay off the list next to the browser, and lookalikes are not admitted.
        other = {f.name: f.allowed for f in self.findings(
            [("_$sX1", "Network"), ("_$sX2", "Network"), ("_$sX3", "Network")],
            {"_$sX1": "NWPathMonitor.start(queue:)", "_$sX2": "NWConnection.__allocating_init(host:port:using:)",
             "_$sX3": "NWEthernetChannel.start(queue:)"},
            {"NetworkDatagramTransport", "NetworkOSCPeerBrowser"})}
        self.assertEqual(other, {"NWPathMonitor.start(queue:)": False, "NWConnection.__allocating_init(host:port:using:)": False,
                                 "NWEthernetChannel.start(queue:)": False})

    def test_network_linkage_outside_the_osc_image_fails(self):
        path = "/System/Library/Frameworks/Network.framework/Network"
        self.assertFalse(self.findings([], libraries=[path])[0].allowed)
        self.assertTrue(self.findings([], defined={"NetworkDatagramTransport"}, libraries=[path])[0].allowed)

    def test_api_names_strip_descriptor_prefixes(self):
        self.assertEqual(cns.network_api_name("enum case for NWConnection.State.ready(_:)"), "NWConnection.State.ready(_:)")
        self.assertEqual(cns.network_api_name("static NWParameters.udp.getter"), "NWParameters.udp.getter")
        self.assertEqual(cns.network_api_name("protocol conformance descriptor for NWError"), "NWError")
        self.assertEqual(cns.network_api_name("dispatch thunk of NWParameters.ProtocolStack.internetProtocol.getter"),
                         "NWParameters.ProtocolStack.internetProtocol.getter")

    def test_release_flag_rejects_the_loopback_sender(self):
        self.assertEqual(len(cns.release_findings("img", "arm64", {"_$s18PerformanceControl17OSCLoopbackSenderO"})), 1)
        self.assertEqual(cns.release_findings("img", "arm64", {"NetworkDatagramTransport"}), [])

    @unittest.skipUnless(sys.platform == "darwin", "macOS only: builds a real binary with clang (FILE-012-R4)")
    def test_positive_control_a_real_binary_calling_socket_fails(self):
        import subprocess
        with tempfile.TemporaryDirectory() as tmp:
            app = Path(tmp) / "Probe.app"
            app.mkdir()
            (app / "Info.plist").write_bytes(b'<?xml version="1.0"?><plist version="1.0"><dict></dict></plist>')
            source = Path(tmp) / "probe.c"
            source.write_text("#include <sys/socket.h>\n#include <netdb.h>\n"
                              "int main(void) { struct addrinfo *r; getaddrinfo(\"example.invalid\", 0, 0, &r);\n"
                              "  int s = socket(AF_INET, SOCK_STREAM, 0); return connect(s, 0, 0); }\n")
            subprocess.run(["xcrun", "clang", "-o", str(app / "Probe"), str(source)], check=True, capture_output=True)
            clean = Path(tmp) / "Clean.app"
            clean.mkdir()
            (clean / "Info.plist").write_bytes((app / "Info.plist").read_bytes())
            (Path(tmp) / "clean.c").write_text("int main(void) { return 0; }\n")
            subprocess.run(["xcrun", "clang", "-o", str(clean / "Clean"), str(Path(tmp) / "clean.c")], check=True, capture_output=True)
            out = io.StringIO()
            with mock.patch("sys.stdout", out):
                bad, good = cns.main([str(app)]), cns.main([str(clean)])
            self.assertEqual((bad, good), (1, 0), out.getvalue())
            for name in ("socket", "connect", "getaddrinfo"):
                self.assertIn(f"socket or resolver function {name}", out.getvalue())


class AppNetworkObserverTests(unittest.TestCase):
    """observe_app_network.py (FILE-012-T06; FILE-012-R6, R7): classification from recorded output."""

    UDID = "8D04FF0C-A557-42C6-BFB6-80F5BCC39BD0"

    def test_expectation_parsing(self):
        self.assertIsNone(oan.parse_expect("none"))
        self.assertEqual(oan.parse_expect("osc:47131"), 47131)
        for bad in ("osc:0", "osc:70000", "all", "osc:"):
            with self.assertRaises(ValueError):
                oan.parse_expect(bad)

    def test_only_the_apps_processes_in_this_simulator_are_found(self):
        base = "/Users/x/Library/Developer/CoreSimulator/Devices/{}/data/Containers/Bundle/Application/A-B/projectM-iOS.app/"
        ps = (f" 101 {base.format(self.UDID)}projectM-iOS -uitestUnlocked NO\n"
              f" 102 {base.format('OTHER-UDID')}projectM-iOS\n"
              f" 103 {base.format(self.UDID)}PlugIns/x.xctest/projectM-iOSUITests-Runner\n"
              f" 104 /usr/bin/lsof -p 101\n")
        self.assertEqual(oan.app_pids_from_ps(ps, self.UDID, "projectM-iOS"), [101])

    def test_lsof_fields_parse(self):
        sockets = oan.parse_lsof_fields("p4647\nf4\ntIPv6\nPUDP\nn*:47129\nf15\ntIPv6\nPUDP\nn127.0.0.1:47129->127.0.0.1:55802\n")
        self.assertEqual([(s["pid"], s["protocol"], s["name"]) for s in sockets],
                         [(4647, "UDP", "*:47129"), (4647, "UDP", "127.0.0.1:47129->127.0.0.1:55802")])

    def sockets(self, *names, protocol="UDP"):
        return [{"pid": 1, "fd": "4", "type": "IPv6", "protocol": protocol, "name": n} for n in names]

    def report(self, sockets=(), events=(), osc=None, probe=False, ports=frozenset(), pids=(1,), ready=True, status=0):
        return oan.evaluate(command_status=status, pids=list(pids), log_ready=ready, sockets=list(sockets),
                            events=list(events), osc_port=osc, probe=probe, probe_ports=set(ports))

    BOOKKEEPING = [{"category": "activity", "eventMessage": "Create activity from XPC object <nw_activity 50:1>"},
                   {"category": "", "eventMessage": "networkd_settings_read_from_file_locked initialized networkd settings"}]
    LISTENER = [{"category": "listener", "eventMessage": "nw_listener_set_state_on_queue [L1] waiting -> ready"}]
    PROBE_PEER = [{"category": "connection", "eventMessage": "[C1 2B22 IPv4#37e29c21:55802 udp, server, prohibit joining protocols, definite]"},
                  {"category": "connection", "eventMessage": "nw_connection_report_state_with_handler_on_nw_queue [C1] reporting state ready"}]

    def test_none_passes_only_with_no_socket_and_no_relevant_event(self):
        self.assertTrue(self.report(events=self.BOOKKEEPING)["ok"])
        self.assertFalse(self.report(sockets=self.sockets("192.168.1.2:50000->17.1.2.3:443"), events=self.BOOKKEEPING)["ok"])
        self.assertFalse(self.report(events=self.LISTENER)["ok"], "any network event fails with OSC off")

    def test_blind_observers_fail(self):
        self.assertIn("blind: no app process was seen in the simulator", self.report(pids=())["problems"])
        self.assertIn("blind: the simulator log stream never became ready", self.report(ready=False)["problems"])
        self.assertIn("the observed command failed (exit 65)", self.report(status=65)["problems"])

    def test_osc_allows_the_listener_and_the_probe_peer_only(self):
        good = self.report(self.sockets("*:47131", "127.0.0.1:47131->127.0.0.1:55802"), self.LISTENER + self.PROBE_PEER,
                           osc=47131, probe=True, ports={55802})
        self.assertTrue(good["ok"], good["problems"])
        self.assertEqual(good["log"]["serverConnections"], ["1"])
        outbound = self.report(self.sockets("*:47131", "127.0.0.1:50001->127.0.0.1:9000"), self.LISTENER, osc=47131)
        self.assertFalse(outbound["ok"])
        stranger = self.report(self.sockets("*:47131", "192.168.1.5:47131->192.168.1.9:4000"), self.LISTENER, osc=47131)
        self.assertFalse(stranger["ok"], "an inbound peer that is not the probe")
        tcp = self.report(self.sockets("*:47131", protocol="TCP"), osc=47131)
        self.assertFalse(tcp["ok"])

    def test_osc_rejects_client_connections_and_resolver_events(self):
        client = [{"category": "connection", "eventMessage": "[C2 Hostname#abc:443 tcp, url: https://x, definite, attribution: developer]"}]
        report = self.report(self.sockets("*:47131"), self.LISTENER + client, osc=47131)
        self.assertIn("log: connection C2 was never described as server-side (inbound)", report["problems"])
        resolver = [{"category": "resolver", "eventMessage": "nw_resolver_start_query_timer [C3] starting DNS"}]
        self.assertFalse(self.report(self.sockets("*:47131"), self.LISTENER + resolver, osc=47131)["ok"])

    def test_osc_probe_must_be_seen_in_both_layers(self):
        unseen = self.report(self.sockets("*:47131"), self.LISTENER, osc=47131, probe=True, ports={55802})
        self.assertIn("blind: the probe's peer socket was not seen in lsof", unseen["problems"])
        self.assertIn("blind: no server-side connection event for the probe in the log", unseen["problems"])
        never = self.report(self.sockets("*:47131"), self.LISTENER, osc=47131, probe=True)
        self.assertIn("blind: the probe was never sent", never["problems"])
        no_listener = self.report((), (), osc=47131)
        self.assertIn("the OSC listener on port 47131 was never seen", no_listener["problems"])


class MotionPolicyCheckTests(unittest.TestCase):
    """check_motion_policy.py (ACC-001-T09, R7): app animations go through MotionPolicy."""

    def test_bare_animations_are_flagged(self):
        text = "a\n.animation(.easeInOut, value: x)\nwithAnimation { y = 1 }\nUIView.animate(withDuration: 1) {}\n"
        self.assertEqual(cmp.violations(text), [2, 3, 4])

    def test_policy_safety_comments_and_strings_pass(self):
        text = "\n".join([
            ".reduceMotionAware(MotionPolicy.controlsFade, value: v, policy: p)",
            ".animation(MotionPolicy.safetyFade(.linear(duration: 0.5)), value: s)",
            "x // .animation(.default, value: v)",
            "/* withAnimation {",
            "   .animation(.default) */ let a = 1",
            'let s = ".animation(.default)"',
            ".transition(.opacity)",
        ])
        self.assertEqual(cmp.violations(text), [])

    def test_tests_and_the_policy_file_are_excluded(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = Path(tmp)
            (app / "Tests").mkdir()
            (app / "Tests" / "T.swift").write_text("withAnimation { }\n")
            (app / "MotionPolicy.swift").write_text("self.animation(x, value: v)\n")
            (app / "V.swift").write_text("ok\n.animation(.spring, value: v)\n")
            self.assertEqual([p.name for p in cmp.source_files(app)], ["V.swift"])
            self.assertEqual(len(cmp.check(app)), 1)

    def test_the_app_is_clean(self):
        self.assertEqual(cmp.check(), [])


class StatusEventsCheckTests(unittest.TestCase):
    """check_status_events.py (ACC-011-T13, R11): no direct announcement posts in the capture files."""

    def test_direct_posts_are_flagged_and_comments_pass(self):
        text = "\n".join([
            "UIAccessibility.post(notification: .announcement, argument: t)",
            "AccessibilityNotification.Announcement(t).post()",
            "// UIAccessibility.post(notification: .announcement, argument: t)",
            'let s = "UIAccessibility.post"',
            "router.post(event)",
        ])
        self.assertEqual(cse.violations(text), [1, 2])

    def test_allowed_names_excuse_a_line(self):
        text = "presets.onScopeChange { UIAccessibility.post(notification: .announcement, argument: $0) }\n"
        self.assertEqual(cse.violations(text, cse.ALLOWED_IN_COORDINATOR), [])
        self.assertEqual(cse.violations(text), [1])

    def test_a_missing_file_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertTrue(any("missing" in p for p in cse.check(Path(tmp))))

    def test_the_app_is_clean(self):
        self.assertEqual(cse.check(), [])


class PermissionCatalogCheckTests(unittest.TestCase):
    """check_permission_catalog.py (FILE-013-T09): catalog vs project.yml and the privacy policy."""

    ROOT = Path(__file__).resolve().parent.parent

    def inputs(self):
        return ((self.ROOT / cpc.PROJECT).read_text(encoding="utf-8"),
                (self.ROOT / cpc.CATALOG).read_text(encoding="utf-8"),
                (self.ROOT / cpc.POLICY).read_text(encoding="utf-8"))

    def test_repository_is_consistent(self):
        yml, swift, policy = self.inputs()
        self.assertEqual(cpc.problems(yml, swift, policy), [])
        self.assertEqual(set(cpc.plist_keys(yml)), {"NSMicrophoneUsageDescription", "NSCameraUsageDescription",
                                                    "NSLocalNetworkUsageDescription", "NSScreenCaptureUsageDescription",
                                                    "NSPhotoLibraryAddUsageDescription"})

    def test_capturelab_keys_are_not_the_apps(self):
        yml, _, _ = self.inputs()
        self.assertNotIn("NSLocalNetworkUsageDescription", cpc.plist_keys(yml, "CaptureLab"))

    def test_key_missing_from_catalog_fails(self):
        yml, swift, policy = self.inputs()
        yml = yml.replace('        NSLocalNetworkUsageDescription: "When',
                          '        NSBluetoothAlwaysUsageDescription: "x"\n        NSLocalNetworkUsageDescription: "When')
        self.assertIn("NSBluetoothAlwaysUsageDescription: in project.yml (projectM-iOS) but not in the catalog",
                      cpc.problems(yml, swift, policy))

    def test_catalog_entry_missing_from_project_fails(self):
        yml, swift, policy = self.inputs()
        yml = "\n".join(line for line in yml.splitlines()
                        if not (line.strip().startswith("NSCameraUsageDescription:")))
        self.assertIn("NSCameraUsageDescription: in the catalog but not in project.yml (projectM-iOS)",
                      cpc.problems(yml, swift, policy))

    def test_changed_text_fails(self):
        yml, swift, policy = self.inputs()
        swift = swift.replace("It never connects to the internet.", "It never connects anywhere.")
        self.assertIn("NSLocalNetworkUsageDescription: the catalog's text differs from project.yml",
                      cpc.problems(yml, swift, policy))

    def test_photos_key_fails(self):
        yml, swift, policy = self.inputs()
        for key in cpc.PHOTOS_KEYS:
            bad = yml + f'\n        {key}: "x"\n'
            self.assertTrue(any(p.startswith(f"{key}: Photos library keys are not allowed")
                                for p in cpc.problems(bad, swift, policy)), key)

    def test_photos_add_key_only_in_the_app_target(self):
        """REC-011 (ADR-0059): the add-only key is allowed in projectM-iOS and nowhere else."""
        yml, swift, policy = self.inputs()
        self.assertIn(cpc.PHOTOS_ADD_KEY, cpc.plist_keys(yml))
        bad = yml.replace("  CaptureLabUITests:", f'        {cpc.PHOTOS_ADD_KEY}: "x"\n  CaptureLabUITests:', 1)
        self.assertIn(f"{cpc.PHOTOS_ADD_KEY}: allowed only in the projectM-iOS target (REC-011, ADR-0059)",
                      cpc.problems(bad, swift, policy))

    def test_policy_mismatch_fails(self):
        yml, swift, policy = self.inputs()
        missing = policy.replace("- **Local Network**:", "- Local Network:")
        self.assertIn("privacy policy: 'Local Network' is in the catalog but not in '## Permissions and why'",
                      cpc.problems(yml, swift, missing))
        extra = policy.replace("- **Camera**:", "- **Location**: never.\n- **Camera**:")
        self.assertIn("privacy policy: 'Location' is listed but is not a catalog permission",
                      cpc.problems(yml, swift, extra))

    def test_main_exit_codes(self):
        with mock.patch("sys.stdout", new_callable=io.StringIO) as out:
            self.assertEqual(cpc.main(["--root", str(self.ROOT), "--json"]), 0)
        self.assertTrue(json.loads(out.getvalue())["ok"])


class RunRenderSoakTests(unittest.TestCase):
    """QA-006-T11: scripts/run_render_soak.py (arguments, commands, environment, report summary)."""

    @staticmethod
    def module():
        import run_render_soak  # local import: keeps the shared import block untouched
        return run_render_soak

    def test_host_command_and_environment(self):
        rrs = self.module()
        args = rrs.parse(["--seconds", "600"])
        plan = rrs.commands(args)
        self.assertEqual(len(plan), 1)
        self.assertEqual(plan[0][0], ["swift", "test", "--filter", "RenderSoakTests/testOnDemandLongSoak"])
        self.assertTrue(str(plan[0][1]).endswith("Packages/RenderGoldens"))
        env = rrs.environment(600, Path("/tmp/r"), simulator=False)
        self.assertEqual(env, {"QA006_SOAK_SECONDS": "600", "QA006_REPORT_DIR": "/tmp/r"})

    def test_simulator_commands_forward_the_environment(self):
        rrs = self.module()
        args = rrs.parse(["--seconds", "120", "--simulator", "ABC", "--angle"])
        plan = rrs.commands(args)
        self.assertEqual([c[0][3] for c in plan], ["RenderGoldens", "ANGLERendering"])
        self.assertIn("-only-testing:ANGLERenderingTests/ProjectMPresetSoakTests", plan[1][0])
        self.assertIn("id=ABC", plan[0][0])
        self.assertIn("240", plan[0][0], "the per-test allowance grows with the soak")
        env = rrs.environment(120, Path("/tmp/r"), simulator=True)
        self.assertEqual(set(env), {"TEST_RUNNER_QA006_SOAK_SECONDS", "TEST_RUNNER_QA006_REPORT_DIR"})

    def test_bad_arguments_exit_2(self):
        rrs = self.module()
        with mock.patch("sys.stderr", new_callable=io.StringIO):
            self.assertEqual(rrs.main(["--seconds", "0"]), 2)
            self.assertEqual(rrs.main(["--seconds", "10", "--angle"]), 2)

    def test_dry_run_prints_and_runs_nothing(self):
        rrs = self.module()
        with tempfile.TemporaryDirectory() as tmp, mock.patch("subprocess.run") as run, \
                mock.patch("sys.stdout", new_callable=io.StringIO) as out:
            self.assertEqual(rrs.main(["--seconds", "30", "--report-dir", tmp, "--dry-run"]), 0)
        run.assert_not_called()
        self.assertIn("QA006_SOAK_SECONDS=30", out.getvalue())

    def test_summary_passes_only_when_every_report_passed(self):
        rrs = self.module()
        def report(name, outcome, rules=()):
            return {"name": name, "platform": "macOS", "simulatedSeconds": 30, "cycles": 10,
                    "verdict": {"outcome": outcome, "failedRules": list(rules), "slopeBytesPerCycle": 0,
                                "slopeLimitBytesPerCycle": 65536, "errorCount": 0}}
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            ok, lines = rrs.summarize(folder)
            self.assertFalse(ok, "no report is a failure")
            (folder / "a.json").write_text(json.dumps(report("a", "pass")))
            ok, lines = rrs.summarize(folder)
            self.assertTrue(ok)
            self.assertIn("a [macOS]: pass", lines[0])
            (folder / "b.json").write_text(json.dumps(report("b", "fail", ["memorySlope"])))
            ok, lines = rrs.summarize(folder)
            self.assertFalse(ok)
            self.assertIn("fail [memorySlope]", lines[1])
            (folder / "c.json").write_text("{not json")
            self.assertIn("unreadable", rrs.summarize(folder)[1][2])

    def test_main_runs_the_tests_and_reads_the_reports(self):
        rrs = self.module()
        with tempfile.TemporaryDirectory() as tmp:
            def fake_run(command, cwd, env):
                Path(env["QA006_REPORT_DIR"], "r.json").write_text(json.dumps(
                    {"name": "r", "verdict": {"outcome": "pass", "failedRules": []}}))
                return mock.Mock(returncode=0)
            with mock.patch("subprocess.run", side_effect=fake_run), mock.patch("sys.stdout", new_callable=io.StringIO):
                self.assertEqual(rrs.main(["--seconds", "40", "--report-dir", tmp]), 0)


class PerformanceThresholdsTests(unittest.TestCase):
    """QA-010: the fixture benchmark (specs/223-qa-010-performance-thresholds, QA-010-S1)."""

    F = FIXTURES / "qa010"
    PASS = ["perf012-d1-pass.json", "perf001-d1-pass.json", "sc015-pass.json"]

    def check(self, *names, **kwargs):
        return cpt.check([self.F / n for n in names], **kwargs)

    def verdicts(self, verdict):
        return {row["metric"]: row["verdict"] for row in verdict["metrics"]}

    def test_committed_thresholds_load_and_cover_every_class_and_metric(self):
        doc = cpt.load_thresholds(cpt.THRESHOLDS)
        self.assertEqual([c["id"] for c in doc["classes"]], ["D1", "D2", "D3", "simulator"])
        self.assertEqual({c["id"]: c["models"] for c in doc["classes"][:3]},
                         {label: [model] for label, model in rdt.DEVICES.items()})
        self.assertEqual([c["evidence"] for c in doc["classes"]], [True, True, True, False])
        for entry in doc["classes"]:   # QA-010-S2: every limit names its basis
            self.assertTrue(all(t["basis"].strip() for t in entry["targets"].values()), entry["id"])
        schema = json.loads((cpt.ROOT / "docs/performance/thresholds.schema.json").read_text())
        self.assertEqual(schema["properties"]["schemaVersion"]["const"], cpt.SCHEMA_VERSION)
        self.assertEqual(set(schema["required"]) - set(doc), set())
        metrics = schema["properties"]["metrics"]["properties"]
        self.assertEqual({m: v["properties"]["direction"]["const"] for m, v in metrics.items()}, cpt.CATALOGUE)

    def test_pass_fixture_passes_every_metric_with_the_version(self):
        verdict = self.check(*self.PASS)
        self.assertEqual(verdict["overall"], "pass")
        self.assertEqual(set(self.verdicts(verdict).values()), {"pass"})
        self.assertEqual((verdict["deviceClass"], verdict["evidence"], verdict["thresholdsVersion"]), ("D1", True, 2))
        self.assertEqual(cpt.exit_code(verdict), 0)

    def test_audio_age_is_read_from_the_perf013_section_of_a_performance_report(self):
        # PERF-013 puts audio age in the exported report (`audioSync.p95Ms`); no automation mode writes it.
        ok = self.verdicts(self.check("perf012-d1-audiosync-pass.json", "perf001-d1-no-audio-age.json", "sc015-pass.json"))
        self.assertEqual(ok["audioAgeP95Ms"], "pass")
        bad = self.verdicts(self.check("perf012-d1-audiosync-fail.json", "perf001-d1-no-audio-age.json", "sc015-pass.json"))
        self.assertEqual(bad["audioAgeP95Ms"], "fail")

    def test_each_kind_of_fail_fails_only_its_metric(self):
        cases = {
            "fps1sP5": ["perf012-d1-pass.json", "perf001-d1-fps-fail.json", "sc015-pass.json"],
            "frameIntervalP95Ms": ["perf012-d1-p95-fail.json", "perf001-d1-pass.json", "sc015-pass.json"],
            "droppedFramePercent": ["perf012-d1-drops-fail.json", "perf001-d1-pass.json", "sc015-pass.json"],
            "peakMemoryMB": ["perf012-d1-memory-fail.json", "perf001-d1-pass.json", "sc015-pass.json"],
            "coldLaunchMs": ["perf012-d1-pass.json", "perf001-d1-pass.json", "sc015-launch-fail.json"],
        }
        for metric, names in cases.items():
            verdict = self.check(*names)
            failed = [m for m, v in self.verdicts(verdict).items() if v == "fail"]
            self.assertEqual((verdict["overall"], failed), ("fail", [metric]), metric)
            self.assertEqual(cpt.exit_code(verdict), 1)
        row = next(r for r in self.check(*cases["droppedFramePercent"])["metrics"] if r["metric"] == "droppedFramePercent")
        self.assertEqual((row["value"], row["limit"], row["source"]), (10.0, 5, "perf012-d1-drops-fail.json"))

    def test_missing_metrics_read_not_measured_never_pass(self):
        verdict = self.check("perf012-d1-missing.json", "perf001-d1-no-audio-age.json")
        v = self.verdicts(verdict)
        self.assertEqual([m for m in v if v[m] == "not measured"],
                         ["frameIntervalP50Ms", "frameIntervalP95Ms", "audioAgeP95Ms", "coldLaunchMs"])
        self.assertEqual(verdict["overall"], "incomplete")
        self.assertEqual(cpt.exit_code(verdict), 1)
        invalid = self.verdicts(self.check("perf012-d1-invalid.json", *self.PASS[1:]))
        self.assertEqual(invalid["peakMemoryMB"], "not measured")

    def test_unknown_class_wrong_version_and_mixed_models_are_errors(self):
        cases = [
            (self.check("perf012-unknown-model.json"), "unknown device class: model iPhone18,3"),
            (self.check(*self.PASS, thresholds_path=self.F / "thresholds-wrong-schema.json"),
             "unsupported thresholds schemaVersion 2"),
            (self.check(*self.PASS, pinned=3), "thresholds version mismatch: file has 2, caller pinned 3"),
            (self.check("perf012-d3-pass.json", "perf001-d1-pass.json"), "mixed device models"),
            (self.check("sc015-pass.json"), "no device model"),
        ]
        for verdict, reason in cases:
            self.assertEqual(verdict["overall"], "error", reason)
            self.assertTrue(verdict["error"].startswith(reason), verdict["error"])
            self.assertNotIn("metrics", verdict)
            self.assertEqual(cpt.exit_code(verdict), 2)

    def test_class_limits_differ_and_simulator_is_not_evidence(self):
        d3 = self.check("perf012-d3-pass.json")
        self.assertEqual((d3["deviceClass"], self.verdicts(d3)["frameIntervalP95Ms"]), ("D3", "pass"))
        as_d1 = self.check("perf012-d3-pass.json", simulator=True)   # same figures under D1's limits
        self.assertEqual((as_d1["deviceClass"], as_d1["evidence"]), ("simulator", False))
        self.assertEqual(self.verdicts(as_d1)["frameIntervalP95Ms"], "fail")
        self.assertIn("not evidence", cpt.render_text(as_d1))

    def test_value_at_the_limit_passes_and_output_is_deterministic(self):
        doc = cpt.load_thresholds(cpt.THRESHOLDS)
        at = cpt.evaluate(doc, "iPhone15,4", {"peakMemoryMB": {"value": 300.0, "source": "x"}})
        self.assertEqual(self.verdicts(at)["peakMemoryMB"], "pass")
        first = cpt.render_json(self.check(*self.PASS))
        self.assertEqual(first, cpt.render_json(self.check(*reversed(self.PASS))))
        self.assertNotIn(str(self.F), first)   # base names only

    def test_cli_writes_the_verdict_and_returns_the_exit_code(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch("sys.stdout", new_callable=io.StringIO) as out:
            target = Path(tmp) / "v.json"
            code = cpt.main([str(self.F / n) for n in self.PASS] + ["--out", str(target)])
            self.assertEqual(code, 0)
            self.assertEqual(json.loads(target.read_text())["overall"], "pass")
            self.assertIn("overall: pass", out.getvalue())
            self.assertEqual(cpt.main([str(self.F / "sc015-pass.json"), "--device", "D3", "--json"]), 1)

    def test_runner_step_picks_the_newest_reports_and_writes_the_verdict(self):
        import shutil
        with tempfile.TemporaryDirectory() as tmp, mock.patch("sys.stdout", new_callable=io.StringIO):
            d = Path(tmp)
            shutil.copy(self.F / "perf001-d1-fps-fail.json", d / "automation-perf001-2026-11-14T100000Z.json")
            shutil.copy(self.F / "perf001-d1-pass.json", d / "automation-perf001-2026-11-14T110000Z.json")
            shutil.copy(self.F / "sc015-pass.json", d / "sc015.json")
            verdict = rdt.judge_thresholds(d, label="D1", simulator=False, extra=[self.F / "perf012-d1-pass.json"])
            self.assertEqual(verdict["overall"], "pass")
            self.assertEqual(json.loads((d / "performance-verdict.json").read_text()), verdict)
            again = rdt.judge_thresholds(d, label="D1", simulator=False, write=False)   # the verdict is not an input
            self.assertEqual(again["inputs"], ["automation-perf001-2026-11-14T110000Z.json", "sc015.json"])
            sim = rdt.judge_thresholds(d, label="sim", simulator=True, write=False)
            self.assertFalse(sim["evidence"])


QA011_FIXTURES = Path(__file__).resolve().parent / "fixtures" / "qa011"


class QA011InventoryTests(unittest.TestCase):
    """QA-011-T06, T16: parser, devices, status, classifier, sessions, checklist (specs/313)."""

    @classmethod
    def setUpClass(cls):
        cls.tasks = qa011.collect(QA011_FIXTURES / "specs")
        cls.by_id = {t["id"]: t for t in cls.tasks}

    def test_only_unchecked_tagged_tasks_are_listed(self):
        self.assertEqual(sorted(self.by_id), sorted([
            "PERF-001-T16", "PERF-001-T17", "PERF-001-T18", "PERF-001-T20", "OSC-001-T26", "OSC-001-T27",
            "REL-001-T05", "REL-001-T06", "T050", "T087"]))   # no format line, checked task or untagged task

    def test_continuation_lines_join_the_task(self):
        t = self.by_id["PERF-001-T16"]
        self.assertIn("`docs/test-reports/performance.md`", t["text"])
        self.assertEqual((t["spec"], t["feature"], t["line"]), ("101-perf-001-stage-timings", "PERF-001", 6))
        self.assertIn("recovers after a 10 s", self.by_id["OSC-001-T26"]["text"])

    def test_devices(self):
        cases = {"PERF-001-T16": ["D1"], "PERF-001-T17": ["D1", "D2", "D3"], "PERF-001-T20": ["D2", "D3"],
                 "OSC-001-T26": ["D1", "D2"], "OSC-001-T27": ["D3"], "T087": ["D1", "D2", "D3"]}
        for task_id, devices in cases.items():
            self.assertEqual(self.by_id[task_id]["devices"], devices, task_id)
        self.assertTrue(self.by_id["REL-001-T05"]["devicesInferred"])
        self.assertFalse(self.by_id["PERF-001-T20"]["devicesInferred"], "quickstart D3, D4 are sections, not devices")
        self.assertEqual(qa011.devices_of("On D1 and D3: x — Open: also D2 later")[0], ["D1", "D3"])
        self.assertEqual(qa011.devices_of("On D1–D3: x")[0], ["D1", "D2", "D3"])

    def test_status(self):
        self.assertEqual(self.by_id["T050"]["status"], "waived")
        self.assertIsNone(self.by_id["T050"]["session"])
        self.assertEqual(self.by_id["PERF-001-T18"]["status"], "optional")
        self.assertEqual(self.by_id["PERF-001-T16"]["status"], "open")

    def test_classifier(self):
        expect = {"PERF-001-T16": ("a", "MATRIX"), "PERF-001-T17": ("b", "B01"), "PERF-001-T18": ("b", "B13"),
                  "PERF-001-T20": ("b", "B02"), "OSC-001-T26": ("b", "B09"), "OSC-001-T27": ("b", "B10"),
                  "REL-001-T05": ("c", None), "REL-001-T06": ("b", "B13"), "T087": ("b", "B13")}
        for task_id, (category, session) in expect.items():
            t = self.by_id[task_id]
            self.assertEqual((t["category"], t["session"]), (category, session), task_id)
        self.assertEqual(self.by_id["PERF-001-T16"]["matrixCases"], ["autorun-perf001"])
        self.assertEqual(qa011.classify("CMP-001-T20", "On D1-D3: the spike tests", ["device"])[2],
                         ["xctest-angle-layer"], "a scripted part is linked")

    def test_every_category_a_case_exists_and_sessions_are_known(self):
        for task_id, cases in qa011.CATEGORY_A.items():
            self.assertTrue(set(cases) <= set(rdm.CASE_IDS), task_id)
        rules = [sid for sid, _ in qa011.HARDWARE_RULES + qa011.KEYWORD_RULES]
        rules += list(qa011.PREFIX_SESSIONS.values()) + list(qa011.SESSION_OVERRIDES.values())
        self.assertTrue(set(rules) <= set(qa011.SESSION_IDS))
        self.assertLessEqual(len(qa011.SESSIONS), 13)   # QA-011-S5

    def test_inventory_is_deterministic_and_checklist_covers_every_b_task(self):
        text1, checklist1 = qa011.generate(QA011_FIXTURES / "specs")
        text2, checklist2 = qa011.generate(QA011_FIXTURES / "specs")
        self.assertEqual((text1, checklist1), (text2, checklist2))
        inv = json.loads(text1)
        self.assertEqual(inv["counts"]["total"], 10)
        self.assertEqual(inv["counts"]["byCategory"], {"a": 1, "b": 7, "c": 1})
        in_sessions = [k for s in inv["sessions"] for k in s["tasks"]]
        b_tasks = [f"{t['spec']}:{t['id']}" for t in inv["tasks"] if t["category"] == "b" and t["status"] != "waived"]
        self.assertEqual(sorted(in_sessions), sorted(b_tasks), "each (b) task in exactly one session")
        for t in inv["tasks"]:
            if t["category"] == "b" and t["status"] != "waived":
                self.assertIn(f"`{t['id']}`", checklist1)
        self.assertIn("python3 scripts/run_device_matrix.py --device D2", checklist1)

    def test_check_detects_a_stale_inventory(self):
        with tempfile.TemporaryDirectory() as tmp:
            args = ["--specs", str(QA011_FIXTURES / "specs"), "--out-dir", tmp]
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(qa011.main(args), 0)
                self.assertEqual(qa011.main(args + ["--check"]), 0)
                inv = Path(tmp) / "device-inventory.json"
                inv.write_text(inv.read_text().replace('"open"', '"waived"', 1))
                self.assertEqual(qa011.main(args + ["--check"]), 1)

    def test_committed_inventory_is_current(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(qa011.main(["--check"]), 0, "run python3 scripts/qa011_inventory.py")


class QA011MatrixTests(unittest.TestCase):
    """QA-011-T12: case plan, dry run, lock detection, codesign, hashing, record writer (specs/313)."""

    def inventory(self):
        return {"tasks": [
            {"status": "open", "devices": ["D1"], "matrixCases": ["xctest-soak-600", "autorun-perf001"]},
            {"status": "open", "devices": ["D2", "D3"], "matrixCases": ["xctest-materials"]},
            {"status": "waived", "devices": ["D2"], "matrixCases": ["bench-cmp008"]},
            {"status": "open", "devices": ["D1"], "matrixCases": ["bench-cmp008"]}]}

    def test_plan_per_device(self):
        devices = rdm.case_devices(self.inventory())
        d1 = [c["id"] for c in rdm.plan("D1", devices)]
        d2 = [c["id"] for c in rdm.plan("D2", devices)]
        d3 = [c["id"] for c in rdm.plan("D3", devices)]
        self.assertIn("xctest-soak-600", d1)
        self.assertNotIn("xctest-soak-600", d2)
        self.assertIn("xctest-materials", d3)
        self.assertNotIn("bench-cmp008", d2, "a waived task adds no device")
        # xctest-angle-layer stays on D1-D3 by default (release evidence after CMP-001-T20 closed).
        self.assertEqual(d2, ["autorun-perf001", "launches-sc015", "thresholds", "xctest-materials", "xctest-angle-layer"])
        self.assertEqual([c["id"] for c in rdm.plan(None, devices)],
                         [c["id"] for c in rdm.CASES if not c.get("onDemand")], "on-demand cases only with --only")
        order = rdm.CASE_IDS
        self.assertEqual(order[-1], "xctest-offline-export", "the app-hosted suite replaces the app: last")
        self.assertLess(order.index("thresholds"), order.index("xctest-goldens"))

    def test_committed_inventory_drives_every_case(self):
        devices = rdm.case_devices(rdm.load_inventory())
        for c in rdm.CASES:
            self.assertTrue(devices[c["id"]], f"{c['id']} runs on no device")

    def test_dry_run_prints_commands_and_writes_nothing(self):
        before = sorted(p for p in rdm.RUNS.rglob("*")) if rdm.RUNS.exists() else []
        out = io.StringIO()
        try:
            with contextlib.redirect_stdout(out):
                code = rdm.main(["--device", "D1", "--dry-run", "--only", "autorun-perf001,xctest-soak-600"])
        finally:
            rdt.DRY_RUN = False
            rdt.LOCKED_WAIT = 30 * 60
        text = out.getvalue()
        self.assertEqual(code, 0)
        self.assertIn('"PROJECTM_AUTORUN": "perf001"', text)
        self.assertIn("devicectl device install app", text)
        self.assertIn("TEST_RUNNER_QA006_SOAK_SECONDS=600", text)
        # On a device, package suites run hosted in the app (DeviceTests.yml), signed through the app project.
        self.assertIn("-only-testing:RenderGoldensDeviceTests/RenderSoakTests/testOnDemandLongSoak", text)
        self.assertIn("ProjectM-DeviceTests.xcodeproj", text)
        self.assertIn("-allowProvisioningUpdates", text)
        self.assertIn("platform=iOS,id=<UDID>", text)
        after = sorted(p for p in rdm.RUNS.rglob("*")) if rdm.RUNS.exists() else []
        self.assertEqual(before, after)

    def test_counts_take_the_run_total_including_skipped_wording(self):
        log = ("Executed 1 test, with 0 failures (0 unexpected)\n"
               "Executed 134 tests, with 3 tests skipped and 2 failures (2 unexpected)\n"
               "Executed 12 tests, with 0 failures (0 unexpected)\n")
        self.assertTrue(rdm.test_counts(log).startswith("134 tests, 2 failures"))

    def test_signing_identity_keeps_only_the_certificate_type_and_team(self):
        text = ("Authority=Apple Development: JANE EXAMPLE (ABCDE12345)\n"
                "Authority=Apple Worldwide Developer Relations Certification Authority\n"
                "Authority=Apple Root CA\nTeamIdentifier=TEAM123456\n")
        s = rdm.parse_codesign(text)
        self.assertEqual(s["identity"], "Apple Development")
        self.assertEqual(s["team"], "TEAM123456")
        self.assertNotIn("JANE", json.dumps(s))
        self.assertNotIn("ABCDE12345", json.dumps(s))
        self.assertIn("Authority=Apple Root CA", s["raw"])
        self.assertIn("redaction", s)

    def test_device_package_cases_map_to_app_hosted_bundles(self):
        self.assertEqual(rdm.device_only_testing(["CompositorTests/LayerGradientCompositeTests/testX"]),
                         ["CompositorDeviceTests/LayerGradientCompositeTests/testX"])
        self.assertEqual(rdm.device_only_testing([], "RenderGoldens"), ["RenderGoldensDeviceTests"],
                         "an unfiltered case runs its package's bundle, never the whole scheme")
        self.assertEqual(rdm.device_only_testing(["ANGLERenderingTests/ProjectMLayerTests"]),
                         ["ANGLEDeviceTests/ProjectMLayerTests"])
        self.assertIsNone(rdm.device_only_testing(["SomeOtherTests/X"]))
        target = rdm.MatrixTarget("D1", "ID", False, Path("/tmp/x"), "UDID")
        case = dict(next(c for c in rdm.CASES if c["id"] == "xctest-angle-layer"), only=["SomeOtherTests/X"])
        with self.assertRaises(rdm.NoDeviceHost):
            rdm.xctest_command(case, target, Path("/tmp/d"), Path("/tmp/b.xcresult"))

    def test_xctest_command_on_a_simulator_is_unsigned(self):
        target = rdm.MatrixTarget("sim", "SIM-UDID", True, Path("/tmp/x"), "SIM-UDID")
        case = next(c for c in rdm.CASES if c["id"] == "bench-expression")
        cmd, cwd = rdm.xctest_command(case, target, Path("/tmp/dd"), Path("/tmp/r.xcresult"))
        self.assertIn("CODE_SIGNING_ALLOWED=NO", cmd)
        self.assertNotIn("-allowProvisioningUpdates", cmd)
        self.assertEqual(cmd[cmd.index("-configuration") + 1], "Release")
        self.assertEqual(cmd[cmd.index("-destination") + 1], "id=SIM-UDID")
        self.assertEqual(cwd.name, "ParameterGraph")

    def test_lock_detection(self):
        self.assertTrue(rdm.is_locked("error: Unable to launch: the device is locked"))
        self.assertTrue(rdm.is_locked('{"error": "Locked"}'))
        self.assertFalse(rdm.is_locked("Test Case testSceneLocked passed\nExecuted 3 tests, with 0 failures"))
        self.assertFalse(rdm.is_locked("** TEST FAILED ** 1 failure"))

    def test_codesign_parsing(self):
        signed = rdm.parse_codesign("Executable=/x\nAuthority=Apple Development: Owner (ABCDE12345)\n"
                                    "Authority=Apple Worldwide Developer Relations Certification Authority\n"
                                    "TeamIdentifier=TEAM123456\n")
        self.assertEqual((signed["signed"], signed["identity"], signed["team"], signed["adhoc"]),
                         (True, "Apple Development", "TEAM123456", False))   # name withheld (owner ruling)
        adhoc = rdm.parse_codesign("Signature=adhoc\nTeamIdentifier=not set\n")
        self.assertEqual((adhoc["signed"], adhoc["adhoc"], adhoc["team"]), (True, True, None))
        unsigned = rdm.parse_codesign("/x.app: code object is not signed at all\n")
        self.assertFalse(unsigned["signed"])

    def test_devicectl_facts(self):
        listing = json.loads((QA011_FIXTURES / "devicectl-list.json").read_text())
        d1 = rdm.device_facts(rdm.device_entry(listing, "D1"))
        self.assertEqual((d1["identifier"], d1["udid"], d1["osVersion"], d1["osBuild"]),
                         ("DEV-D1", "00008120-D1", "27.0.1", "24A446"), "the simulated iPhone15,4 is skipped")
        self.assertEqual(rdm.device_facts(rdm.device_entry(listing, "D3"))["state"], "unavailable")
        self.assertEqual(rdm.device_facts(rdm.device_entry(listing, "D2"))["state"], "not listed")

    def test_folder_hash_is_stable_and_sensitive(self):
        with tempfile.TemporaryDirectory() as tmp:
            a, b = Path(tmp) / "a.xcresult", Path(tmp) / "b.xcresult"
            for root in (a, b):
                (root / "Data").mkdir(parents=True)
                (root / "Info.plist").write_text("x")
                (root / "Data" / "1").write_bytes(b"\x00\x01")
            self.assertEqual(rdm.sha256_path(a), rdm.sha256_path(b))
            (b / "Data" / "1").write_bytes(b"\x00\x02")
            self.assertNotEqual(rdm.sha256_path(a), rdm.sha256_path(b))
            self.assertEqual(rdm.sha256_path(a / "Info.plist"), hashlib.sha256(b"x").hexdigest())

    def test_record_round_trip_and_tamper_detection(self):
        with tempfile.TemporaryDirectory(dir=rdm.ROOT / "scripts" / "fixtures" / "qa011") as tmp:
            d = Path(tmp)
            report = d / "artifacts" / "automation-perf001-1.json"
            report.parent.mkdir()
            report.write_text('{"ok": true}\n')
            record = {"kind": rdm.RECORD_KIND, "schemaVersion": 1, "runId": "20261115T000000Z", "label": "sim",
                      "evidence": False, "evidenceNote": "simulator rehearsal, not evidence", "dryRun": False,
                      "target": {"kind": "simulator", "name": "QA11"}, "app": {"commit": "abc"},
                      "signing": {"signed": False}, "host": {"xcode": "Xcode"}, "startedAt": "s", "finishedAt": "f",
                      "stopReason": None,
                      "cases": [{"id": "autorun-perf001", "status": "pass", "closes": ["PERF-001-T16"], "partOf": [],
                                 "durationSeconds": 1.0, "detail": "", "artifacts": [rdm.artifact(report, True)]}]}
            path = rdm.write_record(record, d)
            self.assertEqual(rdm.verify_record(path), [])
            self.assertEqual(json.loads(path.read_text())["summary"]["pass"], 1)
            self.assertIn("SIMULATOR REHEARSAL, NOT EVIDENCE", (d / "record.md").read_text())
            self.assertTrue((d / "record.json.sha256").read_text().startswith(record["recordSha256"]))
            report.write_text('{"ok": false}\n')
            self.assertEqual(rdm.verify_record(path), [f"artifact changed: {rdm.display_path(report)}"])
            report.unlink()
            self.assertEqual(rdm.verify_record(path), [f"missing artifact {rdm.display_path(report)}"])
            data = json.loads(path.read_text())
            data["label"] = "D1"
            path.write_text(json.dumps(data))
            self.assertIn("record hash does not match its content", rdm.verify_record(path))

    def test_device_runner_forwards_matrix(self):
        with mock.patch.object(rdm, "main", return_value=0) as forwarded:
            self.assertEqual(rdt.main(["--dry-run", "matrix", "--device", "D2"]), 0)
        forwarded.assert_called_once_with(["--dry-run", "--device", "D2"])


class ReleaseManifestTests(unittest.TestCase):
    """QA-012: the evidence manifest hashes files, counts only verified physical device records, lists gaps."""

    def tree(self) -> Path:
        root = Path(tempfile.mkdtemp())
        (root / "docs/test-reports/qa-011").mkdir(parents=True)
        (root / "docs/test-reports/a.md").write_text("report a\n")
        (root / "docs/test-reports/qa-011/runs/sim/r1").mkdir(parents=True)
        (root / "docs/test-reports/qa-011/runs/sim/r1/record.json").write_text("{}")
        (root / "docs/licenses").mkdir(parents=True)
        (root / "docs/licenses/x.txt").write_text("licence\n")
        (root / "docs/FEATURE_ROADMAP_AUTONOMOUS.md").write_text("roadmap\n")
        return root

    def record(self, root: Path, device: str, evidence: bool = True, fail: int = 0, tamper: bool = False) -> Path:
        rec = {"kind": "x", "runId": "20261115T000000Z", "evidence": evidence, "dryRun": False,
               "target": {"osVersion": "27.2", "osBuild": "24B1"}, "summary": {"pass": 3, "fail": fail}}
        rec["recordSha256"] = rdm.record_hash(rec)
        if tamper:
            rec["summary"]["pass"] = 99
        path = root / f"docs/test-reports/qa-011/runs/{device}/20261115T000000Z/record.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(rec))
        return path

    def state(self, root: Path, states: dict[str, str]) -> Path:
        path = root / "state.json"
        path.write_text(json.dumps({"run_id": "r", "features": {
            fid: {"state": st, "branch_sha": "b", "integrated_sha": "i",
                  "evidence": [{"command": "swift test", "exit_code": 0, "sha": "s", "at": "t"}]}
            for fid, st in states.items()}}))
        return path

    def test_files_are_hashed_simulator_runs_excluded_and_the_manifest_verifies(self):
        root = self.tree()
        m = rmf.build(root, self.state(root, {"A-1": "integrated"}), use_git=False, now="2026-11-15T00:00:00Z")
        paths = [f["path"] for f in m["groups"]["testReports"]]
        self.assertIn("docs/test-reports/a.md", paths)
        self.assertFalse(any("/runs/sim/" in p for p in paths), "simulator rehearsals are never evidence")
        self.assertEqual(m["groups"]["licenses"][0]["sha256"],
                         hashlib.sha256(b"licence\n").hexdigest())
        self.assertEqual(m["manifestSha256"], rmf.manifest_hash(m))
        self.assertEqual(rmf.verify(root, m, use_git=False), [])
        self.assertEqual(m["features"][0]["evidence"][0]["command"], "swift test")

    def test_verify_reports_a_changed_file_and_a_tampered_manifest(self):
        root = self.tree()
        m = rmf.build(root, None, use_git=False)
        (root / "docs/test-reports/a.md").write_text("changed\n")
        self.assertTrue(any("a.md changed" in p for p in rmf.verify(root, m, use_git=False)))
        m2 = dict(m, commit="f" * 40)
        self.assertTrue(any("manifestSha256" in p for p in rmf.verify(root, m2, use_git=False)))

    def test_only_verified_physical_device_records_count(self):
        root = self.tree()
        self.record(root, "D1")
        self.record(root, "D2", evidence=False)          # a rehearsal written as a device run
        self.record(root, "D3", tamper=True)
        dev = rmf.device_evidence(root, None)
        self.assertEqual(dev["D1"]["status"], "recorded")
        self.assertEqual(dev["D1"]["os"], "27.2")
        self.assertEqual(dev["D2"]["status"], "missing")
        self.assertIn("not a physical device run", dev["D2"]["problems"][0])
        self.assertEqual(dev["D3"]["status"], "missing")
        self.assertIn("does not verify", dev["D3"]["problems"][0])

    def test_gaps_keep_the_release_open_until_everything_is_recorded(self):
        root = self.tree()
        m = rmf.build(root, self.state(root, {"A-1": "integrated", "Q-1": "awaiting_final_device"}), use_git=False)
        self.assertFalse(m["releaseReady"])
        self.assertTrue(any(g.startswith("D1:") for g in m["gaps"]))
        self.assertTrue(any("awaiting the final device stage: Q-1" in g for g in m["gaps"]))
        for d in ("D1", "D2", "D3"):
            self.record(root, d)
        m = rmf.build(root, self.state(root, {"A-1": "integrated", "Q-1": "device_passed"}), use_git=False)
        self.assertEqual(m["gaps"], [])
        self.assertTrue(m["releaseReady"])
        self.record(root, "D2", fail=1)
        m = rmf.build(root, self.state(root, {"A-1": "integrated"}), use_git=False)
        self.assertIn("D2: QA-011 record has 1 failing case(s)", m["gaps"])

    def test_open_device_tasks_from_the_inventory_are_a_gap(self):
        root = self.tree()
        (root / "docs/test-reports/qa-011/device-inventory.json").write_text(json.dumps(
            {"tasks": [{"category": "a"}, {"category": "b", "status": "open"}, {"category": "b"},
                       {"category": "b", "status": "waived"}, {"category": "a", "status": "optional"}]}))
        m = rmf.build(root, None, use_git=False)
        self.assertEqual(m["openDeviceTasks"]["byCategory"], {"a": 1, "b": 2})
        self.assertEqual(m["openDeviceTasks"]["notCounted"], 2, "waived and optional tasks do not hold a release")
        self.assertIn("3 open {device}/{owner} tasks (QA-011 inventory)", m["gaps"])


class MacDeviceDriverTests(unittest.TestCase):
    """mac_device_driver.py and scripts/mac_driver (QA-011 Batch 1): MAC-DO requests from the xcodebuild log."""

    def test_parse_request_reads_the_json_after_the_marker(self):
        line = 'Test Case ... 2026-11-18 MAC-DO {"action": "audio.stop", "id": "3"}'
        self.assertEqual(mac_driver.parse_request(line), {"action": "audio.stop", "id": "3"})
        self.assertIsNone(mac_driver.parse_request("MAC-DO {not json"))
        self.assertIsNone(mac_driver.parse_request('MAC-DO {"action": "nomodule"}'))
        self.assertIsNone(mac_driver.parse_request("OSC-READY test"))

    def test_only_package_modules_resolve(self):
        context = mac_driver.Context(dry_run=True)
        self.assertTrue(mac_driver.dispatch({"action": "../etc.x"}, context).startswith("error"))
        self.assertTrue(mac_driver.dispatch({"action": "os.system"}, context).startswith("error"))
        self.assertTrue(mac_driver.dispatch({"action": "audio.nothing"}, context).startswith("error"))
        self.assertEqual(mac_driver.dispatch({"action": "audio.stop"}, context), "nothing playing")

    def test_audio_play_stays_inside_the_repository(self):
        context = mac_driver.Context(dry_run=True)
        self.assertTrue(mac_driver.dispatch({"action": "audio.play", "file": "../../etc/hosts"}, context).startswith("error"))
        result = mac_driver.dispatch({"action": "audio.play", "file": "scripts/make_music_fixture.py", "seconds": 2,
                                      "volume": 0.5}, context)
        self.assertEqual(result, "playing make_music_fixture.py")
        self.assertTrue(context.log[-1].startswith("afplay ") and "-t 2.0 -v 0.5 &" in context.log[-1], context.log)

    def test_memory_warning_finds_the_app_pid(self):
        processes = {"result": {"runningProcesses": [
            {"executable": "file:///usr/libexec/backboardd", "processIdentifier": 40},
            {"executable": "file:///private/var/containers/Bundle/Application/X/projectM-iOS.app/projectM-iOS",
             "processIdentifier": 812}]}}
        from mac_driver import memory
        self.assertEqual(memory.app_pid(processes), 812)
        self.assertIsNone(memory.app_pid({"result": {"runningProcesses": []}}))

    def test_crash_reports_since_a_time(self):
        from mac_driver import device
        listing = {"result": {"files": [
            {"relativePath": "projectM-iOS-2026-11-18-101500.ips", "lastModDate": "2026-11-18T10:15:00Z"},
            {"relativePath": "projectM-iOS-2026-11-17-090000.ips", "lastModDate": "2026-11-17T09:00:00Z"},
            {"relativePath": "Camera-2026-11-18-101600.ips", "lastModDate": "2026-11-18T10:16:00Z"}]}}
        since = 1_794_996_000.0   # 2026-11-18T10:00:00Z
        self.assertEqual(device.crash_reports(listing, "projectM", since), ["projectM-iOS-2026-11-18-101500.ips"])

    def test_follow_answers_each_request_once_and_stops_at_the_end_marker(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "x.log"
            log.write_text('MAC-DO {"action": "audio.stop", "id": "1"}\nnoise\nMAC-DO {"action": "audio.tone", '
                           '"id": "2", "hz": 220, "seconds": 0.01}\n** TEST EXECUTE SUCCEEDED **\n'
                           'MAC-DO {"action": "audio.stop", "id": "9"}\n')
            lines: list[str] = []
            context = mac_driver.Context(dry_run=True)
            self.assertEqual(mdd.follow(log, context, timeout=5, out=lines.append, poll=0.01), 0)
        self.assertEqual(len(lines), 2, lines)
        self.assertTrue(lines[0].startswith("MAC-DONE 1 ") and lines[0].endswith("audio.stop: nothing playing"))
        self.assertIn("audio.tone: tone 220 Hz", lines[1])

    def test_prompt_flow_reinstalls_then_runs_the_class_alone(self):
        cmds = mdd.prompt_flow_commands("DEV", "UDID", Path("Build/da"), Path("Build/da/app"), Path("logs"), osc=True)
        self.assertEqual(cmds[0][:5], ["xcrun", "devicectl", "device", "uninstall", "app"])
        self.assertEqual(cmds[1][:5], ["xcrun", "devicectl", "device", "install", "app"])
        self.assertIn("--media", cmds[2])
        test = cmds[3]
        self.assertIn("-only-testing:projectM-iOSDeviceUITests/PromptFlowDeviceTests", test)
        self.assertEqual(sum(a.startswith("-only-testing") for a in test), 1, "the prompt flow runs alone")
        self.assertIn("TEST_RUNNER_MAC_DRIVER=1", test)
        self.assertIn("TEST_RUNNER_OSC_DRIVER=1", test)
        self.assertIn("platform=iOS,id=UDID", test)

    def test_device_ids_map_product_types(self):
        listing = {"result": {"devices": [
            {"identifier": "A", "hardwareProperties": {"productType": "iPhone15,4", "udid": "U1"}},
            {"identifier": "B", "hardwareProperties": {"productType": "iPad99,1", "udid": "U9"}}]}}
        self.assertEqual(mdd.device_ids(listing), {"D1": ("A", "U1")})

    def test_autotester_documents_the_prompt_flow_batch(self):
        """Owner rule 14 (2026-11-18): the self-answering prompt flow is its own batch, excluded from other runs."""
        doc = (Path(__file__).resolve().parent.parent / "docs" / "autotester.md").read_text(encoding="utf-8")
        self.assertIn("-skip-testing:projectM-iOSDeviceUITests/PromptFlowDeviceTests", doc)
        self.assertIn("mac_device_driver.py prompt-flow", doc)


class MediaFixtureTests(unittest.TestCase):
    """make_media_fixtures.py (QA-011 Batch 1): the Python-made fixtures and the catalog."""

    def test_preset_is_exactly_the_size_limit_and_valid(self):
        data = mmf.preset_of_size()
        self.assertEqual(len(data), 524_288)
        self.assertTrue(data.startswith(b"[preset00]\n"))
        for size in (300, 301, 302, 1000):
            self.assertEqual(len(mmf.preset_of_size(size)), size)

    def test_strobe_preset_is_flagged(self):
        import preset_flash_risk
        self.assertTrue(preset_flash_risk.may_flash(mmf.strobe_preset()))

    def test_pdf_is_a_pdf(self):
        data = mmf.pdf_bytes()
        self.assertTrue(data.startswith(b"%PDF-1.4"))
        self.assertTrue(data.rstrip().endswith(b"%%EOF"))
        xref = int(data.split(b"startxref\n")[1].split(b"\n")[0])
        self.assertEqual(data[xref:xref + 4], b"xref")

    def test_damage_m4a_breaks_the_moov_atom(self):
        def atom(kind: bytes, body: bytes) -> bytes:
            return struct.pack(">I4s", 8 + len(body), kind) + body
        ftyp, moov, mdat = atom(b"ftyp", b"M4A \0\0\0\0"), atom(b"moov", b"m" * 40), atom(b"mdat", b"a" * 64)
        early = mmf.damage_m4a(ftyp + moov + mdat)
        self.assertEqual(len(early), len(ftyp + moov + mdat), "same size, audio data kept")
        self.assertTrue(early.endswith(mdat))
        self.assertEqual(early[len(ftyp) + 16:len(ftyp) + len(moov)], bytes(len(moov) - 16), "index zeroed")
        late = mmf.damage_m4a(ftyp + mdat + moov)
        self.assertEqual(late, ftyp + mdat + moov[:16], "cut inside a trailing moov")
        with self.assertRaises(ValueError):
            mmf.damage_m4a(ftyp + mdat)

    def test_click_track_has_a_click_on_every_beat(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "c.wav"
            mmf.click_track(path, seconds=2)
            with wave.open(str(path)) as w:
                rate, frames = w.getframerate(), w.readframes(w.getnframes())
        samples = struct.unpack(f"<{len(frames) // 2}h", frames)
        onsets = [i for i in range(1, len(samples))
                  if samples[i] != 0 and all(s == 0 for s in samples[max(0, i - 200):i])]
        self.assertEqual(len(onsets), 4, "120 BPM: four clicks in 2 s")
        self.assertAlmostEqual((onsets[1] - onsets[0]) / rate, 0.5, delta=0.01)

    def test_catalog_makers_and_install_list(self):
        self.assertTrue(all(maker in ("swift", "audio", "python") for maker, _ in mmf.CATALOG.values()))
        swift = (Path(__file__).resolve().parent / "fixtures" / "make_media.swift").read_text(encoding="utf-8")
        for name, (maker, _) in mmf.CATALOG.items():
            if maker == "swift":
                self.assertIn(f'case "{name}"', swift, name)
        self.assertNotIn(".mp3", " ".join(n for n in mmf.CATALOG if n != "not-audio.mp3"), "no MP3 encoder on the Mac")
        cmd = itf.copy_command("DEV", Path("/x/photo-gps.heic"))
        self.assertEqual(cmd[-2:], ["--destination", "Documents/photo-gps.heic"])


class QA011Batch2Tests(unittest.TestCase):
    """QA-011 Batch 2 (2026-11-18): on-demand and prompting cases, xctrace parsing and verdicts, RendererLab's
    flashcost budget, device goldens import."""

    SIGNPOSTS = """<?xml version="1.0"?>
<trace-query-result><node xpath='//x'><schema name="os-signpost">
<col><mnemonic>time</mnemonic><name>Time</name><engineering-type>event-time</engineering-type></col>
<col><mnemonic>event-type</mnemonic><name>Type</name></col>
<col><mnemonic>name</mnemonic><name>Name</name></col>
<col><mnemonic>process</mnemonic><name>Process</name></col>
</schema>
<row><event-time id="1" fmt="00:01.000">1000000000</event-time><event-type id="2" fmt="Event">Event</event-type><string id="3" fmt="QA-011 start">QA-011 start</string><process id="4" fmt="projectM-iOS (12)"><pid fmt="12">12</pid></process></row>
<row><event-time id="5" fmt="00:02.000">2000000000</event-time><event-type id="6" fmt="Begin">Begin</event-type><string id="7" fmt="PERF-004 texture allocation">PERF-004 texture allocation</string><process ref="4"/></row>
<row><event-time id="8" fmt="00:11.000">11000000000</event-time><event-type ref="2"/><string id="9" fmt="QA-011 rotate">QA-011 rotate</string><process ref="4"/></row>
<row><event-time id="10" fmt="00:12.000">12000000000</event-time><event-type ref="6"/><string ref="7"/><process ref="4"/></row>
<row><event-time id="11" fmt="00:21.000">21000000000</event-time><event-type ref="2"/><string id="12" fmt="QA-011 rotate back">QA-011 rotate back</string><process ref="4"/></row>
<row><sentinel/><event-type ref="2"/><string ref="7"/><process ref="4"/></row>
</node></trace-query-result>"""

    def setUp(self):
        from mac_driver import xctrace
        self.xt = xctrace

    def test_on_demand_and_prompting_cases(self):
        devices = rdm.case_devices(rdm.load_inventory())
        plain = [c["id"] for c in rdm.plan("D1", devices)]
        for cid in ("autorun-sc009", "xctrace-perf008", "xctest-goldens-record"):
            self.assertNotIn(cid, plain, f"{cid} is on demand")
            self.assertEqual([c["id"] for c in rdm.plan("D1", devices, {cid})], [cid])
        self.assertIn("D3", devices["autorun-sc009"], "AUD-014-T32 runs on D1 and D3")
        self.assertIn("xctrace-perf004", plain)
        self.assertEqual(rdm.CASE_IDS[-1], "xctest-offline-export")
        case = next(c for c in rdm.CASES if c["id"] == "autorun-sc009")
        runner = rdm.Runner(rdm.MatrixTarget("D1", "ID", False, Path("/tmp/x"), "UDID"), Path("/tmp/w"), 1, [], True)
        runner.fresh_install = True
        with contextlib.redirect_stdout(io.StringIO()):
            result = runner.run_case(case)
        self.assertEqual(result["status"], "not-run")
        self.assertIn("prompt-flow batch", result["detail"])

    def test_record_command_and_toc(self):
        cmd = self.xt.record_command("UDID", "Logging", 40, Path("/t/x.trace"), "org.b", env={"PROJECTM_AUTORUN": "perf004"},
                                     instruments=["os_signpost"])
        self.assertEqual(cmd[:4], ["xcrun", "xctrace", "record", "--template"])
        self.assertEqual(cmd[-3:], ["--launch", "--", "org.b"])
        self.assertIn("--env", cmd)
        self.assertIn("PROJECTM_AUTORUN=perf004", cmd)
        self.assertIn("40s", cmd)
        toc = ('<trace-toc><run number="1"><data><table schema="os-signpost" category="x"/>'
               '<table schema="metal-gpu-intervals"/><table schema="os-signpost"/></data></run></trace-toc>')
        self.assertEqual(self.xt.parse_toc(toc), [{"run": 1, "schema": "os-signpost"}, {"run": 1, "schema": "metal-gpu-intervals"}])
        self.assertIn('table[@schema="os-signpost"]', self.xt.export_command(Path("/t"), "os-signpost", Path("/o"))[-3])

    def test_signposts_and_perf004_verdict(self):
        rows = self.xt.parse_table(self.SIGNPOSTS)
        self.assertEqual(len(rows), 6)
        self.assertEqual(rows[3]["name"]["fmt"], "PERF-004 texture allocation", "refs resolve")
        events = self.xt.signpost_events(rows)
        self.assertEqual(len(events), 5, "the sentinel row has no time")
        verdict = self.xt.perf004_verdict(events)
        self.assertTrue(verdict["pass"], verdict)
        self.assertEqual((verdict["atStart"], verdict["atSizeChanges"]), (1, 1))
        stray = events + [(16.0, "PERF-004 texture allocation")]
        self.assertFalse(self.xt.perf004_verdict(sorted(stray))["pass"])
        self.assertFalse(self.xt.perf004_verdict([(1.0, "PERF-004 texture allocation")])["pass"], "no markers")
        self.assertFalse(self.xt.perf004_verdict([(1.0, "QA-011 start")])["pass"], "nothing allocated: nothing measured")
        self.assertEqual(self.xt.marker_times(events), {"start": 1.0, "rotate": 11.0, "rotate back": 21.0})

    def test_perf011_verdict(self):
        samples = [{"t": float(t), "state": 0 if t < 10 or t > 30 else 2, "frames": 0 if 10 <= t <= 30 else 60,
                    "footprintMB": 300 if t < 10 or t > 30 else 180} for t in range(1, 41)]
        report = {"samples": samples, "backgroundedAt": 10.0, "activeAgainAt": 30.5, "firstFrameAfterReturnSeconds": 0.4}
        verdict = self.xt.perf011_verdict(report)
        self.assertTrue(verdict["pass"], verdict)
        events = [(5.0, "QA-011 background"), (26.0, "QA-011 foreground")]
        gpu = [{"start": {"raw": str(int(20e9)), "fmt": "", "tag": "start-time"},
                "process": {"raw": "projectM-iOS", "fmt": "projectM-iOS (12)", "tag": "process"}}]
        self.assertFalse(self.xt.perf011_verdict(report, gpu, events)["pass"], "a GPU interval 15 s after backgrounding")
        late = dict(report, firstFrameAfterReturnSeconds=3.5)
        self.assertFalse(self.xt.perf011_verdict(late)["pass"])
        self.assertFalse(self.xt.perf011_verdict(dict(report, backgroundedAt=-1))["pass"], "never backgrounded")

    def test_flashcost_and_perf008_verdicts(self):
        report = {"summary": {"presets": 2, "costMsMedian": 1.2, "costMsMax": 1.6},
                  "flashCost": [{"id": "a", "costMs": 1.2}, {"id": "b", "costMs": 1.6}], "thermalStates": ["nominal"]}
        self.assertTrue(rdm.flashcost_verdict(report, 2.0)["pass"])
        over = {"summary": {"presets": 1, "costMsMedian": 2.4, "costMsMax": 2.4}, "flashCost": [{"id": "x", "costMs": 2.4}]}
        verdict = rdm.flashcost_verdict(over, 2.0)
        self.assertFalse(verdict["pass"])
        self.assertEqual(verdict["over"], ["x"])
        self.assertFalse(rdm.flashcost_verdict({"summary": {}}, 2.0)["pass"])
        runs = [{"name": "perf008-standard", "report": {"profile": "standard", "fps": [60.0] * 9}, "tables": {}},
                {"name": "perf008-batterySaver", "report": {"profile": "batterySaver", "fps": [30.0] * 9}, "tables": {}}]
        self.assertTrue(rdm.verdict_perf008(runs)["pass"])
        self.assertFalse(rdm.verdict_perf008(runs[:1])["pass"])
        rows = [{"time": {"raw": str(int(t * 1e9)), "fmt": "", "tag": "event-time"},
                 "energy-impact": {"raw": str(v), "fmt": "", "tag": "x"}} for t, v in ((10, 2), (50, 4), (70, 6))]
        per = self.xt.per_minute(rows)
        self.assertEqual(per["column"], "energy-impact")
        self.assertEqual([m["mean"] for m in per["minutes"]], [3.0, 6.0])
        self.assertEqual(rdm.dig({"a": {"b": 1}}, "a.b"), 1)
        self.assertIsNone(rdm.dig({"a": {}}, "a.b"))

    def test_device_goldens_import(self):
        import base64
        import import_device_goldens as idg
        png = b"\x89PNG fake"
        entry = {"scene": "photo-gradient", "frame": 7, "width": 128, "height": 96, "file": "photo-gradient-128x96-f7.png",
                 "pixelSHA256": "ab", "fileSHA256": hashlib.sha256(png).hexdigest(), "osSensitive": False}
        capture = {"kind": idg.KIND, "goldenClass": "ios-device-iphone15-4", "recordedOS": "27.0", "recordedGPU": "Apple A16 GPU",
                   "entry": entry, "png": base64.b64encode(png).decode()}
        second = json.loads(json.dumps(capture))
        second["entry"].update(width=256, height=192, file="photo-gradient-256x192-f7.png")
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "attachments"
            folder.mkdir()
            (folder / "b.json").write_text(json.dumps(second))
            (folder / "a.json").write_text(json.dumps(capture))
            (folder / "other.json").write_text('{"kind": "something else"}')
            captures = idg.read_captures(folder)
            self.assertEqual(len(captures), 2)
            golden_class, manifest, files = idg.build(captures)
            out = idg.write(golden_class, manifest, files, Path(tmp) / "Goldens")
            text = (out / "manifest.json").read_text()
            self.assertTrue(text.endswith("}\n"))
            self.assertIn('"platform" : "ios-device-iphone15-4"', text)
            parsed = json.loads(text)
            self.assertEqual([e["width"] for e in parsed["entries"]], [128, 256], "canonical order")
            self.assertEqual((out / entry["file"]).read_bytes(), png)
            bad = json.loads(json.dumps(capture))
            bad["entry"]["fileSHA256"] = "00"
            with self.assertRaises(ValueError):
                idg.build([bad])
            other_os = json.loads(json.dumps(second))
            other_os["recordedOS"] = "26.5"
            with self.assertRaises(ValueError):
                idg.build([capture, other_os])


class Batch8DriverTests(unittest.TestCase):
    """QA-011 Batch 8: the OSC driver's decoder and checks, the MIDI scenarios, the two-device orchestrator."""

    @classmethod
    def setUpClass(cls):
        import importlib
        cls.osc = importlib.import_module("osc_device_driver")
        cls.midi = importlib.import_module("mac_driver.midi")
        cls.peer = importlib.import_module("mac_driver.peer")
        cls.dev = importlib.import_module("mac_driver.devices")

    def test_osc_message_round_trips_through_the_decoder(self):
        self.assertEqual(self.osc.decode(self.osc.message("/projectm/param/glow.intensity", 0.5)),
                         ("/projectm/param/glow.intensity", [0.5]))
        string_msg = self.osc.pad(b"/projectm/scene") + self.osc.pad(b",si") + self.osc.pad(b"Drop") + struct.pack(">i", 3)
        self.assertEqual(self.osc.decode(string_msg), ("/projectm/scene", ["Drop", 3]))

    def test_batch8_scenarios_send_the_documented_addresses(self):
        self.assertEqual(self.osc.SIMPLE["glow-low"], ("/projectm/param/glow.intensity", 0.2))
        self.assertEqual(self.osc.SIMPLE["learn"][0], "/b8/fader/9")
        self.assertEqual(self.osc.SIMPLE["test2"], ("/projectm/test", 0.43))

    def test_listen_check_needs_status_and_two_scene_messages(self):
        ok, counts = self.osc.check_listen(["/projectm/status", "/projectm/scene", "/projectm/scene"])
        self.assertTrue(ok)
        self.assertEqual(counts["/projectm/scene"], 2)
        self.assertFalse(self.osc.check_listen(["/projectm/scene", "/projectm/scene"])[0])

    def test_export_check_finds_missing_routes_and_addresses(self):
        text = "| /projectm/test | osc.receiver.testValue |\n| /projectm/param/glow.intensity | effect.bloom.intensity |\n"
        self.assertEqual(self.osc.check_export(text, ["/projectm/test"]), [])
        problems = self.osc.check_export(text + "listening on 192.168.1.4 port 9000\n", ["/projectm/test", "/b8/x"])
        self.assertIn("missing route /b8/x", problems)
        self.assertTrue(any("IP address" in p for p in problems))
        self.assertTrue(any("port" in p for p in problems))
        self.assertIn("the test printed no OSC-ROUTES line", self.osc.check_export(text, []))

    def test_midi_scenarios_are_well_formed_helper_commands(self):
        verbs = {"cc", "note", "off", "pc", "cc14", "ramp14", "sweep", "clock", "start", "stop", "sleep"}
        for name, commands in self.midi.SCENARIOS.items():
            for command in commands:
                self.assertIn(command.split()[0], verbs, f"{name}: {command}")
        self.assertEqual(self.midi.SCENARIOS["pad60"][-1], "note 0 60 0", "MIDI-006: velocity-0 note-on is the release")

    def test_midi_feedback_fails_on_an_echo_after_the_moves(self):
        quiet = self.midi.feedback_result([10.0, 10.5, 11.0], window_start=9.0, sends_end=11.0, now=14.0)
        self.assertTrue(quiet["ok"])
        echo = self.midi.feedback_result([10.0, 13.5], window_start=9.0, sends_end=11.0, now=14.0)
        self.assertFalse(echo["ok"])
        self.assertEqual(echo["afterTheMoves"], 1)

    def test_peer_pairs_steps_with_the_followers_changes(self):
        steps = self.peer.parse_marks(["x PEER-STEP cue=2 t=100.0", "PEER-STEP cue=3 t=104.0", "noise"], "STEP")
        seen = self.peer.parse_marks(["PEER-SEEN cue=2 t=100.2", "PEER-SEEN cue=3 t=104.3"], "SEEN")
        self.assertEqual(steps, [(2, 100.0), (3, 104.0)])
        result = self.peer.pair_latencies(steps, seen)
        self.assertTrue(result["ok"])
        self.assertEqual(result["max"], 0.3)
        self.assertFalse(self.peer.pair_latencies(steps, [(2, 100.9), (3, 104.9)])["ok"], "0.9 s is too late")

    def test_peer_command_passes_each_filter_and_runner_value_separately(self):
        cmd = self.peer.test_command(Path("x.xctestrun"), "UDID", "B09OSCPeerDeviceTests/testOSC012Lead",
                                     {"PEER_IP": "10.0.0.2", "MAC_IP": "10.0.0.1"})
        self.assertIn("-only-testing:projectM-iOSDeviceUITests/B09OSCPeerDeviceTests/testOSC012Lead", cmd)
        self.assertIn("TEST_RUNNER_PEER_IP=10.0.0.2", cmd)
        self.assertIn("platform=iOS,id=UDID", cmd)
        for plan in self.peer.PLANS.values():
            self.assertNotEqual(plan["first"][0], plan["second"][0], "two devices")

    def test_devices_parse_listing_dscacheutil_and_newest(self):
        listing = {"result": {"devices": [{"identifier": "A", "hardwareProperties": {"productType": "iPhone15,4", "udid": "U1"}}]}}
        self.assertEqual(self.dev.parse_device_list(listing), {"D1": {"identifier": "A", "udid": "U1"}})
        self.assertEqual(self.dev.parse_dscacheutil("name: iPhone77.local\nip_address: 192.168.1.7\n"), "192.168.1.7")
        names = ["Documents/projectM-osc-routes-20261118-100000Z.md", "projectM-osc-routes-20261118-110000Z.md", "a.md"]
        self.assertEqual(self.dev.newest(names, "projectM-osc-routes-", ".md"), "projectM-osc-routes-20261118-110000Z.md")


class RecordingFrameCheckTests(unittest.TestCase):
    """QA-011 Batch 6: recording_frame_check.py (log lines, file choice, atoms, sips, OCR, centre, A/V alignment)."""

    @classmethod
    def setUpClass(cls):
        import importlib
        cls.rfc = importlib.import_module("recording_frame_check")

    def test_parses_check_lines_behind_xcodebuild_prefixes(self):
        lines = ['t = 1.2s RECORDING-CHECK {"task": "REC-016-T13", "dir": "tmp/QA011-REC016", "checks": {}}',
                 "RECORDING-CHECK {broken", "noise",
                 'RECORDING-CHECK {"task": "QA-008-T10", "dir": "tmp/QA011-REC016"}']
        self.assertEqual([c["task"] for c in self.rfc.parse_checks(lines)], ["REC-016-T13", "QA-008-T10"])

    def test_picks_the_newest_file_of_this_run(self):
        names = ["tmp/x/Visualizer Recording 2026-11-18 at 09.00.00.mp4",
                 "Visualizer Recording 2026-11-18 at 14.05.32.mp4", "Visualizer Frame 2026-11-18 at 15.00.00.png",
                 "Visualizer Recording 2026-11-17 at 23.59.59.mp4"]
        pick = self.rfc.pick
        self.assertEqual(pick(names, "Visualizer Recording", ".mp4"), "Visualizer Recording 2026-11-18 at 14.05.32.mp4")
        self.assertIsNone(pick(names, "Visualizer Recording", ".mp4", not_before="2026-11-18 at 14.06.00"),
                          "an older run's file is never taken for this run's")
        self.assertEqual(pick(names, "Visualizer Frame", ".png", "2026-11-18 at 14.00.00"),
                         "Visualizer Frame 2026-11-18 at 15.00.00.png")
        self.assertEqual(pick(["QA011 REC010 1.mp4"], exact="QA011 REC010 1.mp4"), "QA011 REC010 1.mp4")
        self.assertIsNone(pick([], exact="QA011 REC010 1.mp4"))

    def test_top_level_atoms_find_moov_and_moof(self):
        def box(kind, body=b""):
            return struct.pack(">I4s", 8 + len(body), kind) + body
        plain = box(b"ftyp", b"isom") + box(b"mdat", b"\0" * 32) + box(b"moov", box(b"mvhd", b"\0" * 8))
        fragmented = box(b"ftyp") + box(b"moov") + box(b"moof", b"\0" * 4) + box(b"mdat")
        large = box(b"ftyp") + struct.pack(">I4sQ", 1, b"mdat", 16 + 4) + b"\0" * 4 + box(b"moov")
        self.assertEqual(self.rfc.top_level_atoms(plain), ["ftyp", "mdat", "moov"])
        self.assertIn("moof", self.rfc.top_level_atoms(fragmented))
        self.assertEqual(self.rfc.top_level_atoms(large), ["ftyp", "mdat", "moov"])
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "x.mp4"
            path.write_bytes(large)
            self.assertEqual(self.rfc.file_atoms(path), ["ftyp", "mdat", "moov"])
            result = self.rfc.evaluate(path, {"atoms": {"present": ["moov"], "absent": ["moof"]}}, inspect=lambda *a: {})
            self.assertTrue(result["ok"])
            path.write_bytes(fragmented)
            self.assertFalse(self.rfc.evaluate(path, {"atoms": {"absent": ["moof"]}}, inspect=lambda *a: {})["ok"])

    def test_sips_output_and_the_image_check(self):
        text = "/x/Visualizer Frame.png\n  pixelWidth: 1179\n  pixelHeight: 2556\n  format: png\n  hasAlpha: yes\n"
        facts = self.rfc.parse_sips(text)
        self.assertEqual(facts["pixelWidth"], 1179)
        self.assertEqual(facts["format"], "png")
        path = Path("unused.png")
        ok = self.rfc.evaluate(path, {"image": {"format": "png", "minPixels": 500_000}}, read_sips=lambda p: facts)
        self.assertTrue(ok["ok"])
        heif = self.rfc.evaluate(path, {"image": {"format": "heic"}}, read_sips=lambda p: facts)
        self.assertFalse(heif["ok"], "a PNG is not the HEIF that was asked for")

    def test_ocr_absent_any_and_pattern(self):
        frames = [{"t": 1, "texts": ["14.05", "Hello"]}, {"t": 2.5, "texts": ["14:05"]}, {"t": 4, "texts": []}]
        fake = lambda *args: {"frames": frames} if args[0] == "ocr" else {}
        absent = self.rfc.evaluate(Path("x"), {"ocrAbsent": {"times": [1, 2.5], "strings": ["min left", "fps"]}}, inspect=fake)
        self.assertTrue(absent["ok"])
        status = self.rfc.evaluate(Path("x"), {"ocrAbsent": {"strings": ["hello"]}}, inspect=fake)
        self.assertFalse(status["ok"], "a status word in a frame fails REC-009")
        clock = self.rfc.evaluate(Path("x"), {"ocrAny": {"strings": ["14:05"], "minFrames": 2}}, inspect=fake)
        self.assertTrue(clock["ok"], "Vision's 14.05 counts as 14:05")
        countdown = [{"t": 1, "texts": ["00:08"]}, {"t": 2.5, "texts": ["00:06"]}, {"t": 9.5, "texts": ["00:00"]}]
        fake2 = lambda *args: {"frames": countdown}
        spec = {"ocrPattern": {"times": [1, 2.5, 9.5], "pattern": "[0-9]{2}:[0-9]{2}", "minFrames": 3, "last": "00:00"}}
        self.assertTrue(self.rfc.evaluate(Path("x"), spec, inspect=fake2)["ok"])
        countdown[-1]["texts"] = ["00:01"]
        self.assertFalse(self.rfc.evaluate(Path("x"), spec, inspect=fake2)["ok"], "it must hold at 00:00")

    def test_centre_correlation(self):
        grid = [10, 200, 10, 200, 90, 90, 10, 200, 10]
        fake = lambda *args: {"values": [12, 190, 14, 205, 88, 95, 9, 198, 11]}
        spec = {"centre": {"time": 2, "cols": 3, "rows": 3, "values": grid, "minCorrelation": 0.8}}
        self.assertTrue(self.rfc.evaluate(Path("x"), spec, inspect=fake)["ok"])
        off = lambda *args: {"values": [200, 10, 200, 10, 90, 90, 200, 10, 200]}
        self.assertFalse(self.rfc.evaluate(Path("x"), spec, inspect=off)["ok"], "an off-centre crop does not correlate")
        self.assertEqual(self.rfc.pearson([1, 2], [1]), 0.0)

    def test_clicks_flashes_and_alignment(self):
        bin_ms = 1
        peaks = [0.0] * 6000
        for beat in range(12):   # 120 BPM: a click every 0.5 s from 0.2 s
            peaks[200 + beat * 500] = 0.9
        clicks = self.rfc.click_onsets(peaks, bin_ms)
        self.assertEqual(len(clicks), 12)
        self.assertAlmostEqual(clicks[1] - clicks[0], 0.5, places=3)
        frames = []
        for i in range(180):   # 30 fps, 6 s; each ring flashes 1 frame (33 ms) after its click
            t = i / 30
            lit = any(0 <= t - (c + 0.03) < 0.1 for c in clicks)
            frames.append([t, 0.4 if lit else 0.05])
        flashes = self.rfc.flash_onsets(frames)
        result = self.rfc.alignment(clicks, flashes)
        self.assertEqual(result["paired"], 12)
        self.assertLessEqual(abs(result["medianMs"]), 40)
        late = self.rfc.alignment(clicks, [round(c + 0.12, 4) for c in clicks])
        self.assertGreater(late["medianMs"], 40, "a 120 ms lag fails REC-004-S5")
        self.assertEqual(self.rfc.alignment(clicks, [])["paired"], 0)

    def test_run_entry_pulls_the_newest_and_handles_absent(self):
        commands = []

        def runner(cmd, **_):
            commands.append(cmd)
            Path(cmd[cmd.index("--destination") + 1]).write_bytes(b"x")
            return mock.Mock(returncode=0, stderr="")

        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            lister = lambda ident, d: ["Visualizer Recording 2026-11-18 at 14.05.32.mp4"]
            entry = {"task": "REC-016-T13", "dir": "tmp/QA011-REC016", "prefix": "Visualizer Recording",
                     "suffix": ".mp4", "notBefore": "2026-11-18 at 14.05.00", "checks": {}}
            r = self.rfc.run_entry(entry, "DEV", out, lister=lister, runner=runner,
                                   evaluator=lambda p, c: {"ok": True, "results": {}})
            self.assertTrue(r["ok"])
            self.assertIn("tmp/QA011-REC016/Visualizer Recording 2026-11-18 at 14.05.32.mp4", commands[0])
            self.assertIn("appDataContainer", commands[0])
            gone = self.rfc.run_entry({"dir": "Library/Application Support/RecordingLibrary", "name": "QA011 REC010 1.mp4",
                                       "absent": True}, "DEV", out, lister=lambda i, d: ["Other.mp4"])
            self.assertTrue(gone["ok"])
            missing = self.rfc.run_entry(dict(entry, notBefore="2026-11-18 at 15.00.00"), "DEV", out, lister=lister,
                                         runner=runner)
            self.assertFalse(missing["ok"])
            dry = self.rfc.run_entry(entry, "DEV", out, dry_run=True, lister=lister)
            self.assertIn("command", dry)

    def test_swift_helper_and_device_tests_name_the_same_identifiers(self):
        helper = (FIXTURES / "recording_inspect.swift").read_text()
        for command in ("\"info\"", "\"ocr\"", "\"grid\"", "\"luma\"", "\"envelope\"", "\"frame\""):
            self.assertIn(f"case {command}", helper)
        tests = (Path(__file__).resolve().parent.parent / "Apps" / "projectM-iOS" / "DeviceUITests")
        support = (tests / "RecordingCheckSupport.swift").read_text()
        self.assertIn(self.rfc.MARK.strip(), support)
        self.assertIn("yyyy-MM-dd 'at' HH.mm.ss", support, "the stamp the app puts in its file names")
        for name in ("B08RecordingDeviceTests.swift", "B08ShareDeviceTests.swift"):
            source = (tests / name).read_text()
            for key in re.findall(r'"(ocr[A-Za-z]+|centre|alignment|atoms|qa008|audioNonSilent|codec|image)"\s*:', source):
                self.assertIn(f'"{key}"', (Path(self.rfc.__file__)).read_text(), f"{name}: the check {key} exists")


if __name__ == "__main__":
    unittest.main(verbosity=2)
