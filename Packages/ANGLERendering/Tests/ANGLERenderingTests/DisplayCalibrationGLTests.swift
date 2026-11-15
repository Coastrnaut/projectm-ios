// DisplayCalibrationGLTests.swift — OUT-009-T06 (specs/268-out-009-output-color-calibration, contract C3): the display
// calibration in projectM's FX-019 output pass (CFlashLimiter's GLSL through ANGLE's Metal backend, iOS Simulator).
// * A solid encoded grey through the renderer's own pass becomes `DisplayCalibration.apply` of it per channel
//   (within one 8-bit step); the identity leaves it exactly as before.
// * A REC-001 capture of a calibrated projectM frame is the uncalibrated frame, while the frame left on the surface
//   (what the display shows) is its calibration.
// Simulator results are never device evidence (OUT-009-T14 is).
import XCTest
import Compositor
import Rendering
@testable import ANGLERendering

@MainActor
final class DisplayCalibrationGLTests: XCTestCase {
    private static let testPresets = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Vendor/projectM/presets/tests")
    private let calibration = DisplayCalibration(gamma: 1.5, red: 0.8, green: 1, blue: 1.2)

    private func renderer(width: CGFloat = 16, height: CGFloat = 16) throws -> ANGLERenderer {
        let renderer = try ANGLERenderer.make()
        renderer.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        renderer.view.layoutIfNeeded()
        return renderer
    }

    private func setCalibration(_ c: DisplayCalibration, on renderer: ANGLERenderer) throws {
        let receiver = try XCTUnwrap(renderer.view as? DisplayCalibrationReceiver)
        XCTAssertTrue(receiver.acceptsDisplayCalibration)
        receiver.displayCalibration = c
        XCTAssertEqual(renderer.displayCalibration, c)
    }

    /// The first pixel's RGB, encoded 0…1.
    private static func rgb(_ pixels: [UInt8], at i: Int = 0) -> SIMD3<Double> {
        SIMD3<Double>(Double(pixels[i * 4]) / 255, Double(pixels[i * 4 + 1]) / 255, Double(pixels[i * 4 + 2]) / 255)
    }

    func testASolidFrameFollowsTheTransferFunctionAndTheIdentityIsUnchanged() throws {
        let renderer = try renderer()
        let grey: Float = 0.4
        let gain = try XCTUnwrap(renderer.limitedSolidFrame(grey, 1.0 / 60))
        XCTAssertEqual(gain, 1, accuracy: 1e-3, "a single steady frame is not limited")
        let plain = Self.rgb(renderer.readPixels())
        try setCalibration(calibration, on: renderer)
        renderer.limitedSolidFrame(grey, 1.0 / 60)
        let calibrated = Self.rgb(renderer.readPixels())
        let expected: SIMD3<Double> = calibration.apply(encoded: plain)
        for c in 0..<3 { XCTAssertEqual(calibrated[c], expected[c], accuracy: 1.5 / 255, "channel \(c)") }
        XCTAssertLessThan(calibrated.x, calibrated.y, "red trimmed")
        XCTAssertGreaterThan(calibrated.y, plain.y + 0.05, "gamma 1.5 lifts the grey")
        try setCalibration(.identity, on: renderer)
        renderer.limitedSolidFrame(grey, 1.0 / 60)
        XCTAssertEqual(Self.rgb(renderer.readPixels()), plain, "the identity is the FX-019 output exactly")
    }

    func testACaptureIsUncalibratedWhileTheShownFrameIsCalibrated() async throws {
        let renderer = try renderer()
        let preset = Preset(id: "tests/001-line.milk", name: "001-line",
                            fileURL: Self.testPresets.appendingPathComponent("001-line.milk"))
        try await renderer.setPreset(preset)
        try setCalibration(calibration, on: renderer)
        var captured: ANGLECapturedFrame?
        renderer.captureNextFrame { (frame: ANGLECapturedFrame?) in captured = frame }
        XCTAssertTrue(renderer.renderFrame(present: false))
        let frame = try XCTUnwrap(captured)
        let shown: [UInt8] = renderer.readPixels()
        XCTAssertEqual(frame.rgbaBottomUp.count, shown.count)
        var differing = 0
        for i in 0..<(shown.count / 4) {
            let content = Self.rgb(frame.rgbaBottomUp, at: i), display = Self.rgb(shown, at: i)
            let expected: SIMD3<Double> = calibration.apply(encoded: content)
            for c in 0..<3 { XCTAssertEqual(display[c], expected[c], accuracy: 2.5 / 255, "pixel \(i) channel \(c)") }
            if content != display { differing += 1 }
        }
        XCTAssertGreaterThan(differing, 0, "the display's frame differs from the captured content")
    }
}
