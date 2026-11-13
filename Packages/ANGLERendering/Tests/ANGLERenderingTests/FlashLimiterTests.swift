// FX-019-T09 (amends T104's tests): the strobe safety envelope on projectM frames, i.e. the GLSL port
// in CFlashLimiter on the iOS Simulator through ANGLE's Metal backend. Solid frames make the input
// levels exact; each frame's output is read back and measured with FlashSafety's independent
// `FlashAnalysis` per area and signal, and the GPU gain is compared with the Swift `FlashEnvelope`.
// Changed on purpose from T104 (FX-019 is stricter): no gray lift on a cut to black, rate 0.25/s,
// flash counting, the pass runs with Reduce flashing off too. The ≤ 2 ms cost is a device
// measurement (FX-019-T22); simulator results are never device evidence.
import XCTest
import CANGLE
import CFlashLimiter
import FlashSafety
import Rendering
@testable import ANGLERendering

@MainActor
final class FlashLimiterTests: XCTestCase {
    private static let testPresets = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Vendor/projectM/presets/tests")

    private var renderer: ANGLERenderer!
    private var limiter: OpaquePointer!
    private var size: (width: Int32, height: Int32) = (0, 0)

    override func setUp() async throws {
        renderer = try ANGLERenderer.make()
        renderer.view.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
        renderer.view.layoutIfNeeded()
        renderer.makeSurfaceCurrent()
        limiter = try XCTUnwrap(PMFlashLimiterCreate(PMANGLELoadProc, nil), "shaders compile and link")
        size = (Int32(renderer.currentSurfaceSize.width), Int32(renderer.currentSurfaceSize.height))
    }

    override func tearDown() async throws {
        renderer.makeSurfaceCurrent()
        PMFlashLimiterDestroy(limiter)
        renderer = nil
    }

    /// One solid frame of encoded color (r, g, b) through the limiter onto the surface; returns the
    /// gain the GPU applied.
    @discardableResult
    private func frame(_ r: Float, _ g: Float, _ b: Float, _ configuration: FlashEnvelopeConfiguration,
                       frameTime: Double = 1.0 / 60) -> Float {
        renderer.makeSurfaceCurrent()
        let framebuffer = PMFlashLimiterBegin(limiter, size.width, size.height)
        XCTAssertNotEqual(framebuffer, 0)
        PMANGLEClearFramebuffer(framebuffer, r, g, b)
        var parameters = configuration.limiterParameters(frameTime: frameTime)
        PMFlashLimiterFinish(limiter, 0, &parameters)
        return PMFlashLimiterLastGain(limiter)
    }

    private func output() -> [FlashLevels] {
        FlashColor.tileLevels(rgba: renderer.readPixels(), width: Int(size.width), height: Int(size.height), bottomRowFirst: true)
    }

    private static func levels(_ r: Float, _ g: Float, _ b: Float) -> FlashLevels {
        let lr = FlashColor.decodeSRGB(Double(r)), lg = FlashColor.decodeSRGB(Double(g)), lb = FlashColor.decodeSRGB(Double(b))
        return FlashLevels(luminance: FlashColor.relativeLuminance(red: lr, green: lg, blue: lb),
                           redness: FlashColor.redness(red: lr, green: lg, blue: lb))
    }

    func testTheFirstFrameIsShownAsItIs() {
        XCTAssertEqual(frame(1, 1, 1, .reduceFlashing), 1)
        XCTAssertEqual(output()[FlashZones.wholeFrame].luminance, 1, accuracy: 0.005)
    }

    /// T104 lifted a cut to black with gray; FX-019 only dims, so black stays black.
    func testACutToBlackStaysBlack() {
        frame(1, 1, 1, .reduceFlashing)
        frame(0, 0, 0, .reduceFlashing)
        XCTAssertEqual(output()[FlashZones.wholeFrame].luminance, 0, "never brighter than the input")
    }

    func testACutToWhiteRisesAtTheRate() {
        frame(0, 0, 0, .reduceFlashing, frameTime: 0.1)
        for n in 1...4 {
            let g = frame(1, 1, 1, .reduceFlashing, frameTime: 0.1)
            XCTAssertEqual(Double(g), 0.025 * Double(n), accuracy: 0.001, "frame \(n): 0.25/s × 0.1 s per frame")
            XCTAssertEqual(output()[FlashZones.wholeFrame].luminance, 0.025 * Double(n), accuracy: 0.003)
        }
    }

    /// The acceptance sequences (owner rule 7: three representative cases, 2 s each at 60 fps).
    /// "N Hz" is the alternation rate: N changes of the picture per second.
    func testSyntheticStrobesObeyTheEnvelope() {
        struct Case { let name: String; let color: (Float, Float, Float); let halfPeriod: Int; let configuration: FlashEnvelopeConfiguration }
        let cases = [
            Case(name: "white/black 60 Hz on", color: (1, 1, 1), halfPeriod: 1, configuration: .reduceFlashing),
            Case(name: "white/black 10 Hz off", color: (1, 1, 1), halfPeriod: 6, configuration: .alwaysOn),
            Case(name: "red/black 15 Hz on", color: (1, 0, 0), halfPeriod: 4, configuration: .reduceFlashing),
        ]
        var report = ["FX-019 projectM pass (ANGLE, simulator, \(size.width) × \(size.height)); worst transitions per 1 s window input → output, worst gain gap GPU vs Swift:"]
        for c in cases {
            PMFlashLimiterReset(limiter)
            let reference = FlashEnvelope()
            let dt = 1.0 / 60
            var inputs: [[FlashLevels]] = [], outputs: [[FlashLevels]] = []
            var worstGap: Float = 0
            for n in 0..<120 {
                let lit = (n / c.halfPeriod) % 2 == 0
                let (r, g, b) = lit ? c.color : (0, 0, 0)
                let gpu = frame(r, g, b, c.configuration, frameTime: dt)
                let input = [FlashLevels](repeating: Self.levels(r, g, b), count: FlashZones.count)
                let swift = input.withUnsafeBufferPointer { reference.gain(inputs: $0, frameTime: dt, configuration: c.configuration) }
                worstGap = max(worstGap, abs(gpu - swift))
                inputs.append(input)
                outputs.append(output())
            }
            XCTAssertLessThanOrEqual(worstGap, 0.01, "\(c.name): GPU gain follows the shared definition")
            let times = [Double](repeating: dt, count: outputs.count)
            var worstIn = 0, worstOut = 0
            for z in 0..<FlashZones.count {
                for s in FlashSignal.allCases {
                    let threshold = c.configuration.threshold(for: s)
                    let inReport = FlashAnalysis.analyze(inputs.map { $0[z][s] }, frameTimes: times, threshold: threshold)
                    let outReport = FlashAnalysis.analyze(outputs.map { $0[z][s] }, frameTimes: times, threshold: threshold)
                    worstIn = max(worstIn, inReport.maxTransitionsPerWindow)
                    worstOut = max(worstOut, outReport.maxTransitionsPerWindow)
                    if let rate = c.configuration.riseRatePerSecond {
                        XCTAssertLessThanOrEqual(outReport.maxRise, rate * dt + 0.004, "\(c.name) area \(z) \(s): rise rate (+ 8-bit rounding)")
                    }
                    for i in 0..<outputs.count {
                        XCTAssertLessThanOrEqual(outputs[i][z][s], inputs[i][z][s] + 0.004, "\(c.name) frame \(i): never brighter")
                    }
                }
            }
            XCTAssertLessThanOrEqual(worstOut, c.configuration.transitionBudget, c.name)
            report.append("\(c.name): \(worstIn) → \(worstOut) (limit \(c.configuration.transitionBudget)); gain gap \(String(format: "%.5f", worstGap))")
        }
        print(report.joined(separator: "\n"))
    }

    func testResetStartsOverFromTheNextFrame() {
        frame(0, 0, 0, .reduceFlashing)
        PMFlashLimiterReset(limiter)
        XCTAssertEqual(frame(1, 1, 1, .reduceFlashing), 1)
    }

    /// The renderer path: the pass runs with Reduce flashing off and on (FX-019-R7); toggling keeps
    /// the history (FX-019-R11).
    func testTheRendererAlwaysUsesThePassAndKeepsHistoryAcrossAToggle() async throws {
        let preset = Preset(id: "tests/001-line.milk", name: "001-line",
                            fileURL: Self.testPresets.appendingPathComponent("001-line.milk"))
        try await renderer.setPreset(preset)
        XCTAssertFalse(renderer.reduceFlashing)
        XCTAssertTrue(renderer.renderFrame(present: false))
        XCTAssertNotNil(renderer.flashLimiterGain, "the always-on cap runs with Reduce flashing off")
        // Strobe with the setting off until the gate holds a rise…
        var gain: Float = 1
        for n in 0..<7 { gain = try XCTUnwrap(renderer.limitedSolidFrame(n % 2 == 0 ? 1 : 0, 1.0 / 60)) }
        XCTAssertEqual(gain, 0.095, accuracy: 0.002, "the 7th transition is refused")
        // …then turn Reduce flashing on: the history is kept, so the next rise is still held.
        renderer.reduceFlashing = true
        renderer.limitedSolidFrame(0, 1.0 / 60)
        let after = try XCTUnwrap(renderer.limitedSolidFrame(1, 1.0 / 60))
        XCTAssertLessThan(after, 0.1)
        XCTAssertTrue(renderer.renderFrame(present: false))
        XCTAssertFalse(renderer.readPixels().isEmpty)
        XCTAssertEqual(ANGLERenderer.flashLimitPerSecond, 0.25)
    }
}
