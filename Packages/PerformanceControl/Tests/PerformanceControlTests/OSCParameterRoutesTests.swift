// OSC-003-T03 to T07: the allowlisted route table (specs/191-osc-003-parameter-routes, contract R1, R2).
// The roadmap acceptance, "Known route changes intended target and unknown route is ignored", goes through
// the decoder path (encoded datagrams into `OSCDispatcher.handle`) with a fake clock. No networking; Linux-safe.
import ParameterGraph
@testable import PerformanceControl
import XCTest

final class OSCParameterRoutesTests: XCTestCase {
    private static let intensity: ParameterID = "effect.bloom.intensity"
    private static let radius: ParameterID = "effect.bloom.radius"
    private static let locked: ParameterID = "effect.bloom.locked"
    private static let notApplied: ParameterID = "effect.bloom.other"
    private static let glowAlias = "/projectm/param/glow.intensity"

    private static func registry() throws -> ParameterRegistry {
        let group = ParameterGroup(id: "effect.bloom", displayName: "Glow")
        return try ParameterRegistry(descriptors: [
            OSCReceiverCatalog.testValueDescriptor,
            ParameterDescriptor(id: intensity, displayName: "Intensity", group: group, unit: .normalized,
                                kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.5), modulation: .continuousDefault),
            ParameterDescriptor(id: radius, displayName: "Radius", group: group, unit: .none,
                                kind: .continuous(minimum: 0.005, maximum: 0.06, defaultValue: 0.02), modulation: .continuousDefault),
            ParameterDescriptor(id: locked, displayName: "Locked", group: group, unit: .none,
                                kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.5), modulation: .none),
            ParameterDescriptor(id: notApplied, displayName: "Other", group: group, unit: .none,
                                kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.5), modulation: .continuousDefault),
        ])
    }

    private static let applied: Set<ParameterID> = [intensity, radius, locked]

    private struct Fixture {
        let dispatcher: OSCDispatcher
        let store: ParameterStore
        let table: [OSCParameterRoute]
        let clock: FakeMonotonicClock
    }

    private func makeFixture(disabled: Set<String> = [], userAliases: [OSCRouteAlias] = [],
                             limits: OSCRateLimitConfiguration = .default) throws -> Fixture {
        let registry = try Self.registry()
        let routable = OSCParameterRoutes.routable(in: registry, applied: Self.applied)
        let table = OSCParameterRoutes.table(routable: routable, builtInAliases: [(Self.glowAlias, Self.intensity)],
                                             userAliases: userAliases)
        let store = ParameterStore(registry: registry)
        let clock = FakeMonotonicClock()
        let dispatcher = OSCDispatcher(store: store, routes: OSCParameterRoutes.active(table, disabled: disabled),
                                       limits: limits, clock: clock.clock, scheduler: ManualFlushScheduler(clock: clock).scheduler)
        return Fixture(dispatcher: dispatcher, store: store, table: table, clock: clock)
    }

    private func packet(_ address: String, _ arguments: [OSCArgument]) -> [UInt8] {
        OSCEncoder.encode(OSCMessage(address: address, arguments: arguments))
    }

    /// Every stored value, compared bit for bit.
    private func snapshot(_ store: ParameterStore) -> [ParameterID: UInt64] {
        var result: [ParameterID: UInt64] = [:]
        for id in store.registry.ids { result[id] = store.double(id)?.bitPattern }
        return result
    }

    // MARK: Table (R1)

    func testTableListsOnlyRoutableParametersWithOneStandardRuleAndTheAlias() throws {
        let f = try makeFixture()
        XCTAssertEqual(f.table.map(\.address), ["/projectm/test", "/projectm/param/effect.bloom.intensity",
                                                "/projectm/param/effect.bloom.radius", Self.glowAlias])
        XCTAssertEqual(f.table.map(\.origin), [.test, .standard, .standard, .builtInAlias])
        XCTAssertFalse(f.table.contains { $0.parameter == Self.locked }, "no external control: never routable")
        XCTAssertFalse(f.table.contains { $0.parameter == Self.notApplied }, "not applied by the app: never routable")
    }

    // MARK: Acceptance (S1)

    func testKnownRouteChangesTheIntendedTargetAndUnknownRouteIsIgnored() throws {
        let f = try makeFixture()
        // 1. A known route sets exactly its target to the mapped value.
        var before = snapshot(f.store)
        XCTAssertEqual(f.dispatcher.handle(packet(Self.glowAlias, [.float(0.25)])), .applied(Self.intensity, 0.25))
        XCTAssertEqual(f.store.double(Self.intensity), 0.25)
        before[Self.intensity] = Double(0.25).bitPattern
        XCTAssertEqual(snapshot(f.store), before, "nothing else changed")
        XCTAssertEqual(f.dispatcher.liveValues, [Self.intensity: 0.25])

        // 2. An unknown address changes nothing and is counted.
        before = snapshot(f.store)
        XCTAssertEqual(f.dispatcher.handle(packet("/projectm/unknown", [.float(1)])), .unknownAddress)
        XCTAssertEqual(snapshot(f.store), before, "all values byte-identical")
        XCTAssertEqual(f.dispatcher.counters.unknownAddresses, 1)
        XCTAssertEqual(f.dispatcher.counters.ignored, 1)

        // 3. A wrong argument type is ignored.
        XCTAssertEqual(f.dispatcher.handle(packet(Self.glowAlias, [.string("text")])), .wrongArguments)
        XCTAssertEqual(f.dispatcher.handle(packet(Self.glowAlias, [.true])), .wrongArguments, "booleans are not numbers")
        XCTAssertEqual(snapshot(f.store), before)
        XCTAssertEqual(f.dispatcher.counters.ignored, 3)
        XCTAssertEqual(f.dispatcher.counters.applied, 1)
    }

    func testADisabledRouteIsIgnoredAndOtherRoutesToTheSameParameterStillWork() throws {
        let f = try makeFixture(disabled: [Self.glowAlias])
        let before = snapshot(f.store)
        XCTAssertEqual(f.dispatcher.handle(packet(Self.glowAlias, [.float(0.9)])), .unknownAddress)
        XCTAssertEqual(snapshot(f.store), before)
        XCTAssertEqual(f.dispatcher.handle(packet("/projectm/param/effect.bloom.intensity", [.float(0.9)])),
                       .applied(Self.intensity, Double(Float(0.9))))
    }

    func testDisablingWhileRunningStopsTheRouteAndDropsItsLiveValue() throws {
        let f = try makeFixture()
        _ = f.dispatcher.handle(packet(Self.glowAlias, [.float(0.75)]))
        let withoutIntensity = f.table.filter { $0.parameter != Self.intensity }
        f.dispatcher.setRoutes(OSCParameterRoutes.active(withoutIntensity, disabled: []))
        XCTAssertEqual(f.dispatcher.liveValues, [:], "no route reaches the intensity: its live value is gone")
        XCTAssertEqual(f.dispatcher.handle(packet(Self.glowAlias, [.float(0.1)])), .unknownAddress)
        XCTAssertEqual(f.store.double(Self.intensity), 0.75)
        f.dispatcher.clearLiveValues()
        XCTAssertTrue(f.dispatcher.liveValues.isEmpty)
    }

    // MARK: Values (R4)

    func testNormalizedValuesMapOverTheRegistryRangeAndClamp() throws {
        let f = try makeFixture()
        let address = "/projectm/param/effect.bloom.radius"
        XCTAssertEqual(f.dispatcher.handle(packet(address, [.float(0)])), .applied(Self.radius, 0.005))
        f.clock.advance(by: 1_000_000_000)
        XCTAssertEqual(f.dispatcher.handle(packet(address, [.double(1)])), .applied(Self.radius, 0.06))
        f.clock.advance(by: 1_000_000_000)
        guard case let .applied(_, half) = f.dispatcher.handle(packet(address, [.double(0.5)])) else { return XCTFail() }
        XCTAssertEqual(half, 0.0325, accuracy: 1e-12)
        f.clock.advance(by: 1_000_000_000)
        XCTAssertEqual(f.dispatcher.handle(packet(address, [.int(7)])), .applied(Self.radius, 0.06), "above 1 clamps to the maximum")
        f.clock.advance(by: 1_000_000_000)
        XCTAssertEqual(f.dispatcher.handle(packet(address, [.int64(-2)])), .applied(Self.radius, 0.005), "below 0 clamps")
        XCTAssertEqual(f.dispatcher.handle(packet(address, [.float(.nan)])), .refusedByStore)
        XCTAssertEqual(f.dispatcher.handle(packet(address, [.float(0.5), .float(0.5)])), .wrongArguments)
        XCTAssertEqual(f.dispatcher.handle(packet("/projectm/test", [.float(0.4)])), .applied(OSCReceiverCatalog.testValueID, Double(Float(0.4))),
                       "the OSC-001 test route still takes its raw value")
    }

    // MARK: Rate limiter (R8)

    func testTheTargetRateLimitStillAppliesAndTheHeldValueIsTheMappedOne() throws {
        let limits = OSCRateLimitConfiguration(perTarget: OSCRateLimit(perSecond: 10, burst: 1))
        let f = try makeFixture(limits: limits)
        let address = "/projectm/param/effect.bloom.radius"
        XCTAssertEqual(f.dispatcher.handle(packet(address, [.float(0)])), .applied(Self.radius, 0.005))
        XCTAssertEqual(f.dispatcher.handle(packet(address, [.float(1)])), .coalesced(Self.radius))
        XCTAssertEqual(f.dispatcher.handle(packet(Self.glowAlias, [.float(1)])), .applied(Self.intensity, 1), "other targets are separate")
        f.clock.advance(by: 100_000_000)
        f.dispatcher.flush()
        XCTAssertEqual(f.store.double(Self.radius), 0.06, "the flush applies the mapped value")
        XCTAssertEqual(f.dispatcher.liveValues[Self.radius], 0.06)
        XCTAssertEqual(f.dispatcher.counters.coalesced, 1)
        XCTAssertEqual(f.dispatcher.counters.applied, 3)
    }

    // MARK: Aliases (R7)

    func testAliasValidation() throws {
        let f = try makeFixture()
        let registry = try Self.registry()
        let routable = OSCParameterRoutes.routable(in: registry, applied: Self.applied)
        func check(_ address: String, _ parameter: ParameterID = Self.radius, aliases: [OSCRouteAlias] = [])
            -> Result<OSCRouteAlias, OSCRouteAliasError> {
            OSCRouteAliasRules.validate(address: address, parameter: parameter, table: f.table, userAliases: aliases, routable: routable)
        }
        XCTAssertEqual(check("  /fader/1 "), .success(OSCRouteAlias(address: "/fader/1", parameter: Self.radius)))
        for bad in ["", "/", "fader", "/fader/", "//fader", "/a//b", "/fa der", "/fader/*", "/f?", "/f[1]", "/{a,b}", "/f#",
                    "/" + String(repeating: "a", count: 64)] {
            XCTAssertEqual(check(bad), .failure(.invalidAddress), bad)
        }
        XCTAssertEqual(check("/projectm/mine"), .failure(.reservedPrefix))
        XCTAssertEqual(check("/projectm"), .failure(.reservedPrefix))
        XCTAssertEqual(check("/x", aliases: [OSCRouteAlias(address: "/x", parameter: Self.intensity)]), .failure(.duplicate))
        XCTAssertEqual(check("/x", Self.locked), .failure(.unknownParameter))
        XCTAssertEqual(check("/x", Self.notApplied), .failure(.unknownParameter))
        let full = (0..<OSCRouteAliasRules.maximumUserAliases).map { OSCRouteAlias(address: "/a\($0)", parameter: Self.radius) }
        XCTAssertEqual(check("/x", aliases: full), .failure(.tooMany))
    }

    func testUserAliasesRouteAndRoundTripTheirStorageLines() throws {
        let alias = OSCRouteAlias(address: "/fader/1", parameter: Self.radius)
        XCTAssertEqual(alias.storageLine, "/fader/1=effect.bloom.radius")
        XCTAssertEqual(OSCRouteAlias(storageLine: alias.storageLine), alias)
        XCTAssertNil(OSCRouteAlias(storageLine: "/bad path=effect.bloom.radius"))
        XCTAssertNil(OSCRouteAlias(storageLine: "no separator"))
        let stale = OSCRouteAlias(address: "/old", parameter: "effect.bloom.removed")
        let f = try makeFixture(userAliases: [alias, stale])
        XCTAssertEqual(f.table.last, OSCParameterRoute(address: "/fader/1", parameter: Self.radius, origin: .userAlias))
        XCTAssertFalse(f.table.contains { $0.address == "/old" }, "an alias to a parameter that is not routable is dropped")
        XCTAssertEqual(f.dispatcher.handle(packet("/fader/1", [.float(1)])), .applied(Self.radius, 0.06))
    }
}
