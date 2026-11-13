// PERF-006-T07: the preset warm-up's memory pressure steps (PERF-006-R9, R10; PERF-006-S3). The
// controller is tested with a fake worker (deterministic; no setUp state), and the real
// PresetPrewarmer on an EGL display: after the cache step it holds no context, and it warms again.
// Waits are ceilings for a slow shared Mac, never speed targets.
import XCTest
import PresentationLifecycle
import Rendering
@testable import ANGLERendering

@MainActor
final class PresetWarmUpMemoryTests: XCTestCase {
    final class FakeWorker: PresetWarming, @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [[String]] = []
        private var _stops = 0
        private var _holds = false
        var requests: [[String]] { lock.withLock { _requests } }
        var stops: Int { lock.withLock { _stops } }
        var warmedCount: Int { 0 }
        var holdsGraphicsResources: Bool { lock.withLock { _holds } }
        func request(_ presets: [Preset], texturePaths: [String]) {
            lock.withLock {
                _requests.append(presets.map(\.id))
                _holds = true   // a running worker holds its thread and context
            }
        }
        func stop() { lock.withLock { _stops += 1; _holds = false } }
    }

    private static let testPresets = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Vendor/projectM/presets/tests")

    private func preset(_ file: String) -> Preset {
        Preset(id: "tests/\(file)", name: file, fileURL: Self.testPresets.appendingPathComponent(file))
    }

    private func steps(_ controller: PresetWarmUpController) -> (cache: any MemoryPressureResponder, optional: any MemoryPressureResponder) {
        let responders = controller.memoryPressureResponders
        return (responders[0], responders[1])
    }

    /// Long enough for a request with a 20 ms delay to have started if nothing held it.
    private func pastTheDelay() async throws {
        try await Task.sleep(for: .milliseconds(200))
    }

    func testTheCacheStepStopsARunningWorkerOnceAndKeepsTheRequest() async throws {
        let worker = FakeWorker()
        let controller = PresetWarmUpController(worker: worker, delay: .milliseconds(20))
        let (cache, optional) = steps(controller)
        XCTAssertEqual(cache.memoryPressureName, "preset warm-up context")
        XCTAssertEqual(cache.memoryPressureTier, .cache)
        XCTAssertEqual(optional.memoryPressureName, "preset warm-up")
        XCTAssertEqual(optional.memoryPressureTier, .optional)

        XCTAssertEqual(cache.releaseForMemoryPressure(.warning), .none, "idle: nothing held")
        controller.request([preset("a")], texturePaths: [])
        try await pastTheDelay()
        XCTAssertEqual(worker.requests, [["tests/a"]])
        XCTAssertEqual(cache.reclaimableBytes, PresetWarmUpController.estimatedWorkerBytes)

        let release = cache.releaseForMemoryPressure(.warning)
        XCTAssertEqual(release, MemoryPressureRelease(bytes: 256 * 256 * 4, items: 1, bytesEstimated: true))
        XCTAssertFalse(worker.holdsGraphicsResources)
        XCTAssertEqual(cache.releaseForMemoryPressure(.warning), .none, "idempotent")
        XCTAssertEqual(cache.reclaimableBytes, 0)

        controller.request([preset("b")], texturePaths: [])   // the next request starts it again
        try await pastTheDelay()
        XCTAssertEqual(worker.requests, [["tests/a"], ["tests/b"]])
        XCTAssertFalse(controller.isShedForMemoryPressure)
    }

    func testTheCacheStepCancelsARequestWaitingForItsDelay() async throws {
        let worker = FakeWorker()
        let controller = PresetWarmUpController(worker: worker, delay: .milliseconds(20))
        controller.request([preset("a")], texturePaths: [])
        _ = steps(controller).cache.releaseForMemoryPressure(.warning)
        try await pastTheDelay()
        XCTAssertEqual(worker.requests, [], "the waiting request was cancelled")
    }

    func testTheShedHoldsRequestsAndTheRestoreIssuesTheNewestOnce() async throws {
        let worker = FakeWorker()
        let controller = PresetWarmUpController(worker: worker, delay: .milliseconds(20))
        let recovery = MemoryPressureRecovery(repeatWindowSeconds: 30, coolDownSeconds: 60)
        controller.memoryPressureResponders.forEach(recovery.register)
        let report = recovery.handle(.critical, at: 0)
        XCTAssertEqual(report?.steps.map(\.name), ["preset warm-up context", "preset warm-up"])
        XCTAssertTrue(controller.isShedForMemoryPressure)

        controller.request([preset("a")], texturePaths: [])
        controller.request([preset("b")], texturePaths: [])
        try await pastTheDelay()
        XCTAssertEqual(worker.requests, [], "held during the cool-down")

        XCTAssertEqual(recovery.restoreIfDue(at: 60), ["preset warm-up"])
        XCTAssertFalse(controller.isShedForMemoryPressure)
        try await pastTheDelay()
        XCTAssertEqual(worker.requests, [["tests/b"]], "the newest, once")
    }

    func testSuspensionAndTheShedAreIndependent() async throws {
        let worker = FakeWorker()
        let controller = PresetWarmUpController(worker: worker, delay: .milliseconds(20))
        let optional = steps(controller).optional
        controller.request([preset("a")], texturePaths: [])
        _ = optional.releaseForMemoryPressure(.critical)
        controller.suspendForPresentationLoss()
        controller.resumeForPresentation()   // presentation is back, but the shed holds
        try await pastTheDelay()
        XCTAssertEqual(worker.requests, [], "a presentation resume during a shed schedules nothing")

        controller.suspendForPresentationLoss()
        optional.restoreAfterMemoryPressure()   // the cool-down ends while suspended
        try await pastTheDelay()
        XCTAssertEqual(worker.requests, [], "suspension wins over the restore")
        controller.resumeForPresentation()
        try await pastTheDelay()
        XCTAssertEqual(worker.requests, [["tests/a"]])
    }

    // MARK: - Real prewarmer (EGL on the simulator)

    private func waitUntil(_ condition: () -> Bool) async throws {
        // A 90 s ceiling, not a speed target: CI's simulator has no GPU.
        let deadline = ContinuousClock.now + .seconds(90)
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(25)) }
    }

    func testTheRealPrewarmerHoldsNoContextAfterTheCacheStepAndWarmsAgain() async throws {
        let renderer = try ANGLERenderer.make()
        renderer.prewarmDelay = .zero
        let prewarmer = try XCTUnwrap(renderer.warmUp.worker as? PresetPrewarmer)
        let cache = try XCTUnwrap(renderer.memoryPressureResponders.first)
        renderer.prewarm([preset("110-per_pixel.milk")])
        try await waitUntil { prewarmer.warmedCount == 1 }
        XCTAssertTrue(prewarmer.hasGraphicsContext, "the idle thread keeps its context")
        XCTAssertTrue(prewarmer.holdsGraphicsResources)

        let release = cache.releaseForMemoryPressure(.warning)
        XCTAssertEqual(release.items, 1)
        XCTAssertTrue(release.bytesEstimated)
        XCTAssertFalse(prewarmer.isRunning, "S3: no thread")
        XCTAssertFalse(prewarmer.hasGraphicsContext, "S3: context, engine and target destroyed")
        XCTAssertEqual(prewarmer.warmedCount, 1, "the warmed record is kept")

        renderer.prewarm([preset("110-per_pixel.milk"), preset("200-wave.milk")])
        try await waitUntil { prewarmer.warmedCount == 2 }
        XCTAssertEqual(prewarmer.warmedCount, 2, "a new thread warms the preset not warmed yet")
        prewarmer.stop()
    }
}
