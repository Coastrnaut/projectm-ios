// QA-011 main-thread stall (projectM patch 5, docs/projectm-patches.md): custom shapes, the darken
// centre and looped waveforms now draw as triangle lists and closed line strips instead of
// GL_TRIANGLE_FAN and GL_LINE_LOOP, which ANGLE's Metal backend emulated with a GPU wait on the render
// thread. This checks with the real engine on ANGLE (iOS Simulator) that a preset with filled,
// outlined and textured shapes (several fan draws per frame), the darken centre and a circle wave
// still draws them. The preset is written here; none is a third-party file. Simulator results are not
// device evidence (Constitution X).
//
// Set PM_SHAPE_DUMP (TEST_RUNNER_PM_SHAPE_DUMP for xcodebuild) to a file path to write the picture's
// RGBA bytes there, for a byte comparison between two engine builds.
import XCTest
import Rendering
@testable import ANGLERendering

@MainActor
final class CustomShapeDrawTests: XCTestCase {
    private static let width = 96
    private static let height = 96

    /// Shape 0: a red-centred, blue-rimmed hexagon in the middle with a thick white outline. Shape 1:
    /// two textured squares near the top-left corner. A circle wave (mode 0, a loop), the darken
    /// centre, no decay, warp or zoom, so each frame shows only what was drawn on it.
    private let preset = Data("""
    MILKDROP_PRESET_VERSION=201
    PSVERSION=2
    PSVERSION_WARP=2
    PSVERSION_COMP=2
    [preset00]
    fDecay=0.000000
    zoom=1.000000
    rot=0.000000
    warp=0.000000
    fWarpScale=1.000000
    bDarkenCenter=1
    nWaveMode=0
    fWaveAlpha=1.0
    fWaveScale=1.0
    wave_r=0.0
    wave_g=1.0
    wave_b=0.0
    bMaximizeWaveColor=0
    bAdditiveWaves=0
    shapecode_0_enabled=1
    shapecode_0_sides=6
    shapecode_0_additive=0
    shapecode_0_thickOutline=1
    shapecode_0_textured=0
    shapecode_0_num_inst=1
    shapecode_0_x=0.500000
    shapecode_0_y=0.500000
    shapecode_0_rad=0.300000
    shapecode_0_ang=0.000000
    shapecode_0_r=1.000000
    shapecode_0_g=0.000000
    shapecode_0_b=0.000000
    shapecode_0_a=1.000000
    shapecode_0_r2=0.000000
    shapecode_0_g2=0.000000
    shapecode_0_b2=1.000000
    shapecode_0_a2=1.000000
    shapecode_0_border_r=1.000000
    shapecode_0_border_g=1.000000
    shapecode_0_border_b=1.000000
    shapecode_0_border_a=1.000000
    shapecode_1_enabled=1
    shapecode_1_sides=4
    shapecode_1_textured=1
    shapecode_1_num_inst=2
    shapecode_1_x=0.150000
    shapecode_1_y=0.850000
    shapecode_1_rad=0.080000
    shapecode_1_r=1.000000
    shapecode_1_g=1.000000
    shapecode_1_b=0.000000
    shapecode_1_a=1.000000
    shapecode_1_r2=1.000000
    shapecode_1_g2=1.000000
    shapecode_1_b2=0.000000
    shapecode_1_a2=1.000000
    shapecode_1_border_a=0.000000
    shape_1_per_frame1=x = 0.15 + 0.1*instance;

    """.utf8)

    private func frames(_ count: Int) -> [[Float]] {
        (0..<count).map { frame in
            (0..<735).flatMap { index -> [Float] in
                let value = Float(0.3 * sin(Double(frame * 735 + index) * 2 * .pi * 220 / 44_100))
                return [value, value]
            }
        }
    }

    private func pixel(_ bytes: [UInt8], _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let i = (y * Self.width + x) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }

    func testFilledOutlinedAndTexturedShapesAndALoopWaveStillDraw() async throws {
        let renderer = try ANGLERenderer.make()
        let drawing = try XCTUnwrap(renderer.presetThumbnails)
        let result = await drawing.draw(preset, width: Self.width, height: Self.height, frames: frames(4), timeout: .seconds(120))
        guard case .pixels(let pixels) = result else { return XCTFail("\(result)") }
        let bytes = [UInt8](pixels)
        XCTAssertEqual(bytes.count, Self.width * Self.height * 4)

        if let path = ProcessInfo.processInfo.environment["PM_SHAPE_DUMP"], !path.isEmpty {
            try pixels.write(to: URL(fileURLWithPath: path))
        }

        // The hexagon's fill: red at the centre (darkened slightly by the darken centre), blending to
        // blue towards the rim. Halfway out it has both.
        let centre = pixel(bytes, Self.width / 2, Self.height / 2)
        XCTAssertGreaterThan(centre.r, 150, "red fill at the centre: \(centre)")
        XCTAssertLessThan(centre.g, 60, "no green at the centre: \(centre)")
        let halfway = pixel(bytes, Self.width / 2 + Self.width / 10, Self.height / 2)
        XCTAssertGreaterThan(halfway.r, 40, "fill halfway out: \(halfway)")
        XCTAssertGreaterThan(halfway.b, 40, "fill halfway out: \(halfway)")

        // The fill covers the hexagon: about 4.5 % of the picture on the iOS 27.2 simulator (2026-11-19).
        let filled = stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0] > 30 && bytes[$0 + 1] < 60 && bytes[$0 + 2] > 0 }.count
        let share = Double(filled) / Double(Self.width * Self.height)
        XCTAssertGreaterThan(share, 0.025, "the hexagon is filled (\(share))")
        XCTAssertLessThan(share, 0.12, "only the hexagon is filled (\(share))")

        // The thick white outline and the green circle wave leave pixels that only they can draw.
        let white = stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0] > 200 && bytes[$0 + 1] > 200 && bytes[$0 + 2] > 200 }.count
        XCTAssertGreaterThan(white, 10, "the outline is drawn (\(white) white pixels)")
        let green = stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0 + 1] > 120 && bytes[$0] < 80 && bytes[$0 + 2] < 80 }.count
        XCTAssertGreaterThan(green, Self.width / 2, "the circle wave is drawn (\(green) green pixels)")

        // The corners stay black apart from the textured squares at the top left.
        let corner = pixel(bytes, Self.width - 2, Self.height - 2)
        XCTAssertLessThan(corner.r + corner.g + corner.b, 30, "bottom-right corner: \(corner)")
    }
}
