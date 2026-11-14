// MIDILearnTests.swift — MIDI-003-T05: learn session, eligibility, mapping list policy, stored form and
// values (MIDI-003-R2-R5, R7, R9, R16; S1-S5 in the pure model). Deterministic: every time is an argument.
import ParameterGraph
import PerformanceControl
import XCTest

final class MIDILearnTests: XCTestCase {
    private static let intensity: ParameterID = "test.glow.intensity"
    private static let radius: ParameterID = "test.glow.radius"
    private static let enabled: ParameterID = "test.glow.enabled"
    private static let locked: ParameterID = "test.glow.locked"
    private static let group = ParameterGroup(id: "test.glow", displayName: "Glow")

    private static func registry() throws -> ParameterRegistry {
        try ParameterRegistry(descriptors: [
            ParameterDescriptor(id: intensity, displayName: "Intensity", group: group, unit: .normalized,
                                kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.5), modulation: .continuousDefault),
            ParameterDescriptor(id: radius, displayName: "Radius", group: group, unit: .fractionOfOutput,
                                kind: .continuous(minimum: 0.005, maximum: 0.06, defaultValue: 0.02), modulation: .continuousDefault),
            ParameterDescriptor(id: enabled, displayName: "Glow", group: group, unit: .none,
                                kind: .boolean(defaultValue: false), modulation: .discreteManual),
            ParameterDescriptor(id: locked, displayName: "Locked", group: group, unit: .normalized,
                                kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0), modulation: .none),
        ])
    }

    private static func cc(_ number: UInt8, channel: UInt8 = 0, value: UInt32 = 100) -> MIDIEvent {
        MIDIEvent(kind: .controlChange, channel: channel, number: number, value: value)
    }

    private static func key(_ number: UInt8, channel: UInt8 = 0) -> MIDIControlKey {
        MIDIControlKey(kind: .controlChange, channel: channel, number: number)
    }

    // MARK: Session (S1-S3)

    func testOneControlChangeBindsAndEndsLearningAndASecondBindsNothing() {
        var session = MIDILearnSession<ParameterID>()
        var list = MIDIBindingList()
        session.start(target: Self.intensity, now: 1_000)
        XCTAssertTrue(session.isLearning)
        let outcome = session.handle([Self.cc(7)], now: 2_000)
        XCTAssertEqual(outcome, .bound(key: Self.key(7), target: Self.intensity, eventIndex: 0))
        if case let .bound(key, target, _)? = outcome { list.bind(key, to: target) }
        XCTAssertFalse(session.isLearning)
        XCTAssertEqual(list.bindings, [MIDIControlBinding(key: Self.key(7), target: Self.intensity)])
        XCTAssertNil(session.handle([Self.cc(8)], now: 3_000), "a second control change creates nothing")
        XCTAssertEqual(list.count, 1)
    }

    func testABatchOfSeveralControlChangesBindsOnlyTheFirst() {
        var session = MIDILearnSession<ParameterID>()
        session.start(target: Self.radius, now: 0)
        let batch: [MIDIEvent] = [MIDIEvent(kind: .noteOn, number: 60, value: 90), Self.cc(20), Self.cc(21), Self.cc(22, channel: 3)]
        XCTAssertEqual(session.handle(batch, now: 1), .bound(key: Self.key(20), target: Self.radius, eventIndex: 1))
        XCTAssertNil(session.handle(batch, now: 2))
    }

    func testIneligibleMessagesNeverBind() {
        var session = MIDILearnSession<ParameterID>()
        session.start(target: Self.intensity, now: 0)
        var ineligible: [MIDIEvent] = [
            MIDIEvent(kind: .noteOn, number: 60, value: 100), MIDIEvent(kind: .noteOff, number: 60),
            MIDIEvent(kind: .pitchBend, value: 8192), MIDIEvent(kind: .channelPressure, value: 3),
            MIDIEvent(kind: .polyPressure, number: 60, value: 3), MIDIEvent(kind: .programChange, number: 5),
            MIDIEvent(kind: .systemExclusive, value: 12), MIDIEvent(kind: .clock), MIDIEvent(kind: .activeSensing),
            MIDIEvent(kind: .start), MIDIEvent(kind: .stop), MIDIEvent(kind: .songPosition, value: 4),
        ]
        for controller: UInt8 in 120...127 { ineligible.append(Self.cc(controller)) }
        XCTAssertNil(session.handle(ineligible, now: 1))
        XCTAssertTrue(session.isLearning)
        XCTAssertTrue(MIDILearnEligibility.isEligible(Self.cc(0)))
        XCTAssertTrue(MIDILearnEligibility.isEligible(Self.cc(119)))
        XCTAssertFalse(MIDILearnEligibility.isEligible(Self.cc(120)))
    }

    func testCancelAndTimeout() {
        var session = MIDILearnSession<ParameterID>()
        session.start(target: Self.intensity, now: 100)
        XCTAssertEqual(session.cancel(), .cancelled(target: Self.intensity))
        XCTAssertNil(session.cancel())

        session.start(target: Self.intensity, now: 100)
        let deadline: UInt64 = 100 + MIDILearnSession<ParameterID>.timeoutNanoseconds
        XCTAssertNil(session.expire(now: deadline - 1))
        XCTAssertEqual(session.expire(now: deadline), .timedOut(target: Self.intensity))

        session.start(target: Self.radius, now: 0)
        XCTAssertEqual(session.handle([Self.cc(7)], now: deadline), .timedOut(target: Self.radius),
                       "a late batch times out instead of binding")
        XCTAssertFalse(session.isLearning)
    }

    func testANewRequestReplacesTheTargetAndRestartsTheDeadline() {
        var session = MIDILearnSession<ParameterID>()
        session.start(target: Self.intensity, now: 0)
        session.start(target: Self.radius, now: 10_000_000_000)
        XCTAssertEqual(session.target, Self.radius)
        XCTAssertNil(session.expire(now: 35_000_000_000))
    }

    // MARK: Rebinding policy (S4)

    func testMoveReplaceBothAndFull() {
        var list = MIDIBindingList()
        XCTAssertEqual(list.bind(Self.key(7), to: Self.intensity), .added)
        XCTAssertEqual(list.bind(Self.key(7), to: Self.radius), .moved(from: Self.intensity))
        XCTAssertNil(list.binding(for: Self.intensity))
        XCTAssertEqual(list.bind(Self.key(9), to: Self.radius), .replaced(previous: Self.key(7)))
        XCTAssertNil(list.target(for: Self.key(7)))
        XCTAssertEqual(list.bind(Self.key(1), to: Self.intensity), .added)
        XCTAssertEqual(list.bind(Self.key(9), to: Self.intensity), .movedAndReplaced(from: Self.radius, previous: Self.key(1)))
        XCTAssertEqual(list.bindings, [MIDIControlBinding(key: Self.key(9), target: Self.intensity)])
        XCTAssertEqual(list.bind(Self.key(9), to: Self.intensity), .added, "binding an existing pair changes nothing")
        XCTAssertEqual(list.count, 1)

        var full = MIDIBindingList()
        for index in 0..<MIDIBindingList.capacity {
            let number: UInt8 = UInt8(index % 100)
            let channel: UInt8 = UInt8(index / 100)
            full.bind(Self.key(number, channel: channel), to: ParameterID("test.p" + String(index)))
        }
        XCTAssertEqual(full.count, MIDIBindingList.capacity)
        XCTAssertEqual(full.bind(Self.key(110), to: "test.extra"), .full)
        XCTAssertEqual(full.bind(Self.key(110), to: "test.p0"), .replaced(previous: Self.key(0)), "a replace still fits")
    }

    func testEachControlAndParameterAppearsOnce() {
        var list = MIDIBindingList()
        let pairs: [(UInt8, ParameterID)] = [(1, Self.intensity), (2, Self.radius), (1, Self.radius), (3, Self.intensity), (2, Self.intensity)]
        for (number, target) in pairs { list.bind(Self.key(number), to: target) }
        let keys: [MIDIControlKey] = list.bindings.map { (binding: MIDIControlBinding) -> MIDIControlKey in binding.key }
        let targets: [ParameterID] = list.bindings.map { (binding: MIDIControlBinding) -> ParameterID in binding.target }
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertEqual(Set(targets).count, targets.count)
    }

    // MARK: Stored form (R4, R9, R16)

    func testStoredLinesRoundTripAndHoldOnlyKindChannelNumberAndParameter() {
        var list = MIDIBindingList()
        list.bind(Self.key(7), to: Self.intensity)
        list.bind(Self.key(119, channel: 15), to: Self.radius)
        XCTAssertEqual(list.storageLines, ["cc:0:7=test.glow.intensity", "cc:15:119=test.glow.radius"])
        let restored = MIDIBindingList(storageLines: list.storageLines, allowedTargets: [Self.intensity, Self.radius])
        XCTAssertEqual(restored, list)
    }

    func testUnreadableDisallowedDuplicateAndOptionLinesOnLoad() {
        let lines: [String] = [
            "cc:0:7=test.glow.intensity;curve=log;invert",   // MIDI-004 options are ignored
            "cc:16:7=test.glow.radius", "cc:0:120=test.glow.radius", "note:0:60=test.glow.radius",
            "cc:0:8=", "garbage", "cc:0:x=test.glow.radius", "cc:1:8=test.unknown",
            "cc:0:7=test.glow.radius",                       // the control is already bound
            "cc:2:9=test.glow.intensity",                    // the parameter is already bound
            "cc:3:10=test.glow.radius",
        ]
        let list = MIDIBindingList(storageLines: lines, allowedTargets: [Self.intensity, Self.radius])
        XCTAssertEqual(list.storageLines, ["cc:0:7=test.glow.intensity", "cc:3:10=test.glow.radius"])
        let many: [String] = (0..<100).map { (index: Int) -> String in "cc:0:" + String(index) + "=test.p" + String(index) }
        let allowed: Set<ParameterID> = Set((0..<100).map { (index: Int) -> ParameterID in ParameterID("test.p" + String(index)) })
        XCTAssertEqual(MIDIBindingList(storageLines: many, allowedTargets: allowed).count, MIDIBindingList.capacity)
    }

    // MARK: Values (S5)

    func testValuesAreLinearOverTheRangeAndTheNewestWins() throws {
        let registry = try Self.registry()
        var list = MIDIBindingList()
        list.bind(Self.key(7), to: Self.intensity)
        list.bind(Self.key(8), to: Self.radius)
        let ends = MIDIBindingValues.values(for: [Self.cc(7, value: 127), Self.cc(8, value: 0)], bindings: list, registry: registry)
        XCTAssertEqual(ends[Self.intensity], 1)
        XCTAssertEqual(ends[Self.radius], 0.005)
        let newest = MIDIBindingValues.values(for: [Self.cc(7, value: 127), Self.cc(9), Self.cc(7, value: 0)],
                                              bindings: list, registry: registry)
        XCTAssertEqual(newest, [Self.intensity: 0])
        let skipped = MIDIBindingValues.values(for: [Self.cc(7, value: 127)], bindings: list, registry: registry, skipping: 0)
        XCTAssertTrue(skipped.isEmpty, "the learning message applies no value")
        let otherChannel = MIDIBindingValues.values(for: [Self.cc(7, channel: 1)], bindings: list, registry: registry)
        XCTAssertTrue(otherChannel.isEmpty, "the same controller on another channel is another control")
        let middle = try XCTUnwrap(MIDIBindingValues.value(normalized: 0.5, for: try XCTUnwrap(registry.descriptor(for: Self.radius))))
        XCTAssertEqual(middle, 0.0325, accuracy: 1e-12)
    }

    func testLearnableCatalogKeepsContinuousExternallyControlledAppliedParameters() throws {
        let registry = try Self.registry()
        let learnable = MIDILearnCatalog.learnable(in: registry, applied: [Self.radius, Self.intensity, Self.enabled, Self.locked])
        XCTAssertEqual(learnable.map(\.id), [Self.intensity, Self.radius])
        XCTAssertEqual(MIDILearnCatalog.learnable(in: registry, applied: [Self.radius]).map(\.id), [Self.radius])
    }
}
