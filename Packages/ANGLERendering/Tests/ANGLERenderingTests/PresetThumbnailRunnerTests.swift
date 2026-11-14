// PRE-001-T09: the thumbnail runner with the real engine on the iOS Simulator (research PRE-001-D1,
// contract C4). The preset is written here; none is a third-party file. Simulator results are not
// device evidence (Constitution X).
import XCTest
import Rendering
@testable import ANGLERendering

@MainActor
final class PresetThumbnailRunnerTests: XCTestCase {
    /// A bright, audio-reactive preset: a thick wave and a coloured composite.
    private let preset = Data("""
    MILKDROP_PRESET_VERSION=201
    PSVERSION=2
    PSVERSION_WARP=2
    PSVERSION_COMP=2
    [preset00]
    fDecay=0.980000
    zoom=1.020000
    wave_r=1.0
    wave_g=0.7
    wave_b=0.2
    nWaveMode=2
    fWaveAlpha=1.0
    fWaveScale=2.0
    bMaximizeWaveColor=1
    per_frame_1=wave_r = 0.6 + 0.4*sin(time*1.3);
    comp_1=`shader_body
    comp_2=`{
    comp_3=`ret = tex2D(sampler_main, uv).xyz + float3(0.15, 0.05, 0.25)*(1 - uv.y);
    comp_4=`}

    """.utf8)

    private func frames(_ count: Int) -> [[Float]] {
        (0..<count).map { frame in
            (0..<735).flatMap { index -> [Float] in
                let value = Float(0.6 * sin(Double(frame * 735 + index) * 2 * .pi * 110 / 44_100))
                return [value, value]
            }
        }
    }

    /// One drawing only: on the simulator each costs seconds (shader compiles; the first engine in a
    /// process also initialises ANGLE), so the suspended case reuses the same renderer.
    func testAPresetDrawsAPictureOfTheRequestedSizeAndASuspendedRunnerDrawsNothing() async throws {
        let renderer = try ANGLERenderer.make()
        let drawing = try XCTUnwrap(renderer.presetThumbnails)
        let result = await drawing.draw(preset, width: 128, height: 72, frames: frames(3), timeout: .seconds(30))
        guard case .pixels(let pixels) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(pixels.count, 128 * 72 * 4)
        let bytes = [UInt8](pixels)
        let first = Array(bytes[0..<4])
        let varied = stride(from: 0, to: bytes.count, by: 4).contains { Array(bytes[$0..<$0 + 4]) != first }
        XCTAssertTrue(varied, "not a single colour")
        let lit = stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0] > 8 || bytes[$0 + 1] > 8 || bytes[$0 + 2] > 8 }.count
        XCTAssertGreaterThan(lit, 128 * 72 / 4, "the picture is mostly lit")

        let runner = renderer.thumbnailRunner
        runner.setSuspended(true)   // PERF-011
        let suspended = await runner.draw(preset, width: 16, height: 9, frames: frames(1), timeout: .seconds(30))
        guard case .unavailable = suspended else { return XCTFail("\(suspended)") }
        XCTAssertEqual(runner.startedCount, 1, "nothing started while suspended")
        XCTAssertFalse(runner.isBusy)
    }
}
