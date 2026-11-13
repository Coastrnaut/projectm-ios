// ACC-002-T04: the flash risk screen's Swift twin gives the same rules as scripts/preset_flash_risk.py
// for every shared fixture (FlashFixtures/expected.json; the Python tests check the same file), and
// the known high-flash fixture is flagged before any scene loads (ACC-002-S1).
import XCTest
@testable import PresetLibrary

final class PresetFlashRiskTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "FlashFixtures"), name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func preset(_ perFrame: [String]) -> String {
        (["MILKDROP_PRESET_VERSION=201", "[preset00]"] + perFrame.enumerated().map { "per_frame_\($0.offset + 1)=\($0.element)" })
            .joined(separator: "\n")
    }

    func testEveryFixtureMatchesTheSharedExpectations() throws {
        let expected = try JSONDecoder().decode([String: [String]].self, from: Data(fixture("expected.json").utf8))
        XCTAssertEqual(expected.count, 12)
        for (name, rules) in expected {
            XCTAssertEqual(PresetFlashRisk.rules(in: try fixture(name)).map(\.rawValue), rules, name)
        }
    }

    func testTheKnownHighFlashFixtureIsFlaggedAndTheCalmOneIsNot() throws {
        XCTAssertEqual(PresetFlashRisk.rules(in: try fixture("high-flash.milk")), [.toggleDriven, .lumaFlicker])
        XCTAssertEqual(PresetFlashRisk.indexField(for: try fixture("high-flash.milk")), ["toggle-driven", "luma-flicker"])
        XCTAssertFalse(PresetFlashRisk.mayFlash(try fixture("calm.milk")))
        XCTAssertNil(PresetFlashRisk.indexField(for: try fixture("calm.milk")))
    }

    func testStatementsSplitAtTopLevelSemicolonsAcrossLines() {
        XCTAssertEqual(PresetFlashRisk.statements("a = if(b, 1; 2, 3); c = 4;; "), ["a = if(b, 1; 2, 3)", "c = 4"])
        XCTAssertEqual(PresetFlashRisk.perFrameCode("PER_FRAME_2=b=2;\nper_frame_1=a=1; // x\nper_frame_init_1=c=3"), "a=1;  b=2;")
    }

    func testAudioIsFollowedThroughVariablesButFlickerIsNot() {
        XCTAssertEqual(PresetFlashRisk.rules(in: preset(["x = bass_att*2;", "y = x + 1;", "darken = above(y, 3);"])), [.toggleDriven])
        XCTAssertEqual(PresetFlashRisk.rules(in: preset(["x = rand(2);", "gamma = 1 + x;"])), [])
        XCTAssertEqual(PresetFlashRisk.rules(in: preset(["gamma = 1 + 0.5*sin(frame);"])), [.lumaFlicker])
        XCTAssertEqual(PresetFlashRisk.rules(in: preset(["gamma = 1 + 0.5*sin(time*2);"])), [])
        XCTAssertEqual(PresetFlashRisk.rules(in: preset(["echo_alpha = fmod(frame, 4)*0.2;"])), [.lumaFlicker])
        XCTAssertEqual(PresetFlashRisk.rules(in: preset(["decay = decay - 0.1*equal(frame%4,0);"])), [.lumaFlicker])
        XCTAssertEqual(PresetFlashRisk.rules(in: preset(["decay = decay - 0.01*equal(frame%4,0);"])), [])
        XCTAssertEqual(PresetFlashRisk.rules(in: preset(["invert = bnot(invert);"])), [.toggleFlip])
    }

    /// ACC-002-T10 (R4): imported presets are screened by the same rules when they join the
    /// library; the checked-in high-flash fixture itself imports and is flagged, the calm one is not.
    func testImportedPresetsAreScreened() async throws {
        let folder = try UserPresetFixtures.tempDirectory(self)
        let directory = try UserPresetFixtures.tempDirectory(self).appendingPathComponent("UserPresets")
        let library = UserPresetLibrary(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        _ = await library.load()
        await library.setTrial(FakeTrial())
        var ids: [String: String] = [:]
        for name in ["high-flash.milk", "calm.milk"] {
            let source = try UserPresetFixtures.write(try fixture(name), named: "Fixture - \(name)", in: folder)
            guard case .added(let preset) = await library.importFile(at: source) else { return XCTFail("\(name) was not added") }
            ids[name] = preset.id
        }
        let risk = await library.flashRisk()
        XCTAssertEqual(risk, [try XCTUnwrap(ids["high-flash.milk"]): ["toggle-driven", "luma-flicker"]])
        let snapshot = await library.snapshot
        let entries = snapshot.playable.map { $0.indexed(flash: risk[$0.id]) }
        XCTAssertEqual(entries.filter(\.mayFlash).map(\.id), [ids["high-flash.milk"]])
        let again = await library.flashRisk()
        XCTAssertEqual(again, risk, "the cached result is the same")
    }

    func testLiteralsReadLikePython() {
        XCTAssertEqual(PresetFlashRisk.number("5."), 5)
        XCTAssertEqual(PresetFlashRisk.number(".5"), 0.5)
        XCTAssertEqual(PresetFlashRisk.rate("q2*time*30", "time"), 30)
        XCTAssertEqual(PresetFlashRisk.rate("frame", "frame"), 1)
        XCTAssertNil(PresetFlashRisk.rate("time", "frame"))
    }
}
