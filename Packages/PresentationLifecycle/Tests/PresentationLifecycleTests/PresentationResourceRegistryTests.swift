// PERF-011-T04: the registry of presentation-bound resources (PERF-011-R2 to R4, R12, R13;
// S1, S4, S5), with recording fakes.
import XCTest
@testable import PresentationLifecycle

@MainActor
final class PresentationResourceRegistryTests: XCTestCase {
    /// Shared call log, in call order.
    final class Log {
        var calls: [String] = []
    }

    final class FakeResource: PresentationBoundResource {
        let presentationResourceName: String
        let log: Log
        private(set) var suspended = false
        private(set) var suspends = 0
        private(set) var resumes = 0
        /// Calls in order, "s" or "r" (alternation check).
        private(set) var sequence = ""
        var onSuspend: (() -> Void)?
        var onResume: (() -> Void)?

        init(_ name: String, _ log: Log) {
            presentationResourceName = name
            self.log = log
        }

        func suspendForPresentationLoss() {
            suspended = true
            suspends += 1
            sequence += "s"
            log.calls.append("suspend \(presentationResourceName)")
            onSuspend?()
        }

        func resumeForPresentation() {
            suspended = false
            resumes += 1
            sequence += "r"
            log.calls.append("resume \(presentationResourceName)")
            onResume?()
        }
    }

    private let log = Log()
    private var registry: PresentationResourceRegistry!
    /// Keeps the fakes alive: the registry holds them weakly.
    private var kept: [FakeResource] = []

    override func setUp() async throws {
        log.calls = []
        kept = []
        registry = PresentationResourceRegistry()
    }

    private func make(_ names: String...) -> [FakeResource] {
        let resources = names.map { FakeResource($0, log) }
        resources.forEach(registry.register)
        kept += resources
        return resources
    }

    // MARK: - Order and exactly-once (R3)

    func testSuspendsInReverseOrderAndResumesInRegistrationOrder() {
        let resources = make("loop", "warm-up", "camera")
        XCTAssertEqual(registry.activeCount, 3)

        registry.setCanPresent(false)
        XCTAssertEqual(log.calls, ["suspend camera", "suspend warm-up", "suspend loop"])
        XCTAssertEqual(registry.activeCount, 0, "S1: no active resource in the background")
        XCTAssertEqual(registry.suspendedCount, 3)
        XCTAssertTrue(resources.allSatisfy(\.suspended))

        log.calls = []
        registry.setCanPresent(true)
        XCTAssertEqual(log.calls, ["resume loop", "resume warm-up", "resume camera"])
        XCTAssertEqual(registry.activeCount, 3)
        XCTAssertEqual(registry.suspendedCount, 0)
    }

    func testRepeatedSignalsDoNothing() {
        let resources = make("a", "b")
        XCTAssertNil(registry.setCanPresent(true), "already presentable")
        XCTAssertEqual(log.calls, [])
        XCTAssertNotNil(registry.setCanPresent(false))
        XCTAssertNil(registry.setCanPresent(false))
        XCTAssertNotNil(registry.setCanPresent(true))
        XCTAssertNil(registry.setCanPresent(true))
        for resource in resources {
            XCTAssertEqual(resource.suspends, 1)
            XCTAssertEqual(resource.resumes, 1)
        }
    }

    func testRapidFlipsEndInTheLastStateWithAlternatingCalls() {
        let resources = make("a", "b", "c")
        for _ in 0..<10 {
            registry.setCanPresent(false)
            registry.setCanPresent(true)
        }
        registry.setCanPresent(false)
        for resource in resources {
            XCTAssertEqual(resource.suspends, 11)
            XCTAssertEqual(resource.resumes, 10)
            XCTAssertTrue(resource.suspended)
            XCTAssertFalse(resource.sequence.contains("ss") || resource.sequence.contains("rr"))
        }
    }

    /// S4: 100 seeded signals through PresentationAvailability.
    func testSeededSignalSequence() {
        let resources = make("a", "b", "c")
        var availability = PresentationAvailability()
        var seed: UInt64 = 0x5EED_0011
        let signals = PresentationSignal.allCases
        var transitions = 0
        registry.onTransition = { _ in transitions += 1 }
        var expectedTransitions = 0
        for _ in 0..<100 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let signal = signals[Int((seed >> 33) % UInt64(signals.count))]
            let before = availability.canPresent
            let after = availability.apply(signal)
            if before != after { expectedTransitions += 1 }
            registry.setCanPresent(after)
            XCTAssertEqual(registry.canPresent, after)
            XCTAssertEqual(registry.activeCount, after ? 3 : 0)
        }
        XCTAssertGreaterThan(expectedTransitions, 5, "the sequence exercises both directions")
        XCTAssertEqual(transitions, expectedTransitions)
        for resource in resources {
            XCTAssertEqual(resource.suspended, !availability.canPresent)
            XCTAssertFalse(resource.sequence.contains("ss") || resource.sequence.contains("rr"), resource.sequence)
            XCTAssertEqual(resource.suspends + resource.resumes, expectedTransitions)
        }
    }

    // MARK: - Registration (R2, R4)

    func testLateRegistrationIsSuspendedAtOnceAndResumedWithTheOthers() {
        _ = make("loop")
        registry.setCanPresent(false)
        log.calls = []
        let camera = FakeResource("camera", log)
        registry.register(camera)
        XCTAssertEqual(log.calls, ["suspend camera"], "never runs in the background")
        XCTAssertEqual(registry.activeCount, 0)

        log.calls = []
        registry.setCanPresent(true)
        XCTAssertEqual(log.calls, ["resume loop", "resume camera"])
        XCTAssertEqual(camera.suspends, 1)
        XCTAssertEqual(camera.resumes, 1)
    }

    func testRegistrationWhilePresentableCallsNothing() {
        _ = make("loop")
        XCTAssertEqual(log.calls, [])
    }

    func testDuplicateRegistrationIsIgnored() {
        let resources = make("loop")
        registry.register(resources[0])
        XCTAssertEqual(registry.registeredCount, 1)
        registry.setCanPresent(false)
        XCTAssertEqual(resources[0].suspends, 1)
    }

    func testUnregisterStopsCallsAndDoesNotResume() {
        let resources = make("loop", "camera")
        registry.setCanPresent(false)
        registry.unregister(resources[1])
        log.calls = []
        registry.setCanPresent(true)
        XCTAssertEqual(log.calls, ["resume loop"])
        XCTAssertTrue(resources[1].suspended, "its owner decides what happens next")
        registry.setCanPresent(false)
        XCTAssertEqual(resources[1].suspends, 1)
        XCTAssertEqual(registry.registeredCount, 1)
    }

    func testUnregisteringAnUnknownResourceDoesNothing() {
        _ = make("loop")
        registry.unregister(FakeResource("stranger", log))
        XCTAssertEqual(registry.registeredCount, 1)
    }

    func testDoesNotKeepResourcesAliveAndSkipsDeallocatedOnes() {
        var camera: FakeResource? = FakeResource("camera", log)
        weak let weakCamera = camera
        registry.register(camera!)
        _ = make("loop")
        camera = nil
        XCTAssertNil(weakCamera, "the registry holds resources weakly")
        XCTAssertEqual(registry.registeredCount, 1)
        let report = registry.setCanPresent(false)
        XCTAssertEqual(log.calls, ["suspend loop"])
        XCTAssertEqual(report?.registered, 1)
        XCTAssertEqual(report?.activeBefore, 1)
    }

    func testAResourceDeallocatedWhileSuspendedIsNotResumed() {
        var camera: FakeResource? = FakeResource("camera", log)
        registry.register(camera!)
        registry.setCanPresent(false)
        camera = nil
        log.calls = []
        let report = registry.setCanPresent(true)
        XCTAssertEqual(log.calls, [])
        XCTAssertEqual(report, PresentationTransitionReport(canPresent: true, registered: 0, activeBefore: 0, activeAfter: 0))
    }

    // MARK: - Reentrancy (R13)

    func testAResourceMayUnregisterAnotherFromItsCallback() {
        let resources = make("a", "b", "c")
        // Suspension runs c, b, a. c removes a before a's turn.
        resources[2].onSuspend = { [registry, resources] in registry?.unregister(resources[0]) }
        registry.setCanPresent(false)
        XCTAssertEqual(log.calls, ["suspend c", "suspend b"])
        XCTAssertEqual(resources[0].suspends, 0)
    }

    func testAResourceMayRegisterAnotherFromItsCallback() {
        let resources = make("a")
        let late = FakeResource("late", log)
        resources[0].onSuspend = { [registry] in registry?.register(late) }
        registry.setCanPresent(false)
        XCTAssertEqual(log.calls, ["suspend a", "suspend late"])
        XCTAssertEqual(late.suspends, 1, "suspended once, by its registration")
        log.calls = []
        registry.setCanPresent(true)
        XCTAssertEqual(log.calls, ["resume a", "resume late"])
    }

    func testAvailabilityChangedFromACallbackIsAppliedAfterTheSweep() {
        let resources = make("a", "b")
        var reports: [PresentationTransitionReport] = []
        registry.onTransition = { reports.append($0) }
        // b is suspended first and immediately reports that presentation is back.
        resources[1].onSuspend = { [registry] in
            XCTAssertNil(registry?.setCanPresent(true))
        }
        let last = registry.setCanPresent(false)
        XCTAssertEqual(log.calls, ["suspend b", "suspend a", "resume a", "resume b"])
        XCTAssertTrue(registry.canPresent)
        XCTAssertEqual(registry.activeCount, 2)
        XCTAssertEqual(reports.map(\.canPresent), [false, true])
        XCTAssertEqual(last?.canPresent, true)
    }

    // MARK: - Reports (R12)

    func testReportsCountsBeforeAndAfter() {
        _ = make("loop", "warm-up")
        var reports: [PresentationTransitionReport] = []
        registry.onTransition = { reports.append($0) }
        let lost = registry.setCanPresent(false)
        let regained = registry.setCanPresent(true)
        registry.setCanPresent(true)
        XCTAssertEqual(lost, PresentationTransitionReport(canPresent: false, registered: 2, activeBefore: 2, activeAfter: 0))
        XCTAssertEqual(regained, PresentationTransitionReport(canPresent: true, registered: 2, activeBefore: 0, activeAfter: 2))
        XCTAssertEqual(reports, [lost, regained].compactMap { $0 }, "one report per real change")
    }

    func testAnEmptyRegistryStillTracksAvailability() {
        let report = registry.setCanPresent(false)
        XCTAssertEqual(report, PresentationTransitionReport(canPresent: false, registered: 0, activeBefore: 0, activeAfter: 0))
        XCTAssertFalse(registry.canPresent)
    }

    func testSnapshotListsNamesAndStatesInOrder() {
        _ = make("loop", "warm-up")
        registry.setCanPresent(false)
        let snapshot = registry.snapshot
        XCTAssertEqual(snapshot.map(\.name), ["loop", "warm-up"])
        XCTAssertEqual(snapshot.map(\.suspended), [true, true])
    }
}
