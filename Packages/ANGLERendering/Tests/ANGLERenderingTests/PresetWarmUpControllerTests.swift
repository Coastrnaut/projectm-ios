// PERF-011-T08, T15: the preset warm-up while the app cannot present frames (PERF-011-R7, R8).
// The controller is tested with a fake worker (deterministic), and the real PresetPrewarmer on an
// EGL display: after a stop it has no thread and no context, and it warms again afterwards.
import XCTest
import PresentationLifecycle
import Rendering
@testable import ANGLERendering

@MainActor
final class PresetWarmUpControllerTests: XCTestCase {
    final class FakeWorker: PresetWarming, @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [[String]] = []
        private var _stops = 0
        var requests: [[String]] { lock.withLock { _requests } }
        var stops: Int { lock.withLock { _stops } }
        var warmedCount: Int { lock.withLock { Set(_requests.flatMap { $0 }).count } }
        func request(_ presets: [Preset], texturePaths: [String]) { lock.withLock { _requests.append(presets.map(\.id)) } }
        func stop() { lock.withLock { _stops += 1 } }
    }

    private static let testPresets = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Vendor/projectM/presets/tests")

    private func preset(_ file: String) -> Preset {
        Preset(id: "tests/\(file)", name: file, fileURL: Self.testPresets.appendingPathComponent(file))
    }

    private let delay = Duration.milliseconds(60)
    private var worker: FakeWorker!
    private var controller: PresetWarmUpController!

    override func setUp() async throws {
        worker = FakeWorker()
        controller = PresetWarmUpController(worker: worker, delay: delay)
    }

    /// Waits well past the delay so a cancelled or suppressed request would have started.
    private func pastTheDelay() async throws {
        try await Task.sleep(for: .milliseconds(250))
    }

    // MARK: - Fake worker: scheduling

    func testARequestStartsAfterTheDelay() async throws {
        controller.request([preset("a"), preset("b")], texturePaths: ["/t"])
        XCTAssertEqual(worker.requests, [], "nothing before the delay")
        try await pastTheDelay()
        XCTAssertEqual(worker.requests, [["tests/a", "tests/b"]])
        XCTAssertEqual(controller.startedRequests, 1)
    }

    func testSuspendCancelsAWaitingRequestAndStopsTheWorkerOnce() async throws {
        controller.request([preset("a")], texturePaths: [])
        controller.suspendForPresentationLoss()
        controller.suspendForPresentationLoss()   // repeat: nothing
        XCTAssertTrue(controller.isSuspended)
        XCTAssertEqual(worker.stops, 1)
        try await pastTheDelay()
        XCTAssertEqual(worker.requests, [], "R7: the waiting request starts no work in the background")
    }

    func testARequestWhileSuspendedStartsNothing() async throws {
        controller.suspendForPresentationLoss()
        controller.request([preset("a")], texturePaths: [])
        try await pastTheDelay()
        XCTAssertEqual(worker.requests, [])
        XCTAssertEqual(controller.startedRequests, 0)
    }

    func testResumeIssuesTheLastRequestAgainOnceAfterTheDelay() async throws {
        controller.request([preset("old")], texturePaths: [])
        controller.suspendForPresentationLoss()
        controller.request([preset("newer")], texturePaths: ["/t"])   // made while suspended
        controller.resumeForPresentation()
        controller.resumeForPresentation()   // repeat: nothing
        XCTAssertEqual(worker.requests, [], "the normal delay applies")
        try await pastTheDelay()
        XCTAssertEqual(worker.requests, [["tests/newer"]], "R8: the most recent request, once")
    }

    func testResumeReissuesARequestThatHadAlreadyStarted() async throws {
        controller.request([preset("a")], texturePaths: [])
        try await pastTheDelay()
        controller.suspendForPresentationLoss()   // the worker dropped its queue
        controller.resumeForPresentation()
        try await pastTheDelay()
        XCTAssertEqual(worker.requests, [["tests/a"], ["tests/a"]], "the worker skips what it already warmed")
        XCTAssertEqual(worker.stops, 1)
    }

    func testResumeWithoutARequestStartsNothing() async throws {
        controller.suspendForPresentationLoss()
        controller.resumeForPresentation()
        try await pastTheDelay()
        XCTAssertEqual(worker.requests, [])
    }

    func testDisabledStartsNothingAndForgetsTheRequest() async throws {
        controller.enabled = false
        controller.request([preset("a")], texturePaths: [])
        controller.suspendForPresentationLoss()
        controller.enabled = true
        controller.resumeForPresentation()
        try await pastTheDelay()
        XCTAssertEqual(worker.requests, [])
    }

    func testAnEmptyRequestClearsTheRememberedOne() async throws {
        controller.request([preset("a")], texturePaths: [])
        controller.request([], texturePaths: [])
        controller.suspendForPresentationLoss()
        controller.resumeForPresentation()
        try await pastTheDelay()
        XCTAssertEqual(worker.requests, [])
    }

    func testRapidFlipsStartTheLastRequestOnce() async throws {
        controller.request([preset("a")], texturePaths: [])
        for _ in 0..<10 {
            controller.suspendForPresentationLoss()
            controller.resumeForPresentation()
        }
        try await pastTheDelay()
        XCTAssertEqual(worker.requests, [["tests/a"]])
        XCTAssertEqual(worker.stops, 10)
    }

    func testEndingSuspendedStartsNothing() async throws {
        controller.request([preset("a")], texturePaths: [])
        for _ in 0..<3 {
            controller.resumeForPresentation()
            controller.suspendForPresentationLoss()
        }
        try await pastTheDelay()
        XCTAssertEqual(worker.requests, [])
    }

    func testShutdownStopsTheWorkerAndForgetsTheRequest() async throws {
        controller.request([preset("a")], texturePaths: [])
        controller.shutdown()
        try await pastTheDelay()
        XCTAssertEqual(worker.requests, [])
        XCTAssertEqual(worker.stops, 1)
    }

    func testItIsAPresentationBoundResourceInARegistry() async throws {
        let registry = PresentationResourceRegistry()
        registry.register(controller)
        controller.request([preset("a")], texturePaths: [])
        registry.setCanPresent(false)
        XCTAssertTrue(controller.isSuspended)
        XCTAssertEqual(registry.snapshot.map(\.name), ["preset warm-up"])
        registry.setCanPresent(true)
        try await pastTheDelay()
        XCTAssertEqual(worker.requests, [["tests/a"]])
    }

    // MARK: - Real prewarmer (EGL on the simulator)

    private func realPrewarmer(_ renderer: ANGLERenderer) throws -> PresetPrewarmer {
        try XCTUnwrap(renderer.warmUp.worker as? PresetPrewarmer)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 where !condition() { try await Task.sleep(for: .milliseconds(25)) }
    }

    func testStopReleasesTheThreadAndContextAndTheWorkerRestarts() async throws {
        let renderer = try ANGLERenderer.make()
        let prewarmer = try realPrewarmer(renderer)
        XCTAssertFalse(prewarmer.isRunning, "idle until the first request")
        XCTAssertFalse(prewarmer.hasGraphicsContext)
        prewarmer.stop()   // idle: nothing to do

        prewarmer.request([preset("110-per_pixel.milk")], texturePaths: [])
        try await waitUntil { prewarmer.warmedCount == 1 }
        XCTAssertEqual(prewarmer.warmedCount, 1)
        XCTAssertTrue(prewarmer.isRunning)
        XCTAssertTrue(prewarmer.hasGraphicsContext)

        prewarmer.stop()
        XCTAssertFalse(prewarmer.isRunning, "S2: no thread")
        XCTAssertFalse(prewarmer.hasGraphicsContext, "S2: context, engine and target destroyed")
        XCTAssertEqual(prewarmer.queuedCount, 0)

        prewarmer.request([preset("110-per_pixel.milk"), preset("200-wave.milk")], texturePaths: [])
        try await waitUntil { prewarmer.warmedCount == 2 }
        XCTAssertEqual(prewarmer.warmedCount, 2, "a new thread warms the preset that was not warmed yet")
        XCTAssertTrue(prewarmer.isWarmed("tests/200-wave.milk"))
        prewarmer.stop()
        XCTAssertFalse(prewarmer.isRunning)
    }

    func testStopInTheMiddleOfAQueueDropsTheRest() async throws {
        let renderer = try ANGLERenderer.make()
        let prewarmer = try realPrewarmer(renderer)
        let files = ["100-square.milk", "101-per_frame.milk", "110-per_pixel.milk", "200-wave.milk"]
        prewarmer.request(files.map(preset), texturePaths: [])
        prewarmer.stop()   // at once: at most the preset in progress finishes or is abandoned
        XCTAssertFalse(prewarmer.isRunning)
        XCTAssertFalse(prewarmer.hasGraphicsContext)
        XCTAssertEqual(prewarmer.queuedCount, 0)
        let warmed = prewarmer.warmedCount
        XCTAssertLessThan(warmed, files.count, "the queue was dropped")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(prewarmer.warmedCount, warmed, "no work after stop returned")
    }

    func testRepeatedStopAndRestart() async throws {
        let renderer = try ANGLERenderer.make()
        let prewarmer = try realPrewarmer(renderer)
        for round in 0..<5 {
            prewarmer.request([preset("100-square.milk")], texturePaths: [])
            if round.isMultiple(of: 2) { try await waitUntil { prewarmer.warmedCount == 1 } }
            prewarmer.stop()
            XCTAssertFalse(prewarmer.isRunning, "round \(round)")
            XCTAssertFalse(prewarmer.hasGraphicsContext, "round \(round)")
        }
    }

    func testTheRendererWarmUpIsSuspendedAndResumed() async throws {
        let renderer = try ANGLERenderer.make()
        renderer.view.frame = CGRect(x: 0, y: 0, width: 64, height: 64)
        renderer.view.layoutIfNeeded()
        renderer.prewarmDelay = .zero
        let prewarmer = try realPrewarmer(renderer)
        renderer.prewarm([preset("110-per_pixel.milk")])
        try await waitUntil { renderer.prewarmedCount == 1 }
        XCTAssertEqual(renderer.prewarmedCount, 1)

        renderer.warmUp.suspendForPresentationLoss()
        XCTAssertFalse(prewarmer.isRunning)
        XCTAssertFalse(prewarmer.hasGraphicsContext)
        renderer.prewarm([preset("200-wave.milk")])   // requested in the background
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(renderer.prewarmedCount, 1, "nothing is warmed while suspended")
        XCTAssertFalse(prewarmer.isRunning)

        renderer.warmUp.resumeForPresentation()
        try await waitUntil { renderer.prewarmedCount == 2 }
        XCTAssertEqual(renderer.prewarmedCount, 2, "the request made while suspended is warmed after resume")
    }
}
