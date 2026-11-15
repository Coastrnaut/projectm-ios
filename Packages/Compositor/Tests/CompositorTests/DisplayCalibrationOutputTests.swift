// DisplayCalibrationOutputTests.swift — OUT-009-T04 (specs/268-out-009-output-color-calibration, contract C2;
// OUT-009-S1, S2, S4): the display calibration in the compositor's real screen pass, on the app's screen format
// (`bgra8Unorm_srgb`, read back as encoded bytes). A few representative colours, not a sweep (owner rule 7):
// * the identity draws exactly the bytes of the plain pass (`cmp_output`, no calibrated frame);
// * a calibration (gamma 1.5, trims 0.8 / 1 / 1.2) gives each channel `DisplayCalibration.apply` of the
//   uncalibrated encoded value within two 8-bit steps (the input is itself quantized);
// * `encodeOutput` (a recording's pass) of the calibrated frame is the uncalibrated frame.
// Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
@testable import Compositor
import Metal
import XCTest

final class DisplayCalibrationOutputTests: XCTestCase {
    private static let frameNanoseconds: UInt64 = 16_666_667
    private static let colors: [Pixel] = [Pixel(0.18, 0.18, 0.18, 1), Pixel(0.6, 0.3, 0.05, 1), Pixel(0.02, 0.5, 0.9, 1),
                                          Pixel(1, 1, 1, 1), Pixel(0, 0, 0, 1)]
    private let calibration = DisplayCalibration(gamma: 1.5, red: 0.8, green: 1, blue: 1.2)

    /// One 4 × 4 frame of `color` through a fresh compositor at `calibration`; returns the screen's first pixel
    /// (encoded, 0…1) and the same frame's recording output.
    private func frame(_ color: Pixel, _ calibration: DisplayCalibration) throws -> (screen: SIMD4<Float>, recording: SIMD4<Float>, calibrated: Int) {
        let passes = try OutputPassRig()
        let rig: GPURig = passes.rig
        let compositor = try Compositor(device: rig.device, layers: [StillLayer("c", color: color)])
        compositor.displayCalibration = calibration
        let screen: MTLTexture = try passes.target(.bgra8Unorm_srgb, width: 4, height: 4)
        let recording: MTLTexture = try passes.target(.bgra8Unorm_srgb, width: 4, height: 4)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        XCTAssertTrue(compositor.composite(into: screen, commandBuffer: commands, presentationTimeNanoseconds: 1_000_000_000,
                                           contentScale: 2, reduceFlashing: false, audio: .empty))
        XCTAssertTrue(compositor.encodeOutput(into: recording, commandBuffer: commands))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertNil(commands.error)
        return (passes.readRaw(screen)[0], passes.readRaw(recording)[0], compositor.calibratedFrames)
    }

    func testTheIdentityIsThePlainPassBitForBit() throws {
        for color in Self.colors {
            let plain = try frame(color, .identity)
            XCTAssertEqual(plain.calibrated, 0, "the identity never uses the calibrated pass")
            XCTAssertEqual(plain.screen, plain.recording, "screen = recording")
        }
    }

    func testTheCalibratedScreenMatchesTheTransferFunctionAndTheRecordingDoesNot() throws {
        for color in Self.colors {
            let plain = try frame(color, .identity)
            let calibrated = try frame(color, calibration)
            XCTAssertEqual(calibrated.calibrated, 1)
            XCTAssertEqual(calibrated.recording, plain.screen, "the recording output is uncalibrated (content)")
            for c in 0..<3 {
                let expected: Double = calibration.apply(encoded: Double(plain.screen[c]), channel: c)
                XCTAssertEqual(Double(calibrated.screen[c]), expected, accuracy: 2.0 / 255, "\(color) channel \(c)")
            }
            XCTAssertEqual(calibrated.screen.w, plain.screen.w, "alpha unchanged")
        }
        // The calibration really changes a mid grey (not a no-op): brighter mid-tones, red below green below blue.
        let grey = try frame(Self.colors[0], calibration).screen
        let plainGrey = try frame(Self.colors[0], .identity).screen
        XCTAssertGreaterThan(grey.y, plainGrey.y + 0.05, "gamma 1.5 lifts the mid grey")
        XCTAssertLessThan(grey.x, grey.y, "red trimmed")
        XCTAssertGreaterThan(grey.z, grey.y, "blue raised")
    }
}
#endif
