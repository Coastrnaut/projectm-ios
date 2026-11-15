// ANGLEOutputPacingTests.swift — OUT-013-T08 (specs/281-out-013-frame-pacing, contract C3): projectM's frames in flight
// on ANGLE. A slow output is a fence that does not signal (DEBUG `holdFences`); ticks are driven by calling
// `pacedTick()` directly (the display link's path), so no wall clock is involved.
import CANGLE
import FrameTiming
import QuartzCore
import XCTest
@testable import ANGLERendering

@MainActor
final class ANGLEOutputPacingTests: XCTestCase {
    private func makeLaidOut() throws -> ANGLERenderer {
        let renderer = try ANGLERenderer.make()
        renderer.view.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
        renderer.view.layoutIfNeeded()
        return renderer
    }

    /// A slow output: two frames go out, every further tick is dropped and counted without waiting, and nothing grows.
    func testASlowOutputDropsTicksInsteadOfQueueing() throws {
        let renderer = try makeLaidOut()
        renderer.frameFences.holdFences = true
        XCTAssertTrue(renderer.pacedTick())
        XCTAssertTrue(renderer.pacedTick())
        for _ in 0..<30 { XCTAssertFalse(renderer.pacedTick(), "full: the tick is dropped") }
        let counts: OutputPacingCounts = renderer.outputPacing.counts
        XCTAssertEqual(counts.begun, 2)
        XCTAssertEqual(counts.droppedInFlight, 30)
        XCTAssertEqual(counts.inFlight, 2)
        XCTAssertEqual(counts.maxInFlight, 2)
        XCTAssertEqual(renderer.frameFences.outstanding, 2, "the fence ring never grows past the bound")
        XCTAssertEqual(renderer.presentedFrameCount, 2)

        renderer.frameFences.holdFences = false   // the output caught up
        renderer.makeSurfaceCurrent()
        PMANGLEFinish()
        XCTAssertTrue(renderer.pacedTick(), "both fences retire at the next tick; a frame goes out")
        XCTAssertEqual(renderer.outputPacing.counts.completed, 2)
        XCTAssertEqual(renderer.outputPacing.counts.inFlight, 1)
    }

    /// A fast output: every tick presents and frames in flight stay within the bound.
    func testAFastOutputPresentsEveryTick() throws {
        let renderer = try makeLaidOut()
        for _ in 0..<20 {
            XCTAssertTrue(renderer.pacedTick())
            renderer.makeSurfaceCurrent()
            PMANGLEFinish()   // the GPU keeps up
        }
        let counts: OutputPacingCounts = renderer.outputPacing.counts
        XCTAssertEqual(counts.begun, 20)
        XCTAssertEqual(counts.dropped, 0)
        XCTAssertLessThanOrEqual(counts.maxInFlight, 2)
    }

    /// Presentation loss releases every fence: nothing of a released surface stays in flight.
    func testSuspensionDrainsTheFences() throws {
        let renderer = try makeLaidOut()
        renderer.frameFences.holdFences = true
        renderer.pacedTick()
        renderer.pacedTick()
        renderer.suspendForPresentationLoss()
        XCTAssertEqual(renderer.frameFences.outstanding, 0)
        XCTAssertEqual(renderer.outputPacing.counts.inFlight, 0)
        renderer.resumeForPresentation()
    }

    /// OUT-013-R6: the layer states its drawable policy.
    func testTheLayerStatesItsDrawablePolicy() throws {
        let renderer = try makeLaidOut()
        let layer = try XCTUnwrap(renderer.view.layer as? CAMetalLayer)
        XCTAssertEqual(layer.maximumDrawableCount, 3)
        XCTAssertTrue(layer.allowsNextDrawableTimeout)
    }
}
