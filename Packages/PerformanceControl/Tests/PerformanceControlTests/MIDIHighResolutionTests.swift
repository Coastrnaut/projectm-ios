// MIDIHighResolutionTests.swift — MIDI-005-T05, T09, T12: 14-bit control changes (specs/266-midi-005-14-bit-controls,
// contract H1-H4). The row's acceptance (S1): an MSB/LSB pair gives the expected 14-bit normalized value. Also several
// fine messages after one coarse, a new coarse resetting the fine part, the 7-bit fallback, learn detection, the
// stored segment and the profile round trip. Pure Swift, no clock: runs on the host and on Linux.
import Foundation
import ParameterGraph
import PerformanceControl
import XCTest

final class MIDIHighResolutionTests: XCTestCase {
    private static let group = ParameterGroup(id: "test.hires", displayName: "Hires")
    private static let unit: ParameterID = "test.hires.unit"        // 0…1
    private static let signed: ParameterID = "test.hires.signed"    // −12…48

    private static func registry() throws -> ParameterRegistry {
        try ParameterRegistry(descriptors: [
            ParameterDescriptor(id: unit, displayName: "Unit", group: group, unit: .normalized,
                                kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.5), modulation: .continuousDefault),
            ParameterDescriptor(id: signed, displayName: "Signed", group: group, unit: .normalized,
                                kind: .continuous(minimum: -12, maximum: 48, defaultValue: 0), modulation: .continuousDefault),
        ])
    }

    private static func cc(_ number: UInt8, _ value: UInt32, channel: UInt8 = 0) -> MIDIEvent {
        MIDIEvent(kind: .controlChange, channel: channel, number: number, value: value)
    }

    private static func key(_ number: UInt8, channel: UInt8 = 0) -> MIDIControlKey {
        MIDIControlKey(kind: .controlChange, channel: channel, number: number)
    }

    /// A list with `cc:0:<number>=test.hires.unit` and the given options.
    private static func list(_ number: UInt8 = 7, options: MIDIMappingOptions = MIDIMappingOptions(highResolution: true),
                             target: ParameterID = unit) -> MIDIBindingList {
        var list = MIDIBindingList()
        list.bind(key(number), to: target)
        list.setOptions(options, for: target)
        return list
    }

    // MARK: S1 — the acceptance

    func testMSBAndLSBPairsGiveTheExpected14BitNormalizedValue() throws {
        XCTAssertEqual(MIDIHighResolution.normalized(msb: 0x40, lsb: 0x00), 8192.0 / 16383.0)
        XCTAssertEqual(MIDIHighResolution.normalized(msb: 0x7F, lsb: 0x7F), 1.0)
        XCTAssertEqual(MIDIHighResolution.normalized(msb: 0, lsb: 0), 0.0)

        // Through a 14-bit mapping on CC 7 (fine CC 39) driving a 0…1 parameter with a fake source's events.
        let registry = try Self.registry()
        let list = Self.list()
        var tracker = MIDIHighResolutionTracker()
        let cases: [(msb: UInt32, lsb: UInt32, expected: Double)] = [(0x40, 0x00, 8192.0 / 16383.0), (0x7F, 0x7F, 1.0), (0, 0, 0)]
        for entry in cases {
            let batch: [MIDIEvent] = [Self.cc(7, entry.msb), Self.cc(39, entry.lsb)]
            let values = MIDIBindingValues.values(for: batch, bindings: list, registry: registry, tracker: &tracker)
            XCTAssertEqual(try XCTUnwrap(values[Self.unit]), entry.expected, accuracy: 1e-12, "\(entry)")
        }
    }

    // MARK: S2 — coarse then several fine; a new coarse resets the fine part (R2)

    func testSeveralFineMessagesRefineOneCoarseAndANewCoarseResetsTheFinePart() {
        var tracker = MIDIHighResolutionTracker()
        XCTAssertNil(tracker.fine(channel: 0, controller: 7, value: 5), "a fine message before any coarse one gives no value")
        XCTAssertEqual(tracker.coarse(channel: 0, controller: 7, value: 0x40), 64.0 / 127.0, "7-bit until a fine message")
        for lsb: UInt8 in [0x00, 0x01, 0x40, 0x7F] {
            XCTAssertEqual(tracker.fine(channel: 0, controller: 7, value: lsb), Double(0x40 * 128 + Int(lsb)) / 16383.0)
        }
        XCTAssertTrue(tracker.hasSeenFine(channel: 0, controller: 7))
        XCTAssertEqual(tracker.coarse(channel: 0, controller: 7, value: 0x41), Double(0x41 * 128) / 16383.0,
                       "a new coarse resets the fine part to 0")
        XCTAssertEqual(tracker.fine(channel: 0, controller: 7, value: 3), Double(0x41 * 128 + 3) / 16383.0)
        XCTAssertNil(tracker.fine(channel: 1, controller: 7, value: 3), "another channel has its own pair")
        XCTAssertNil(tracker.coarse(channel: 0, controller: 32, value: 3), "only controllers 0–31 are coarse")
    }

    // MARK: S3 — a 7-bit-only controller still reaches both ends (R3)

    func testACoarseOnlyControllerReachesBothEnds() throws {
        let registry = try Self.registry()
        let list = Self.list()
        var tracker = MIDIHighResolutionTracker()
        let low = MIDIBindingValues.values(for: [Self.cc(7, 0)], bindings: list, registry: registry, tracker: &tracker)
        let mid = MIDIBindingValues.values(for: [Self.cc(7, 64)], bindings: list, registry: registry, tracker: &tracker)
        let high = MIDIBindingValues.values(for: [Self.cc(7, 127)], bindings: list, registry: registry, tracker: &tracker)
        XCTAssertEqual(low[Self.unit], 0)
        XCTAssertEqual(try XCTUnwrap(mid[Self.unit]), 64.0 / 127.0, accuracy: 1e-12)
        XCTAssertEqual(high[Self.unit], 1)
        XCTAssertFalse(tracker.hasSeenFine(channel: 0, controller: 7))
    }

    // MARK: R4 — curve and Invert on the 14-bit value; R1 — fine on another channel ignored

    func testCurveInvertAndRangeApplyToThe14BitValue() throws {
        let registry = try Self.registry()
        let options = MIDIMappingOptions(curve: .easeIn(exponent: 2), inverted: true, highResolution: true)
        let list = Self.list(options: options, target: Self.signed)
        var tracker = MIDIHighResolutionTracker()
        let batch: [MIDIEvent] = [Self.cc(7, 0x20), Self.cc(39, 0x11), Self.cc(39, 0x7F, channel: 3)]
        let values = MIDIBindingValues.values(for: batch, bindings: list, registry: registry, tracker: &tracker)
        let position: Double = 1 - Double(0x20 * 128 + 0x11) / 16383.0
        let expected: Double = -12 + position * position * 60
        XCTAssertEqual(try XCTUnwrap(values[Self.signed]), expected, accuracy: 1e-9, "the channel-4 fine message is ignored")
        let ends = MIDIBindingValues.values(for: [Self.cc(7, 0x7F), Self.cc(39, 0x7F)], bindings: list, registry: registry,
                                            tracker: &tracker)
        XCTAssertEqual(ends[Self.signed], -12, "inverted: the top of the 14-bit range is the minimum, exactly")
    }

    func testSevenBitMappingsAndFlagsOnFineControllersAreUnchanged() throws {
        let registry = try Self.registry()
        var tracker = MIDIHighResolutionTracker()
        let plain = Self.list(options: .default)
        let values = MIDIBindingValues.values(for: [Self.cc(7, 0x40), Self.cc(39, 0x7F)], bindings: plain, registry: registry,
                                              tracker: &tracker)
        XCTAssertEqual(try XCTUnwrap(values[Self.unit]), 64.0 / 127.0, accuracy: 1e-12, "7-bit: CC 39 is not a fine part")
        let stateless = MIDIBindingValues.values(for: [Self.cc(7, 0x40)], bindings: plain, registry: registry)
        XCTAssertEqual(stateless, values, "the stateless overload gives the same 7-bit value")

        let fineFlagged = Self.list(40, options: MIDIMappingOptions(highResolution: true))
        XCTAssertFalse(try XCTUnwrap(fineFlagged.binding(forKey: Self.key(40))).isHighResolution, "only CC 0–31 can be 14-bit")
        let fineValues = MIDIBindingValues.values(for: [Self.cc(40, 127)], bindings: fineFlagged, registry: registry,
                                                  tracker: &tracker)
        XCTAssertEqual(fineValues[Self.unit], 1, "a flag on CC 40 is kept but reads as 7-bit")
        XCTAssertEqual(fineFlagged.storageLines, ["cc:0:40=test.hires.unit;hires=1"], "and is stored verbatim")
    }

    // MARK: R7, R10 — stored segment and summary

    func testTheFlagIsStoredAfterInvertAndBeforeUnknownSegments() throws {
        let line: String = "cc:0:7=test.hires.unit;curve=easeIn:2.0;invert=1;hires=1;min=0.2"
        let binding = try XCTUnwrap(MIDIControlBinding(storageLine: "cc:0:7=test.hires.unit;min=0.2;hires=1;invert=1;curve=easeIn:2.0"))
        XCTAssertTrue(binding.isHighResolution)
        XCTAssertEqual(binding.storageLine, line, "canonical order: curve, invert, hires, unknown")
        XCTAssertEqual(binding.options.summary, "Ease in, inverted, 14-bit")
        XCTAssertEqual(MIDIMappingOptions(highResolution: true).summary, "Linear, 14-bit")

        let old = try XCTUnwrap(MIDIControlBinding(storageLine: "cc:0:7=test.hires.unit"))
        XCTAssertFalse(old.options.highResolution, "a line without the flag is 7-bit")
        XCTAssertEqual(old.storageLine, "cc:0:7=test.hires.unit", "and stays byte-identical")
        XCTAssertFalse(try XCTUnwrap(MIDIControlBinding(storageLine: "cc:0:7=test.hires.unit;hires=0")).options.highResolution)
        XCTAssertEqual(try XCTUnwrap(MIDIControlBinding(storageLine: "cc:0:7=test.hires.unit;hires=1;hires=0")).storageLine,
                       "cc:0:7=test.hires.unit;hires=1", "the first flag wins")
    }

    // MARK: S4 — learn detection (R5)

    func testTheLearnWatchDetectsTheFineControllerWithinTheWindow() throws {
        let start: UInt64 = 1_000_000_000
        var watch = MIDIHighResolutionLearnWatch<ParameterID>()
        watch.arm(key: Self.key(7), target: Self.unit, now: start)
        XCTAssertNil(watch.detect(in: [Self.cc(39, 1, channel: 2), Self.cc(40, 1)], now: start), "other channel or controller")
        XCTAssertTrue(watch.isArmed)
        let found = try XCTUnwrap(watch.detect(in: [Self.cc(39, 1)], now: start + MIDIHighResolution.learnWindowNanoseconds))
        XCTAssertEqual(found.key, Self.key(7))
        XCTAssertEqual(found.target, Self.unit)
        XCTAssertFalse(watch.isArmed, "detection happens once")
        XCTAssertNil(watch.detect(in: [Self.cc(39, 1)], now: start + 1))

        watch.arm(key: Self.key(7), target: Self.unit, now: start)
        XCTAssertNil(watch.detect(in: [Self.cc(39, 1)], now: start + MIDIHighResolution.learnWindowNanoseconds + 1), "too late")
        XCTAssertFalse(watch.isArmed, "an expired watch disarms")

        watch.arm(key: Self.key(50), target: Self.unit, now: start)
        XCTAssertFalse(watch.isArmed, "controllers 32–119 have no fine part")
    }

    // MARK: S5 — profiles round-trip with and without the flag (R8)

    func testProfilesRoundTripLinesWithAndWithoutTheFlag() throws {
        let lines: [String] = ["cc:0:7=effect.bloom.intensity;hires=1", "cc:0:8=effect.bloom.radius",
                               "cc:1:1=effect.bloom.knee;curve=log:9.0;invert=1;hires=1"]
        let decoded = try MIDIProfileDocument.decode(MIDIProfileDocument.encode(name: "Fine faders", lines: lines))
        XCTAssertTrue(MIDIProfile.sameBytes(decoded.lines, lines), "byte for byte, in order")
        XCTAssertEqual(MIDIProfileReport(lines: lines).counts, [.controlChange: 3], "all three are controls")
        let flags: [Bool] = decoded.lines.compactMap { (line: String) -> Bool? in MIDIControlBinding(storageLine: line)?.isHighResolution }
        XCTAssertEqual(flags, [true, false, true])
    }
}
