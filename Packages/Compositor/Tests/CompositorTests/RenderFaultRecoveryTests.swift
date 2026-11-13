// PERF-014-T05 (US1: layer faults) and T12 (US2: GPU faults, the black back-off, the placeholder state
// and the flash check). GPU tests at 64 × 64 (32 × 32 for the long runs); skipped without a Metal
// device. Faults are injected through the compositor's DEBUG `faultInjection` (creation or the status
// check fails; no faulty shader) or by test layers that fail. Ticks are counted, never wall time.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import FlashSafety
import Metal
import XCTest

/// Counts calls; fails `prepare` or `render` while asked to.
private final class CountingLayer: LayerSource {
    let layerName: String
    let fallback: LayerFallback
    var color: Pixel
    var prepareError: LayerSourceError?
    var renderError: LayerSourceError?
    private(set) var prepareTicks: [UInt64] = []
    private(set) var renderCalls = 0
    /// The compositor's tick, set by the test before each frame.
    var tick: UInt64 = 0

    init(_ name: String, color: Pixel, fallback: LayerFallback = .transparent) {
        layerName = name
        self.color = color
        self.fallback = fallback
    }

    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {
        prepareTicks.append(tick)
        if let prepareError { throw prepareError }
    }

    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) {
        renderCalls += 1
        if let renderError { throw renderError }
        SolidLayer.clear(picture, to: color, commandBuffer: commandBuffer)
    }
}

final class RenderFaultRecoveryTests: XCTestCase {
    private let blue = Pixel(0, 0, 1, 1)
    private let white = Pixel(1, 1, 1, 1)
    /// The empty composite: transparent black (shown as black on screen).
    private let black = Pixel(0, 0, 0, 0)
    private let frameNanoseconds: UInt64 = 16_666_667

    /// `count` frames committed without waiting (the last one waited for); returns the composites' results.
    @discardableResult
    private func frames(_ count: Int, _ compositor: Compositor, _ rig: GPURig, _ output: MTLTexture,
                        layer: CountingLayer? = nil) throws -> [Bool] {
        var results: [Bool] = []
        var last: MTLCommandBuffer?
        for _ in 0..<count {
            layer?.tick = compositor.frameTicks + 1
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            results.append(compositor.composite(into: output, commandBuffer: commands,
                                                presentationTimeNanoseconds: (compositor.frameTicks + 1) * frameNanoseconds,
                                                contentScale: 1, reduceFlashing: false, audio: .empty))
            commands.commit()
            last = commands
        }
        last?.waitUntilCompleted()
        return results
    }

    /// One frame, waited for (so its status is final before the next tick reads it).
    private func waitedFrame(_ compositor: Compositor, _ rig: GPURig, _ output: MTLTexture) throws {
        try rig.frame(compositor, into: output, time: (compositor.frameTicks + 1) * frameNanoseconds, scale: 1)
    }

    // MARK: - US1: layer faults (T05)

    func testInjectedPrepareFailureBacksOffThenGivesUpAndOtherLayersKeepDrawing() throws {
        let rig = try GPURig()
        let photo = CountingLayer("photo", color: Pixel(0.5, 0, 0, 0.5))
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("blue", color: blue), photo])
        compositor.faultInjection.failingPrepare = ["photo"]
        let output = try rig.output(width: 32, height: 32)
        try frames(1, compositor, rig, output, layer: photo)
        XCTAssertEqual(compositor.health.lastReason, .layerPrepareFailed, "S1: the reason at the fault's tick")
        XCTAssertEqual(compositor.health.lastFaultTick, 1)
        XCTAssertEqual(compositor.health.faultCount, 1)
        XCTAssertEqual(compositor.health.state, .recovering)
        assertAll(try rig.read(output), equal: blue, "the other layer keeps drawing")
        let allocations = compositor.pictureAllocations

        let preparationsBefore = compositor.layerPreparations
        try frames(1 + 450 + 1_000 - 1, compositor, rig, output, layer: photo)
        XCTAssertEqual(compositor.frameTicks, 1_451, "S2: one tick per frame while faulted")
        // The injected failure stops before the layer's own prepare, so count the compositor's calls.
        XCTAssertEqual(compositor.layerPreparations - preparationsBefore, 4, "S3: four retries, no more in the next 1,000 frames")
        XCTAssertEqual(compositor.health.faultCount, 5, "the first fault and four failed retries")
        XCTAssertEqual(compositor.health.state, .degraded, "the photo gave up; the blue layer still shows")
        XCTAssertEqual(compositor.pictureAllocations, allocations, "R12: no picture created while faulted at a steady size")
        assertAll(try rig.read(output), equal: blue, "still drawing")
        XCTAssertEqual(compositor.outcome(ofLayer: 1), .unavailable(.resourceUnavailable("injected pipeline failure")))
        XCTAssertTrue(photo.prepareTicks.isEmpty, "the layer itself was never asked while injected")

        compositor.faultInjection = RenderFaultInjection()
        compositor.resetRenderHealth()   // R6: the user resumes the visual
        try frames(1, compositor, rig, output, layer: photo)
        XCTAssertEqual(compositor.outcome(ofLayer: 1), .rendered, "a reset retries at once")
        XCTAssertEqual(compositor.health.state, .healthy)
        XCTAssertEqual(compositor.health.recoveries, 1)
        assertAll(try rig.read(output), equal: Pixel(0.5, 0, 0.5, 1), "the photo is back over blue")
    }

    func testPrepareRetriesHappenOnlyAtBackOffTicksAndRecoverWhenTheFaultClears() throws {
        let rig = try GPURig()
        let photo = CountingLayer("photo", color: Pixel(0.5, 0, 0, 0.5))
        photo.prepareError = .resourceUnavailable("pipeline")
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("blue", color: blue), photo])
        let output = try rig.output(width: 32, height: 32)
        try frames(100, compositor, rig, output, layer: photo)
        XCTAssertEqual(photo.prepareTicks, [1, 31, 91], "prepared at the first size, then at +30 and +90 only")
        XCTAssertEqual(photo.renderCalls, 0)
        photo.prepareError = nil   // the fault clears before the next retry (tick 211)
        try frames(111, compositor, rig, output, layer: photo)
        XCTAssertEqual(photo.prepareTicks, [1, 31, 91, 211], "S4: the next retry succeeds")
        XCTAssertEqual(photo.renderCalls, 1, "rendered from the retry's tick on")
        XCTAssertEqual(compositor.health.state, .healthy)
        XCTAssertEqual(compositor.health.recoveries, 1)
        XCTAssertEqual(compositor.health.faultCount, 3)
        XCTAssertEqual(compositor.health.lastReason, .layerPrepareFailed)
        assertAll(try rig.read(output), equal: Pixel(0.5, 0, 0.5, 1), "the photo is shown again")
    }

    func testMissingPicturesAreAFaultAndComeBackWhenCleared() throws {
        let rig = try GPURig()
        let video = CountingLayer("video", color: Pixel(0.5, 0, 0, 0.5))
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("blue", color: blue), video])
        compositor.faultInjection.missingPictures = ["video"]
        let output = try rig.output(width: 32, height: 32)
        try frames(30, compositor, rig, output, layer: video)
        XCTAssertEqual(compositor.health.lastReason, .missingTexture)
        XCTAssertEqual(compositor.health.faultCount, 1)
        assertAll(try rig.read(output), equal: blue, "the layer without pictures is skipped")
        compositor.faultInjection.missingPictures = []
        try frames(1, compositor, rig, output, layer: video)   // tick 31: the retry creates its pictures
        XCTAssertEqual(video.prepareTicks, [31], "prepared once its pictures exist")
        XCTAssertEqual(compositor.outcome(ofLayer: 1), .rendered)
        XCTAssertEqual(compositor.health.recoveries, 1)
    }

    func testASeriousRenderErrorHoldsTheLayerUntilItsRetry() throws {
        let rig = try GPURig()
        let layer = CountingLayer("spectrum", color: Pixel(0.5, 0, 0, 0.5), fallback: .lastGoodFrame)
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("blue", color: blue), layer])
        let output = try rig.output(width: 32, height: 32)
        try frames(2, compositor, rig, output, layer: layer)
        layer.renderError = .engineFailure("lost")
        try frames(29, compositor, rig, output, layer: layer)   // ticks 3…31: fails at 3, held until 33
        XCTAssertEqual(layer.renderCalls, 3, "R4: no per-frame retry while held")
        XCTAssertEqual(compositor.health.lastReason, .layerRenderFailed)
        XCTAssertEqual(compositor.health.faultCount, 1)
        XCTAssertEqual(compositor.outcome(ofLayer: 1), .fallbackLastGood(.engineFailure("lost")))
        assertAll(try rig.read(output), equal: Pixel(0.5, 0, 0.5, 1), "the last good picture stays (no luminance change)")
        layer.renderError = nil
        try frames(2, compositor, rig, output, layer: layer)    // tick 33: the retry renders
        XCTAssertEqual(layer.renderCalls, 4)
        XCTAssertEqual(compositor.health.state, .healthy)
        XCTAssertEqual(compositor.health.recoveries, 1)
    }

    func testRoutineErrorsAndTheInjectedRenderFailure() throws {
        let rig = try GPURig()
        let loading = CountingLayer("photo", color: Pixel(0.5, 0, 0, 0.5))
        loading.renderError = .notReady
        let spectrum = CountingLayer("spectrum", color: Pixel(0, 0.5, 0, 0.5))
        let compositor = try Compositor(device: rig.device, layers: [loading, spectrum])
        compositor.faultInjection.failingRender = ["spectrum"]
        let output = try rig.output(width: 32, height: 32)
        try frames(10, compositor, rig, output)
        XCTAssertEqual(loading.renderCalls, 10, "D4: not ready is asked again every frame and is not a fault")
        XCTAssertEqual(spectrum.renderCalls, 0, "the injection fails before the layer draws")
        XCTAssertEqual(compositor.health.faultCount, 1, "only the injected render failure counts")
        XCTAssertEqual(compositor.health.lastReason, .layerRenderFailed)
        XCTAssertEqual(compositor.outcome(ofLayer: 1), .fallbackTransparent(.engineFailure("injected")))
    }

    // MARK: - US2: GPU faults and the placeholder state (T12)

    func testInjectedGPUFaultsAreCoalescedDrawBlackAndRecover() throws {
        for reason in [RenderFaultReason.gpuTimeout, .gpuPageFault, .gpuNotPermitted] {
            let rig = try GPURig()
            let compositor = try Compositor(device: rig.device, layers: [SolidLayer("white", color: white)])
            let output = try rig.output()
            try waitedFrame(compositor, rig, output)
            compositor.faultInjection.gpuFault = reason
            try frames(3, compositor, rig, output)            // three buffers in flight, all "failing"
            try waitedFrame(compositor, rig, output)          // tick 5 reads them all
            XCTAssertEqual(compositor.health.lastReason, reason, "\(reason)")
            XCTAssertEqual(compositor.health.faultCount, 1, "\(reason): three in-flight errors count once")
            XCTAssertEqual(compositor.health.state, .recovering)
            assertAll(try rig.read(output), equal: black, "\(reason): black while backing off (no layer renders)")
            XCTAssertEqual(compositor.outcome(ofLayer: 0), .notRendered)

            compositor.faultInjection.gpuFault = nil
            while compositor.frameTicks < 2 + 30 { try waitedFrame(compositor, rig, output) }   // the retry at tick 32
            try waitedFrame(compositor, rig, output)           // reads the retry's buffer: a success
            XCTAssertEqual(compositor.health.state, .healthy, "\(reason): S4")
            XCTAssertEqual(compositor.health.recoveries, 1)
            assertAll(try rig.read(output), equal: white, "\(reason): drawn again")
        }
    }

    func testAPersistentGPUFaultEndsInThePlaceholderStateUntilAReset() throws {
        let rig = try GPURig()
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("white", color: white)])
        compositor.recoveryPolicy = RenderRecoveryPolicy(firstDelayTicks: 2, maxRetries: 2)
        compositor.faultInjection.gpuFault = .gpuError
        let output = try rig.output(width: 32, height: 32)
        for _ in 0..<40 { try waitedFrame(compositor, rig, output) }
        XCTAssertEqual(compositor.health.state, .placeholder)
        XCTAssertEqual(compositor.health.faultCount, 3, "the fault and two failed retries")
        XCTAssertEqual(compositor.frameTicks, 40, "S2: ticks keep advancing")
        assertAll(try rig.read(output), equal: black, "the visual stays black under the placeholder")

        compositor.faultInjection.gpuFault = nil
        for _ in 0..<5 { try waitedFrame(compositor, rig, output) }
        XCTAssertEqual(compositor.health.state, .placeholder, "no automatic return after giving up (Clarifications Q5)")
        compositor.resetRenderHealth()
        try waitedFrame(compositor, rig, output)
        try waitedFrame(compositor, rig, output)
        XCTAssertEqual(compositor.health.state, .healthy)
        XCTAssertEqual(compositor.health.recoveries, 1)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered, "back after the reset")
        // The short test policy retried every few ticks, so the composite flash guard (R16) dims the
        // return until its 1 s window clears: the safety net working. Full brightness after that.
        for _ in 0..<70 { try waitedFrame(compositor, rig, output) }
        assertAll(try rig.read(output), equal: white, "back at full brightness once the envelope allows it")
    }

    func testAMissingCompositeIsRetriedOnlyAtItsBackOff() throws {
        let rig = try GPURig()
        let layer = CountingLayer("photo", color: blue)
        let compositor = try Compositor(device: rig.device, layers: [layer])
        compositor.faultInjection.missingPictures = ["composite"]
        let output = try rig.output(width: 32, height: 32)
        let results = try frames(31, compositor, rig, output, layer: layer)
        XCTAssertEqual(results.filter { $0 }.count, 0, "nothing encoded without a composite")
        XCTAssertEqual(compositor.frameTicks, 31, "ticks advance although nothing is encoded")
        XCTAssertEqual(compositor.health.lastReason, .missingTexture)
        XCTAssertEqual(compositor.health.faultCount, 2, "tick 1 and the failed retry at tick 31 (none in between)")
        compositor.faultInjection.missingPictures = []
        try frames(60, compositor, rig, output, layer: layer)   // the retry at tick 91 creates it
        try waitedFrame(compositor, rig, output)
        XCTAssertEqual(compositor.health.state, .healthy)
        assertAll(try rig.read(output), equal: blue, "drawn once the composite exists")
    }

    func testGPUErrorCodesMapToReasons() {
        XCTAssertEqual(Compositor.renderFaultReason(for: MTLCommandBufferError(.timeout)), .gpuTimeout)
        XCTAssertEqual(Compositor.renderFaultReason(for: MTLCommandBufferError(.pageFault)), .gpuPageFault)
        XCTAssertEqual(Compositor.renderFaultReason(for: MTLCommandBufferError(.notPermitted)), .gpuNotPermitted)
        XCTAssertEqual(Compositor.renderFaultReason(for: MTLCommandBufferError(.outOfMemory)), .gpuOutOfMemory)
        XCTAssertEqual(Compositor.renderFaultReason(for: MTLCommandBufferError(.internal)), .gpuError)
        XCTAssertEqual(Compositor.renderFaultReason(for: nil), .gpuError)
    }

    /// S5: a white layer switching to its transparent fallback and back (after its retry) gives at most
    /// one luminance transition in any 1 s window of the read-back output (FlashAnalysis, 0.10 threshold).
    func testAFallbackSwitchStaysWithinTheFlashEnvelope() throws {
        let rig = try GPURig()
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("white", color: white)])
        let output = try rig.output(width: 16, height: 16)
        var luminance: [Double] = []
        func record() throws {
            try waitedFrame(compositor, rig, output)
            let pixels = try rig.read(output)
            let mean = pixels.reduce(0.0) { (sum: Double, p: Pixel) -> Double in
                sum + FlashColor.relativeLuminance(red: Double(p.x), green: Double(p.y), blue: Double(p.z))
            } / Double(pixels.count)
            luminance.append(mean)
        }
        for _ in 0..<20 { try record() }
        compositor.faultInjection.failingRender = ["white"]   // tick 21: fault; retry at 51 fails; next at 111
        for _ in 0..<50 { try record() }
        compositor.faultInjection.failingRender = []
        for _ in 0..<60 { try record() }                      // tick 111: back
        XCTAssertEqual(compositor.health.recoveries, 1)
        let report = FlashAnalysis.analyze(luminance, frameTimes: Array(repeating: 1.0 / 60, count: luminance.count), threshold: 0.10)
        XCTAssertEqual(report.transitions, 2, "one switch to the fallback and one back")
        XCTAssertLessThanOrEqual(report.maxTransitionsPerWindow, 1, "S5: never two switches inside one second")
    }
}

#endif
