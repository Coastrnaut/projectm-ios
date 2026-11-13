// OUT-001-T11 (OUT-001-S4, S5): a compositor visual moved to an external display composites at the
// display's size, and its flash limiting carries on across the move.
// * A 1920 × 1080 output gets a 1920 × 1080 picture; pictures are created once per size and never
//   per frame at a steady size (CMP-001-R9).
// * A strobe that starts at a phone-like size and continues at 1920 × 1080 (the visual's view moved
//   to the external window) stays within the envelope's transition limit, and the GPU gain matches a
//   `FlashEnvelope` fed the whole series without a reset (FX-019-R11): the move gives the strobe no
//   fresh budget. Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import FlashSafety
import Metal
import XCTest

final class ExternalOutputSizeTests: XCTestCase {
    private static let frameNanoseconds: UInt64 = 16_666_667
    private let blue = Pixel(0, 0, 1, 1)

    func testAnExternalOutputIsCompositedAtItsOwnSizeWithoutPerFrameAllocation() throws {
        let rig = try GPURig()
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("blue", color: blue)])
        let phone = try rig.output(.bgra8Unorm, width: 390, height: 844)
        let television = try rig.output(.bgra8Unorm, width: 1920, height: 1080)
        for t in 1...3 { try rig.frame(compositor, into: phone, time: UInt64(t) * Self.frameNanoseconds) }
        let atPhone = compositor.pictureAllocations
        try rig.frame(compositor, into: television, time: 4 * Self.frameNanoseconds)
        XCTAssertEqual(compositor.pictureAllocations, 2 * atPhone, "pictures created once more, for 1920 × 1080")
        for t in 5...34 { try rig.frame(compositor, into: television, time: UInt64(t) * Self.frameNanoseconds) }
        XCTAssertEqual(compositor.pictureAllocations, 2 * atPhone, "no picture created over 30 frames at a steady size")
        let pixels = try rig.read(television)
        XCTAssertEqual(pixels.count, 1920 * 1080)
        assertAll(pixels, equal: blue, "the whole 1920 × 1080 output is the composited scene")
    }

    private func strobeAcrossAMove(reduceFlashing: Bool) throws {
        let rig = try GPURig()
        let compositor = try Compositor(device: rig.device, layers: [StrobeLayer()])
        let phone = try rig.output(width: 78, height: 169)
        let television = try rig.output(width: 1920, height: 1080)
        let reference = FlashEnvelope()
        let configuration = FlashEnvelopeConfiguration.forReduceFlashing(reduceFlashing)
        var shown: [Double] = []
        var frameTimes: [Double] = []
        var worstGainError: Float = 0
        var gainAfterMove: Float = 1
        let moveAt = 40
        for i in 0..<120 {
            let output = i < moveAt ? phone : television
            try rig.frame(compositor, into: output, time: 1_000_000_000 + UInt64(i) * Self.frameNanoseconds, reduceFlashing: reduceFlashing)
            let dt = i == 0 ? 0 : Double(Self.frameNanoseconds) / 1e9
            let level = i % 2 == 0 ? 1.0 : 0.0
            let inputs = [FlashLevels](repeating: FlashLevels(luminance: level, redness: 0), count: FlashZones.count)
            let expected = inputs.withUnsafeBufferPointer { reference.gain(inputs: $0, frameTime: dt, configuration: configuration) }
            let gain = compositor.lastFlashGain
            if level > 0 { worstGainError = max(worstGainError, abs(gain - expected)) }
            if i == moveAt { gainAfterMove = gain }
            shown.append(level * Double(gain))   // a uniform frame: luminance scales with the gain
            frameTimes.append(dt)
        }
        let report = FlashAnalysis.analyze(shown, frameTimes: frameTimes, threshold: configuration.luminanceThreshold)
        print("OUT-001 strobe across a move (Reduce flashing \(reduceFlashing)): worst transitions per window \(report.maxTransitionsPerWindow), gain after the move \(gainAfterMove), worst GPU-CPU gain difference \(worstGainError)")
        XCTAssertLessThanOrEqual(report.maxTransitionsPerWindow, reduceFlashing ? 4 : 6, "transitions per 1 s window across the move")
        XCTAssertLessThanOrEqual(worstGainError, 1e-4, "the GPU gain follows one uninterrupted envelope: no reset at the move")
        XCTAssertLessThan(gainAfterMove, 0.5, "the first white frame on the external display is still held")
    }

    func testAStrobeKeepsItsBudgetAcrossTheMoveWithReduceFlashing() throws {
        try strobeAcrossAMove(reduceFlashing: true)
    }

    func testAStrobeKeepsItsBudgetAcrossTheMoveWithTheAlwaysOnCap() throws {
        try strobeAcrossAMove(reduceFlashing: false)
    }
}
#endif
