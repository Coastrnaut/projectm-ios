// OSC-003-T10, T11: the OSC Routes list in the app (specs/191-osc-003-parameter-routes, contract R3). Datagrams go
// through the receiver's decoder path (`dispatcher.handle`), never a socket. The live value reaches the native host
// through the same path as MIDI-003, so ACC-012's Strict cap applies.
import Metal
import ParameterGraph
import PerformanceControl
import VisualEffects
import VisualGenerators
import VisualParameters
import FlashSafety
import XCTest
@testable import projectM_iOS

@MainActor
final class OSCRoutesCoordinatorTests: XCTestCase {
    private static let intensity: ParameterID = VisualParameterIDs.bloomIntensity
    private static let glowAlias = "/projectm/param/glow.intensity"

    private struct Harness {
        let defaults: UserDefaults
        let suite: String
        let settings: AppSettings
        let receiver: OSCReceiver
        let osc: OSCReceiverCoordinator
        let routes: OSCRoutesCoordinator
    }

    private func makeHarness(suite existing: String? = nil) throws -> Harness {
        let suite: String = existing ?? "OSCRoutesCoordinatorTests-\(UUID().uuidString)"
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        let routable: [ParameterDescriptor] = OSCRoutesCoordinator.routable()
        let receiver = OSCReceiver(store: OSCRoutesCoordinator.makeStore(routable: routable),
                                   routes: OSCRoutesCoordinator.initialRoutes(routable: routable, defaults: defaults),
                                   makeTransport: { () -> (any OSCDatagramTransport)? in nil })
        let osc = OSCReceiverCoordinator(settings: settings, receiver: receiver)
        let routes = OSCRoutesCoordinator(routable: routable, defaults: defaults) { [weak osc] (r: [OSCRoute]) -> Void in osc?.setRoutes(r) }
        osc.routes = routes
        return Harness(defaults: defaults, suite: suite, settings: settings, receiver: receiver, osc: osc, routes: routes)
    }

    private func send(_ h: Harness, _ address: String, _ argument: OSCArgument) {
        h.receiver.dispatcher.handle(OSCEncoder.encode(OSCMessage(address: address, arguments: [argument])))
    }

    private func settle(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(nanoseconds: 10_000_000) }
    }

    func testTheReceiverStoreAndTableCoverTheGlow() throws {
        let h = try makeHarness()
        defer { h.defaults.removePersistentDomain(forName: h.suite) }
        XCTAssertEqual(h.receiver.store.registry.count, 5, "the test value and the four glow parameters")
        XCTAssertEqual(h.routes.rows.count, 9, "test, four standard routes, four glow aliases")
        XCTAssertEqual(h.routes.rows.first?.address, "/projectm/test")
        XCTAssertTrue(h.routes.rows.contains { $0.address == "/projectm/param/effect.bloom.intensity" && $0.target == "Glow intensity" })
        XCTAssertTrue(h.routes.rows.allSatisfy(\.isEnabled), "every route is on by default")
    }

    func testARouteDrivesTheLiveValueAndADisabledRouteIsIgnoredAndRemembered() async throws {
        let h = try makeHarness()
        defer { h.defaults.removePersistentDomain(forName: h.suite) }
        var pushed: [[ParameterID: Double]] = []
        h.osc.applyLiveValues = { (values: [ParameterID: Double]) -> Void in pushed.append(values) }

        send(h, Self.glowAlias, .float(0.25))
        try await settle { h.osc.liveValues[Self.intensity] == 0.25 }
        XCTAssertEqual(h.osc.liveValues, [Self.intensity: 0.25])
        XCTAssertEqual(pushed.last, [Self.intensity: 0.25])

        send(h, "/projectm/unknown", .float(1))
        try await settle { h.osc.unknownAddressCount == 1 }
        XCTAssertEqual(h.osc.unknownAddressCount, 1)
        XCTAssertEqual(h.osc.liveValues, [Self.intensity: 0.25], "unchanged")

        h.routes.setEnabled(false, address: Self.glowAlias)
        XCTAssertEqual(h.defaults.stringArray(forKey: OSCRoutesCoordinator.disabledRoutesKey), [Self.glowAlias])
        send(h, Self.glowAlias, .float(0.9))
        XCTAssertEqual(h.receiver.store.double(Self.intensity), 0.25, "a disabled route is ignored")
        XCTAssertEqual(h.osc.liveValues, [Self.intensity: 0.25], "the standard route still reaches the intensity: value kept")

        // Relaunch: the disabled route stays off.
        let again = try makeHarness(suite: h.suite)
        XCTAssertFalse(again.routes.rows.first { $0.address == Self.glowAlias }?.isEnabled ?? true)
        XCTAssertFalse(again.receiver.dispatcher.routedAddresses.contains(Self.glowAlias))

        // Turning off every route to the intensity returns it to the manual value.
        h.routes.setEnabled(false, address: "/projectm/param/effect.bloom.intensity")
        try await settle { h.osc.liveValues.isEmpty }
        XCTAssertEqual(h.osc.liveValues, [:])
        XCTAssertEqual(pushed.last, [:])
    }

    func testTurningOSCOffForgetsLiveValues() async throws {
        let h = try makeHarness()
        defer { h.defaults.removePersistentDomain(forName: h.suite) }
        send(h, Self.glowAlias, .float(0.5))
        try await settle { !h.osc.liveValues.isEmpty }
        XCTAssertFalse(h.osc.liveValues.isEmpty)
        h.osc.setEnabled(false)
        try await settle { h.osc.liveValues.isEmpty }
        XCTAssertEqual(h.osc.liveValues, [:])
    }

    func testAliasesAreValidatedStoredAndDeleted() throws {
        let h = try makeHarness()
        defer { h.defaults.removePersistentDomain(forName: h.suite) }
        XCTAssertFalse(h.routes.addAlias(address: "/fader/*", parameter: Self.intensity))
        XCTAssertEqual(h.routes.aliasError, OSCRouteAliasError.invalidAddress.message)
        XCTAssertFalse(h.routes.addAlias(address: "/projectm/mine", parameter: Self.intensity))
        XCTAssertFalse(h.routes.addAlias(address: "/x", parameter: OSCReceiverCatalog.testValueID), "only routable parameters")
        XCTAssertTrue(h.routes.addAlias(address: "/fader/1", parameter: Self.intensity))
        XCTAssertNil(h.routes.aliasError)
        XCTAssertFalse(h.routes.addAlias(address: "/fader/1", parameter: Self.intensity), "duplicate")
        XCTAssertEqual(h.defaults.stringArray(forKey: OSCRoutesCoordinator.aliasesKey), ["/fader/1=effect.bloom.intensity"])
        XCTAssertTrue(h.receiver.dispatcher.routedAddresses.contains("/fader/1"))
        send(h, "/fader/1", .float(1))
        XCTAssertEqual(h.receiver.store.double(Self.intensity), 1)

        h.routes.deleteAlias(address: "/fader/1")
        XCTAssertNil(h.defaults.stringArray(forKey: OSCRoutesCoordinator.aliasesKey))
        XCTAssertFalse(h.receiver.dispatcher.routedAddresses.contains("/fader/1"))
    }

    func testTheOSCValueGoesThroughTheMIDIPathAndIsCappedByStrict() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32,
                                               glow: BloomParameters(enabled: true, intensity: 0.5))
        var live = ExternalLiveValues()
        live.update(.osc, [Self.intensity: 1])
        host.externalValues = live.merged
        XCTAssertEqual(host.effectiveGlow.intensity, 1, "Standard: OSC reaches the top of the range")
        host.safetyClamp = SafetyClamp(profile: SensorySafetyProfile(preset: .strict), reduceFlashingSetting: false)
        let cap: Float = BloomParameters.intensityRange.upperBound * Float(SensorySafetyLimits.strict.intensityLimit)
        XCTAssertEqual(host.effectiveGlow.intensity, cap, accuracy: 1e-6, "ACC-012 Strict caps the OSC value")
        XCTAssertEqual(host.glow.intensity, 0.5, "the manual glow is unchanged")
    }
}
