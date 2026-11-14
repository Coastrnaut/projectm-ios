// PRE-016-T06: preset parameter overrides in the package (spec PRE-016-R2 to R8, R15, R17; research
// D2-D4; contract C1, C2). Allow-list and clamping, the text overlay against the engine's parsing
// rules, the original values, the document and the store (relaunch = a new store on the same folder).
// Each test runs in milliseconds.
import Foundation
import XCTest
@testable import PresetLibrary

final class PresetOverrideParameterTests: XCTestCase {
    func testAllowListMatchesWithoutRegardToCase() {
        XCTAssertEqual(PresetOverrideParameter.allCases.map(\.key),
                       ["zoom", "rot", "warp", "fDecay", "wave_r", "wave_g", "wave_b", "fGammaAdj"])
        XCTAssertEqual(PresetOverrideParameter(key: "FDECAY"), .decay)
        XCTAssertEqual(PresetOverrideParameter(key: "Zoom"), .zoom)
        XCTAssertNil(PresetOverrideParameter(key: "bInvert"))
        XCTAssertNil(PresetOverrideParameter(key: "per_frame_1"))
    }

    func testValuesAreClampedAndRoundedAndNonFiniteRefused() {
        XCTAssertEqual(PresetOverrideParameter.zoom.clamped(3), 1.2)
        XCTAssertEqual(PresetOverrideParameter.zoom.clamped(-5), 0.8)
        XCTAssertEqual(PresetOverrideParameter.decay.clamped(0.123), 0.9)
        XCTAssertEqual(PresetOverrideParameter.rotation.clamped(0.123456), 0.1235)
        XCTAssertEqual(PresetOverrideParameter.brightness.clamped(9), 3)
        XCTAssertNil(PresetOverrideParameter.warp.clamped(.nan))
        XCTAssertNil(PresetOverrideParameter.warp.clamped(.infinity))
    }

    func testMapRejectsUnknownNamesAndBadValuesWithoutChange() {
        var map = PresetOverrideMap()
        XCTAssertThrowsError(try map.set(1, for: "bInvert", preset: "a")) { error in
            XCTAssertEqual(error as? PresetOverrideError, .unknownParameter("bInvert"))
        }
        XCTAssertThrowsError(try map.set(.nan, for: "zoom", preset: "a")) { error in
            XCTAssertEqual(error as? PresetOverrideError, .invalidValue)
        }
        XCTAssertThrowsError(try map.set(1, for: "zoom", preset: "")) { error in
            XCTAssertEqual(error as? PresetOverrideError, .invalidPreset)
        }
        XCTAssertTrue(map.isEmpty)
        XCTAssertEqual(try map.set(7, for: "ZOOM", preset: "a"), 1.2)
        XCTAssertEqual(map.overrides(for: "a"), ["zoom": 1.2])
        XCTAssertTrue(map.remove("zoom", preset: "a"))
        XCTAssertTrue(map.isEmpty, "an empty set is removed")
    }
}

final class PresetTextOverlayTests: XCTestCase {
    private let fixture = """
    MILKDROP_PRESET_VERSION=201
    [preset00]
    fDecay=0.980000
    Zoom=1.000000
    rot=0.010000
    zoom=0.5
    per_frame_1=zoom = zoom + 0.01*bass;
    """

    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    func testOverlayRewritesTheFirstOccurrenceAndInsertsMissingKeysAfterTheHeader() {
        let source = Data(fixture.utf8)
        let result = PresetTextOverlay.apply(["zoom": 1.05, "fDecay": 0.95, "wave_r": 0.25], to: source)
        XCTAssertEqual(text(result), """
        MILKDROP_PRESET_VERSION=201
        [preset00]
        wave_r=0.25
        fDecay=0.95
        zoom=1.05
        rot=0.010000
        zoom=0.5
        per_frame_1=zoom = zoom + 0.01*bass;
        """)
        let read = PresetTextOverlay.originalValues(result)
        XCTAssertEqual(read[.zoom], 1.05)
        XCTAssertEqual(read[.decay], 0.95)
        XCTAssertEqual(read[.waveRed], 0.25)
        XCTAssertEqual(read[.rotation], 0.01)
    }

    func testNoOverridesGiveTheSameBytes() {
        let source = Data(fixture.utf8)
        XCTAssertEqual(PresetTextOverlay.apply([:], to: source), source)
        XCTAssertEqual(PresetTextOverlay.apply(["bInvert": 1, "zoom": .nan], to: source), source)
    }

    func testOriginalValuesFollowTheEngine() {
        let values = PresetTextOverlay.originalValues(Data(fixture.utf8))
        XCTAssertEqual(values[.zoom], 1, "first occurrence wins, key case-insensitive")
        XCTAssertEqual(values[.decay], 0.98)
        XCTAssertEqual(values[.warp], 1, "engine default when absent")
        XCTAssertEqual(values[.brightness], 2)
        let odd = PresetTextOverlay.originalValues(Data("warp= 1.5e-1junk\n rot=0.2\nzoom=abc\n".utf8))
        XCTAssertEqual(odd[.warp], 0.15, "stof-like prefix")
        XCTAssertEqual(odd[.rotation], 0, "a leading space means no key")
        XCTAssertEqual(odd[.zoom], 1, "unparsable keeps the default")
    }

    func testCRLFAndNonUTF8BytesAreKept() {
        var bytes: [UInt8] = Array("[preset00]\r\nzoom=1.0\r\n// caf".utf8)
        bytes.append(0xE9)   // Latin-1 é: not UTF-8
        bytes.append(contentsOf: Array("\r\n".utf8))
        let result = [UInt8](PresetTextOverlay.apply(["zoom": 0.9, "warp": 2], to: Data(bytes)))
        var expected: [UInt8] = Array("[preset00]\r\nwarp=2\r\nzoom=0.9\r\n// caf".utf8)
        expected.append(0xE9)
        expected.append(contentsOf: Array("\r\n".utf8))
        XCTAssertEqual(result, expected)
    }

    func testWithoutAHeaderLinesGoFirst() {
        let result = PresetTextOverlay.apply(["rot": -0.1], to: Data("zoom=1\n".utf8))
        XCTAssertEqual(String(decoding: result, as: UTF8.self), "rot=-0.1\nzoom=1\n")
        let headerOnly = PresetTextOverlay.apply(["rot": 0.1], to: Data("[preset00]".utf8))
        XCTAssertEqual(String(decoding: headerOnly, as: UTF8.self), "[preset00]\nrot=0.1\n")
    }

    func testValueText() {
        XCTAssertEqual(PresetTextOverlay.valueText(1.05), "1.05")
        XCTAssertEqual(PresetTextOverlay.valueText(1), "1")
        XCTAssertEqual(PresetTextOverlay.valueText(-0.00001), "0")
        XCTAssertEqual(PresetTextOverlay.valueText(0.98765), "0.9877")
    }

    /// R17: the overlay changes starting values only, so ACC-002's screen gives the same rules.
    func testFlashScreenIsUnchangedByAnOverlay() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "high-flash.milk", withExtension: nil, subdirectory: "FlashFixtures"))
        let source = try Data(contentsOf: url)
        let adjusted = PresetTextOverlay.apply(["fGammaAdj": 3, "fDecay": 1, "zoom": 1.2], to: source)
        XCTAssertNotEqual(adjusted, source)
        let before = PresetFlashRisk.rules(in: String(decoding: source, as: UTF8.self))
        XCTAssertFalse(before.isEmpty)
        XCTAssertEqual(PresetFlashRisk.rules(in: String(decoding: adjusted, as: UTF8.self)), before)
    }
}

final class PresetOverrideStoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL { directory.appendingPathComponent(PresetOverrideStore.fileName) }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PresetOverrideStoreTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("PresetCollections", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    private func put(_ text: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: fileURL)
    }

    func testOverridesSurviveARelaunchAndResetRemovesThem() throws {
        let store = PresetOverrideStore(directory: directory)
        XCTAssertEqual(try store.set(1.05, for: "zoom", preset: "included/a.milk"), 1.05)
        try store.set(0.95, for: "fDecay", preset: "included/a.milk")
        let relaunched = PresetOverrideStore(directory: directory)
        XCTAssertEqual(relaunched.overrides(for: "included/a.milk"), ["zoom": 1.05, "fDecay": 0.95])
        XCTAssertEqual(relaunched.loadNotice, .none)
        XCTAssertEqual(String(decoding: try Data(contentsOf: fileURL), as: UTF8.self),
                       #"{"overrides":{"included/a.milk":{"fDecay":0.95,"zoom":1.05}},"schemaVersion":1}"#)
        XCTAssertTrue(try relaunched.reset("included/a.milk"))
        XCTAssertFalse(try relaunched.reset("included/a.milk"))
        XCTAssertTrue(PresetOverrideStore(directory: directory).map.isEmpty)
    }

    func testRefusedChangeAndFailedSaveChangeNothing() throws {
        let failing = PresetOverrideStore(directory: directory) { (_: Data, _: URL) throws in throw CocoaError(.fileWriteNoPermission) }
        XCTAssertThrowsError(try failing.set(1.1, for: "zoom", preset: "a")) { error in
            XCTAssertEqual(error as? PresetOverrideError, .saveFailed)
        }
        XCTAssertTrue(failing.map.isEmpty)
        let store = PresetOverrideStore(directory: directory)
        XCTAssertThrowsError(try store.set(1, for: "bBrighten", preset: "a"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testDamagedEntriesAreDroppedAndOutOfRangeClamped() throws {
        try put(#"{"schemaVersion":1,"overrides":{"a":{"zoom":9,"bInvert":1},"b":"x","c":{}}}"#)
        let store = PresetOverrideStore(directory: directory)
        XCTAssertEqual(store.overrides(for: "a"), ["zoom": 1.2])
        XCTAssertEqual(store.loadNotice, .repaired(dropped: 3))
    }

    func testNewerFormatIsNeverWrittenAndUnreadableIsSetAside() throws {
        try put(#"{"schemaVersion":2,"overrides":{}}"#)
        let newer = PresetOverrideStore(directory: directory)
        XCTAssertEqual(newer.availability, .newerFormat(version: 2))
        XCTAssertThrowsError(try newer.set(1, for: "zoom", preset: "a")) { error in
            XCTAssertEqual(error as? PresetOverrideError, .newerFormat)
        }
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), #"{"schemaVersion":2,"overrides":{}}"#)

        try put("not json")
        let unreadable = PresetOverrideStore(directory: directory)
        XCTAssertEqual(unreadable.loadNotice, .unreadableSetAside)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(PresetOverrideStore.unreadableFileName).path))
        try unreadable.set(1.1, for: "zoom", preset: "a")
        XCTAssertEqual(PresetOverrideStore(directory: directory).overrides(for: "a"), ["zoom": 1.1])
    }
}
