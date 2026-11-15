// GridWarpGLTests.swift — OUT-008-T06 (specs/309-out-008-grid-warp, contract C3): the grid warp in projectM's FX-019
// output step (CFlashLimiter's GLSL through ANGLE's Metal backend, iOS Simulator). A REC-001 capture is the plain content
// of the frame (the unwarped redraw of the same output step), and the frame left on the surface is what the display
// shows, so one rendered preset frame gives both sides:
// * the identity mesh draws exactly the captured content (byte for byte);
// * a half-size affine mesh shows the content bilinearly scaled into the middle (≥ 99 % of pixels within 5/255) and
//   opaque black around it;
// * `.none` adds no redraw and guides add white lines.
// Simulator results are never device evidence (OUT-008-T15 is).
import XCTest
import Compositor
import Rendering
@testable import ANGLERendering

@MainActor
final class GridWarpGLTests: XCTestCase {
    private static let testPresets = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Vendor/projectM/presets/tests")
    /// Points; the surface has the screen's scale, so pixel sizes are read from the captured frame.
    private static let points = CGSize(width: 16, height: 12)
    private var width = 0
    private var height = 0

    /// One preset frame through the warp: (content captured for REC-001, what the surface shows).
    private func frame(_ mesh: OutputWarpMesh) async throws -> (content: [UInt8], shown: [UInt8]) {
        let renderer = try ANGLERenderer.make()
        renderer.view.frame = CGRect(origin: .zero, size: Self.points)
        renderer.view.layoutIfNeeded()
        let preset = Preset(id: "tests/001-line.milk", name: "001-line",
                            fileURL: Self.testPresets.appendingPathComponent("001-line.milk"))
        try await renderer.setPreset(preset)
        let receiver = try XCTUnwrap(renderer.view as? OutputWarpReceiver)
        XCTAssertTrue(receiver.acceptsOutputWarp)
        receiver.outputWarp = mesh
        XCTAssertEqual(renderer.outputWarp, mesh)
        var captured: ANGLECapturedFrame?
        renderer.captureNextFrame { (frame: ANGLECapturedFrame?) in captured = frame }
        XCTAssertTrue(renderer.renderFrame(present: false))
        let content = try XCTUnwrap(captured)
        width = content.width
        height = content.height
        XCTAssertEqual(content.rgbaBottomUp.count, width * height * 4)
        return (content.rgbaBottomUp, renderer.readPixels())
    }

    func testTheIdentityMeshShowsTheContentExactly() async throws {
        for side in [3, 9] {
            let f = try await frame(.identity(columns: side, rows: side))
            XCTAssertEqual(f.shown.count, f.content.count)
            XCTAssertEqual(f.shown, f.content, "identity \(side) × \(side) is the plain output step byte for byte")
            XCTAssertTrue(f.content.contains { (b: UInt8) -> Bool in b > 0 && b < 255 }, "the frame has a picture")
        }
    }

    func testAHalfSizeMeshScalesTheContentIntoTheMiddle() async throws {
        let points: [SIMD2<Float>] = OutputWarpMesh.identity(columns: 3, rows: 3).points.map { (p: SIMD2<Float>) -> SIMD2<Float> in
            SIMD2<Float>(0.25, 0.25) + 0.5 * p
        }
        let f = try await frame(OutputWarpMesh(columns: 3, rows: 3, points: points, showsGuides: false))
        var inside = 0, close = 0
        for y in 0..<height {
            for x in 0..<width {
                let px = (Double(x) + 0.5) / Double(width), py = (Double(y) + 0.5) / Double(height)
                let k: Int = (y * width + x) * 4
                let shown: [UInt8] = Array(f.shown[k..<(k + 3)])
                let margin: Double = 1.0 / Double(height)
                if px < 0.25 - margin || px > 0.75 + margin || py < 0.25 - margin || py > 0.75 + margin {
                    XCTAssertEqual(shown, [0, 0, 0], "outside the picture is black (\(x), \(y))")
                    continue
                }
                guard px > 0.25 + margin, px < 0.75 - margin, py > 0.25 + margin, py < 0.75 - margin else { continue }
                inside += 1
                let want: [Double] = bilinear(f.content, u: (px - 0.25) * 2, v: (py - 0.25) * 2)
                let worst: Double = (0..<3).map { (c: Int) -> Double in abs(Double(shown[c]) - want[c]) }.max() ?? 0
                if worst <= 5 { close += 1 }
            }
        }
        XCTAssertGreaterThan(inside, 200)
        XCTAssertGreaterThanOrEqual(Double(close), 0.99 * Double(inside), "\(close) of \(inside) within 5/255")
    }

    func testGuidesAddWhiteLines() async throws {
        let plain = try await frame(.identity(columns: 3, rows: 3))
        let guided = try await frame(.identity(columns: 3, rows: 3, showsGuides: true))
        var white = 0
        for k in stride(from: 0, to: guided.shown.count, by: 4) where guided.shown[k] == 255 && guided.shown[k + 1] == 255
            && guided.shown[k + 2] == 255 && plain.shown[k..<(k + 3)] != guided.shown[k..<(k + 3)] { white += 1 }
        XCTAssertGreaterThan(white, width + height, "the grid lines are drawn")
    }

    /// Bilinear sampling of RGBA8 rows (any vertical order; the mesh above is symmetric), clamped at the edges.
    private func bilinear(_ pixels: [UInt8], u: Double, v: Double) -> [Double] {
        let fx: Double = u * Double(width) - 0.5, fy: Double = v * Double(height) - 0.5
        let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
        let ax: Double = fx - Double(x0), ay: Double = fy - Double(y0)
        func texel(_ x: Int, _ y: Int, _ c: Int) -> Double {
            Double(pixels[(min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)) * 4 + c])
        }
        return (0..<3).map { (c: Int) -> Double in
            let top: Double = texel(x0, y0, c) * (1 - ax) + texel(x0 + 1, y0, c) * ax
            let bottom: Double = texel(x0, y0 + 1, c) * (1 - ax) + texel(x0 + 1, y0 + 1, c) * ax
            return top * (1 - ay) + bottom * ay
        }
    }
}
