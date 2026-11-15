// MIDIFeedbackTests.swift — MIDI-009-T06, T10, T13: MIDI feedback (specs/269-midi-009-midi-feedback, contract F1-F5).
// The acceptance: a connected mock output receives bounded state updates without feedback loops. Manual clock (no wall
// time), representative cases (owner rule 7); the loopback runs 3000 simulated 30 Hz ticks in memory.
import Foundation
import ParameterGraph
import PerformanceControl
import XCTest

final class MIDIFeedbackTests: XCTestCase {
    private static let group = ParameterGroup(id: "test.fb", displayName: "Feedback")
    private static let unit: ParameterID = "test.fb.unit"        // 0…1
    private static let signed: ParameterID = "test.fb.signed"    // −12…48
    private static let tick: UInt64 = 33_333_334                 // one 30 Hz tick

    private static func registry(extra: Int = 0) throws -> ParameterRegistry {
        var descriptors: [ParameterDescriptor] = [
            ParameterDescriptor(id: unit, displayName: "Unit", group: group, unit: .normalized,
                                kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.5), modulation: .continuousDefault),
            ParameterDescriptor(id: signed, displayName: "Signed", group: group, unit: .normalized,
                                kind: .continuous(minimum: -12, maximum: 48, defaultValue: 0), modulation: .continuousDefault),
        ]
        for index in 0..<extra {
            descriptors.append(ParameterDescriptor(id: Self.extraID(index), displayName: "Extra " + String(index), group: group,
                                                   unit: .normalized, kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0),
                                                   modulation: .continuousDefault))
        }
        return try ParameterRegistry(descriptors: descriptors)
    }

    private static func extraID(_ index: Int) -> ParameterID { ParameterID("test.fb.extra" + String(index)) }

    private static func key(_ number: UInt8, channel: UInt8 = 0) -> MIDIControlKey {
        MIDIControlKey(kind: .controlChange, channel: channel, number: number)
    }

    private static func list(_ lines: [String], registry: ParameterRegistry) -> MIDIBindingList {
        let allowed: Set<ParameterID> = Set(registry.descriptors.map { (descriptor: ParameterDescriptor) -> ParameterID in descriptor.id })
        return MIDIBindingList(storageLines: lines, allowedTargets: allowed)
    }

    private static func engine(_ lines: [String], registry: ParameterRegistry) -> MIDIFeedbackEngine {
        var engine = MIDIFeedbackEngine()
        engine.configure(bindings: list(lines, registry: registry))
        return engine
    }

    private static func cc(_ message: MIDIFeedbackMessage, at time: UInt64) -> MIDIEvent {
        MIDIEvent(kind: .controlChange, channel: message.channel, number: message.controller, value: UInt32(message.value),
                  timestamp: time)
    }

    // MARK: US1 — one change, one correct message (S1, S5)

    func testOneParameterChangeSendsExactlyOneCorrectControlChange() throws {
        let registry = try Self.registry()
        var engine = Self.engine(["cc:0:7=test.fb.unit;fb=1"], registry: registry)
        var now: UInt64 = 1_000_000_000
        _ = engine.tick(values: [Self.unit: 0], registry: registry, now: now)   // first state (R11)
        now += Self.tick
        let sent: [MIDIFeedbackMessage] = engine.tick(values: [Self.unit: 100.0 / 127.0], registry: registry, now: now)
        XCTAssertEqual(sent, [MIDIFeedbackMessage(channel: 0, controller: 7, value: 100)])
        now += Self.tick
        XCTAssertEqual(engine.tick(values: [Self.unit: 100.0 / 127.0], registry: registry, now: now), [], "no change, nothing sent")
    }

    func testFirstTickSendsTheCurrentStateOnceAndAMappingWithoutFeedbackSendsNothing() throws {
        let registry = try Self.registry()
        var engine = Self.engine(["cc:0:7=test.fb.unit;fb=1", "cc:0:8=test.fb.signed"], registry: registry)
        let first = engine.tick(values: [Self.unit: 0.75, Self.signed: 10], registry: registry, now: 1)
        XCTAssertEqual(first, [MIDIFeedbackMessage(channel: 0, controller: 7, value: 95)], "only the feedback mapping (0.75 × 127 = 95.25)")
        XCTAssertEqual(engine.tick(values: [Self.unit: 0.75, Self.signed: 40], registry: registry, now: 1 + Self.tick), [])
        var none = Self.engine(["cc:0:7=test.fb.unit"], registry: registry)
        XCTAssertFalse(none.isActive)
        XCTAssertEqual(none.tick(values: [Self.unit: 1], registry: registry, now: 1), [])
        XCTAssertEqual(engine.tick(values: [:], registry: registry, now: 1 + 2 * Self.tick), [], "no value (no native visual): nothing")
    }

    func testInvertedCurvedMappingSendsTheSwappedEndsAndOutOfRangeValuesTheNearestEnd() throws {
        let registry = try Self.registry()
        let binding = try XCTUnwrap(MIDIControlBinding(storageLine: "cc:0:7=test.fb.signed;curve=easeIn:2.0;invert=1;fb=1"))
        let descriptor = try XCTUnwrap(registry.descriptor(for: Self.signed))
        XCTAssertEqual(MIDIFeedbackQuantizer.code(for: -12, binding: binding, descriptor: descriptor), 127, "minimum → 127")
        XCTAssertEqual(MIDIFeedbackQuantizer.code(for: 48, binding: binding, descriptor: descriptor), 0, "maximum → 0")
        XCTAssertEqual(MIDIFeedbackQuantizer.code(for: -500, binding: binding, descriptor: descriptor), 127, "below the range")
        XCTAssertEqual(MIDIFeedbackQuantizer.code(for: 900, binding: binding, descriptor: descriptor), 0, "above the range")
        XCTAssertNil(MIDIFeedbackQuantizer.code(for: .nan, binding: binding, descriptor: descriptor))
    }

    func testEveryControllerValueRoundTripsForEachPresetCurveInvertedOrNot() throws {
        let registry = try Self.registry()
        let descriptor = try XCTUnwrap(registry.descriptor(for: Self.signed))
        for preset in MIDICurvePreset.allCases {
            for inverted in [false, true] {
                let options = MIDIMappingOptions(curve: preset.curve, inverted: inverted)
                let seven = MIDIControlBinding(key: Self.key(7), target: Self.signed, options: options)
                for code in UInt16(0)...127 {
                    let value = try XCTUnwrap(MIDIFeedbackQuantizer.value(code: code, binding: seven, descriptor: descriptor))
                    XCTAssertEqual(MIDIFeedbackQuantizer.code(for: value, binding: seven, descriptor: descriptor), code,
                                   "\(preset) inverted \(inverted) code \(code)")
                }
                var fine = options
                fine.highResolution = true
                let fourteen = MIDIControlBinding(key: Self.key(7), target: Self.signed, options: fine)
                for code in stride(from: UInt16(0), through: 16_383, by: 61) {
                    let value = try XCTUnwrap(MIDIFeedbackQuantizer.value(code: code, binding: fourteen, descriptor: descriptor))
                    XCTAssertEqual(MIDIFeedbackQuantizer.code(for: value, binding: fourteen, descriptor: descriptor), code)
                }
            }
        }
    }

    func testAFlatCurvePartKeepsTheControllersCodeOrTakesTheLowest() throws {
        let registry = try Self.registry()
        let descriptor = try XCTUnwrap(registry.descriptor(for: Self.unit))
        let flat = MappingCurve.piecewise([CurvePoint(x: 0.25, y: 0.6), CurvePoint(x: 0.75, y: 0.6)])
        let binding = MIDIControlBinding(key: Self.key(7), target: Self.unit, options: MIDIMappingOptions(curve: flat))
        let value = try XCTUnwrap(MIDIFeedbackQuantizer.value(code: 64, binding: binding, descriptor: descriptor))
        XCTAssertEqual(MIDIFeedbackQuantizer.code(for: value, binding: binding, descriptor: descriptor, preferring: 64), 64)
        let lowest = try XCTUnwrap(MIDIFeedbackQuantizer.code(for: value, binding: binding, descriptor: descriptor))
        XCTAssertEqual(MIDIFeedbackQuantizer.value(code: lowest, binding: binding, descriptor: descriptor), value)
        XCTAssertNotEqual(MIDIFeedbackQuantizer.value(code: lowest - 1, binding: binding, descriptor: descriptor), value, "lowest of the run")
    }

    func testA14BitMappingSendsCoarseThenFine() throws {
        let registry = try Self.registry()
        var engine = Self.engine(["cc:2:7=test.fb.unit;hires=1;fb=1"], registry: registry)
        let sent = engine.tick(values: [Self.unit: 8192.0 / 16_383.0], registry: registry, now: 1)
        XCTAssertEqual(sent, [MIDIFeedbackMessage(channel: 2, controller: 7, value: 64), MIDIFeedbackMessage(channel: 2, controller: 39, value: 0)])
        let later = engine.tick(values: [Self.unit: 8193.0 / 16_383.0], registry: registry, now: 1 + Self.tick)
        XCTAssertEqual(later, [MIDIFeedbackMessage(channel: 2, controller: 7, value: 64), MIDIFeedbackMessage(channel: 2, controller: 39, value: 1)])
    }

    // MARK: US2 — bounded, no loops (S2, S3, S4)

    func testAThousandRapidChangesStayWithinTheRateBoundAndTheFinalValueArrives() throws {
        let registry = try Self.registry()
        var engine = Self.engine(["cc:0:7=test.fb.unit;fb=1"], registry: registry)
        var now: UInt64 = 5_000_000_000
        var sent: [(time: UInt64, message: MIDIFeedbackMessage)] = []
        for index in 0..<1000 {   // one change per millisecond for one second
            let value: Double = Double((index * 37) % 1000) / 999.0
            for message in engine.tick(values: [Self.unit: value], registry: registry, now: now) { sent.append((now, message)) }
            now += 1_000_000
        }
        let final: Double = 0.123
        for _ in 0..<10 {   // the value settles; ticks continue at 30 Hz
            for message in engine.tick(values: [Self.unit: final], registry: registry, now: now) { sent.append((now, message)) }
            now += Self.tick
        }
        let during = sent.filter { (entry: (time: UInt64, message: MIDIFeedbackMessage)) -> Bool in entry.time < 6_000_000_000 }
        XCTAssertLessThanOrEqual(during.count, 31, "at most 30 per second plus the first")
        XCTAssertGreaterThanOrEqual(during.count, 25, "updates keep flowing at the bound")
        for (previous, next) in zip(sent, sent.dropFirst()) {
            XCTAssertGreaterThanOrEqual(next.time - previous.time, MIDIFeedbackLimits().minimumInterval)
        }
        XCTAssertEqual(sent.last?.message.value, UInt8((final * 127).rounded()), "the final value is delivered")
    }

    func testAValueAppliedFromTheControllerIsNotEchoed() throws {
        let registry = try Self.registry()
        var engine = Self.engine(["cc:0:7=test.fb.unit;fb=1", "cc:0:2=test.fb.signed;hires=1;fb=1"], registry: registry)
        var tracker = MIDIHighResolutionTracker()
        var now: UInt64 = 1_000_000_000
        _ = engine.tick(values: [Self.unit: 0, Self.signed: -12], registry: registry, now: now)
        let bindings = Self.list(["cc:0:7=test.fb.unit;fb=1", "cc:0:2=test.fb.signed;hires=1;fb=1"], registry: registry)
        var base: [ParameterID: Double] = [Self.unit: 0, Self.signed: -12]
        for step in 0..<60 {   // the user turns both knobs for two seconds
            now += Self.tick
            let events: [MIDIEvent] = [MIDIEvent(kind: .controlChange, number: 7, value: UInt32(step * 2)),
                                       MIDIEvent(kind: .controlChange, number: 2, value: UInt32(step)),
                                       MIDIEvent(kind: .controlChange, number: 34, value: UInt32(127 - step))]
            let applied = MIDIBindingValues.values(for: engine.filterEchoes(events, now: now), bindings: bindings,
                                                   registry: registry, tracker: &tracker)
            base.merge(applied) { (_: Double, newer: Double) -> Double in newer }
            engine.incomingApplied(applied, registry: registry, now: now)
            XCTAssertEqual(engine.tick(values: base, registry: registry, now: now), [], "step \(step): no echo")
        }
        for _ in 0..<30 {   // after the echo window: still nothing (the controller shows the value)
            now += Self.tick
            XCTAssertEqual(engine.tick(values: base, registry: registry, now: now), [])
        }
    }

    /// The output wired straight back into the input, through the same filter and value path as the app.
    private struct Loopback {
        var engine: MIDIFeedbackEngine
        var tracker = MIDIHighResolutionTracker()
        let bindings: MIDIBindingList
        let registry: ParameterRegistry
        var base: [ParameterID: Double]
        var now: UInt64 = 1_000_000_000
        var inFlight: [[MIDIEvent]] = []
        let delayTicks: Int

        mutating func step() -> Int {
            now += MIDIFeedbackTests.tick
            let arriving: [MIDIEvent] = inFlight.count > delayTicks ? inFlight.removeFirst() : []
            let applied = MIDIBindingValues.values(for: engine.filterEchoes(arriving, now: now), bindings: bindings,
                                                   registry: registry, tracker: &tracker)
            base.merge(applied) { (_: Double, newer: Double) -> Double in newer }
            engine.incomingApplied(applied, registry: registry, now: now)
            let sent = engine.tick(values: base, registry: registry, now: now)
            let time: UInt64 = now
            inFlight.append(sent.map { (message: MIDIFeedbackMessage) -> MIDIEvent in MIDIFeedbackTests.cc(message, at: time) })
            return sent.count
        }
    }

    func testALoopbackSettlesAfterOneMessagePerChangeAndNeverOscillates() throws {
        let registry = try Self.registry()
        let lines: [String] = ["cc:0:7=test.fb.unit;curve=log:9.0;fb=1", "cc:0:3=test.fb.signed;hires=1;invert=1;fb=1"]
        for delay in [0, 5] {   // the echo arrives on the next tick, or after the 100 ms window
            var loop = Loopback(engine: Self.engine(lines, registry: registry), bindings: Self.list(lines, registry: registry),
                                registry: registry, base: [Self.unit: 0.3, Self.signed: 7.25], delayTicks: delay)
            var total: Int = loop.step()
            XCTAssertEqual(total, 3, "first state: one 7-bit and one 14-bit update")
            for change in 0..<10 {
                loop.base[Self.unit] = Double(change) / 10.0 + 0.05
                loop.base[Self.signed] = Double(change) * 4.1 - 3
                var sentForChange: Int = 0
                for _ in 0..<20 { sentForChange += loop.step() }
                XCTAssertLessThanOrEqual(sentForChange, 3, "delay \(delay), change \(change): one update per control")
                total += sentForChange
            }
            var after: Int = 0
            for _ in 0..<3000 { after += loop.step() }
            XCTAssertEqual(after, 0, "delay \(delay): silent over 3000 ticks, no oscillation")
            XCTAssertLessThanOrEqual(total, 33)
        }
    }

    func testEchoedBytesAreDroppedOnceAndOnlyWithinTheWindow() throws {
        let registry = try Self.registry()
        var engine = Self.engine(["cc:0:7=test.fb.unit;fb=1"], registry: registry)
        let sent = engine.tick(values: [Self.unit: 1], registry: registry, now: 1_000)
        XCTAssertEqual(sent, [MIDIFeedbackMessage(channel: 0, controller: 7, value: 127)])
        let echo = MIDIEvent(kind: .controlChange, number: 7, value: 127)
        let other = MIDIEvent(kind: .controlChange, number: 7, value: 3)
        XCTAssertEqual(engine.filterEchoes([echo, other, echo], now: 2_000), [other, echo], "dropped once, others kept")
        _ = engine.tick(values: [Self.unit: 0], registry: registry, now: 1_000 + Self.tick)
        XCTAssertEqual(engine.filterEchoes([MIDIEvent(kind: .controlChange, number: 7, value: 0)], now: 1_000 + Self.tick + 200_000_000).count, 1,
                       "after 100 ms a matching byte is the user's")
    }

    func testThePerTickCapServesControlsRoundRobin() throws {
        let registry = try Self.registry(extra: 20)
        let lines: [String] = (0..<20).map { (index: Int) -> String in "cc:0:" + String(index + 64) + "=test.fb.extra" + String(index) + ";fb=1" }
        var engine = Self.engine(lines, registry: registry)
        var values: [ParameterID: Double] = [:]
        for index in 0..<20 { values[Self.extraID(index)] = 1 }
        let first = engine.tick(values: values, registry: registry, now: 1)
        XCTAssertEqual(first.count, MIDIFeedbackLimits().maxMessagesPerTick)
        let second = engine.tick(values: values, registry: registry, now: 1 + Self.tick)
        XCTAssertEqual(Set(second.map(\.controller)), Set((80..<84).map { (n: Int) -> UInt8 in UInt8(n) }), "the four left over")
        XCTAssertEqual(engine.tick(values: values, registry: registry, now: 1 + 2 * Self.tick), [])
        XCTAssertEqual(engine.sentCount, 20)
    }

    func testPanicAbsorbsPendingAndResyncSendsTheStateAgain() throws {
        let registry = try Self.registry()
        var engine = Self.engine(["cc:0:7=test.fb.unit;fb=1"], registry: registry)
        _ = engine.tick(values: [Self.unit: 0], registry: registry, now: 1)
        engine.absorb([Self.unit: 1], registry: registry)
        XCTAssertEqual(engine.tick(values: [Self.unit: 1], registry: registry, now: 1 + Self.tick), [], "panic: nothing sent")
        engine.resync()
        XCTAssertEqual(engine.tick(values: [Self.unit: 1], registry: registry, now: 1 + 2 * Self.tick).count, 1, "a new destination gets the state")
    }

    // MARK: Routing and the wire format (R9)

    func testFeedbackGoesOnlyToDestinationsPairedWithListenedInputs() {
        let list = MIDIEndpointList.make(from: [
            MIDIEndpointRecord(uniqueID: 1, direction: .source, displayName: "Knobs", deviceName: "Knobs"),
            MIDIEndpointRecord(uniqueID: 2, direction: .destination, displayName: "Knobs", deviceName: "Knobs"),
            MIDIEndpointRecord(uniqueID: 3, direction: .destination, displayName: "Synth", deviceName: "Synth"),
            MIDIEndpointRecord(uniqueID: 4, direction: .destination, displayName: "Knobs 2", deviceName: "Knobs", isOffline: true),
            MIDIEndpointRecord(uniqueID: 5, direction: .destination, displayName: "Knobs net", deviceName: "Knobs", transport: .network),
            MIDIEndpointRecord(uniqueID: 6, direction: .source, displayName: "Bus", isVirtual: true),
            MIDIEndpointRecord(uniqueID: 7, direction: .destination, displayName: "Bus", isVirtual: true),
            MIDIEndpointRecord(uniqueID: 8, direction: .destination, displayName: "Other bus", isVirtual: true),
        ])
        XCTAssertEqual(MIDIFeedbackRouting.destinations(in: list), [.unique(2), .unique(7)])
        XCTAssertEqual(MIDIFeedbackRouting.destinations(in: .empty), [])
    }

    func testUMPWordsAreMIDI1ControlChangesOnGroup0() {
        XCTAssertEqual(MIDIFeedbackUMP.word(MIDIFeedbackMessage(channel: 2, controller: 7, value: 100)), 0x20B2_0764)
        let output = RecordingMIDIFeedbackOutput()
        output.send([MIDIFeedbackMessage(channel: 0, controller: 1, value: 2)], to: [])
        XCTAssertTrue(output.sends.isEmpty, "no destination, nothing recorded")
    }

    // MARK: US3 — the option (S6)

    func testTheFlagIsStoredAfterHiresAndRoundTripsThroughProfiles() throws {
        let line = "cc:0:7=test.fb.unit;curve=easeIn:2.0;invert=1;hires=1;fb=1;zz=9"
        let binding = try XCTUnwrap(MIDIControlBinding(storageLine: "cc:0:7=test.fb.unit;zz=9;fb=1;hires=1;invert=1;curve=easeIn:2.0"))
        XCTAssertEqual(binding.storageLine, line)
        XCTAssertTrue(binding.options.feedback)
        XCTAssertEqual(MIDIMappingOptions(feedback: true).summary, "Linear, feedback")
        XCTAssertEqual(binding.options.summary, "Ease in, inverted, 14-bit, feedback")
        XCTAssertEqual(MIDIControlBinding(storageLine: "cc:0:7=test.fb.unit")?.storageLine, "cc:0:7=test.fb.unit", "unchanged without it")
        XCTAssertEqual(MIDIControlBinding(storageLine: "cc:0:7=test.fb.unit;fb=0")?.options.feedback, false)
        let lines: [String] = [line, "cc:0:8=test.fb.signed;fb=1", "cc:0:9=test.fb.other"]
        let decoded = try MIDIProfileDocument.decode(MIDIProfileDocument.encode(name: "Feedback", lines: lines))
        XCTAssertTrue(MIDIProfile.sameBytes(decoded.lines, lines), "byte for byte, in order")
        XCTAssertEqual(MIDIProfileReport(lines: lines).counts, [.controlChange: 3])
    }
}
