// WaterfallFlashTests.swift — VIS-020-T04 (VIS-020-R6, R7; S4; contract C3): the flash estimate's cells are the exact
// mean light of the history texels they show; full-level input stays at or below 0.8 of full white (ACC-012); bursts
// alternating with silence stay within FX-019's envelope in all 17 areas with Reduce flashing on and off (FlashSafety's
// independent `FlashAnalysis`). Pure Swift (Linux too).
import FlashSafety
import XCTest
@testable import VisualEffects
@testable import VisualGenerators

final class WaterfallFlashTests: XCTestCase {
    private static func stops(_ palette: VisualPalette) -> [LinearColor] {
        (0..<16).map { (k: Int) -> LinearColor in palette.color(bar: k, of: 16).clamped }
    }

    /// What the generator does per frame: advance, update the written rows' cell sums, load the 64 samples.
    private static func step(_ h: SpectrumWaterfallHistory, _ cells: WaterfallFlashCells, _ areas: NoiseFieldFlashAreas,
                             stops: [LinearColor], bands: [Float], t: UInt64) {
        bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in h.advance(bands: b, timeNanoseconds: t, reduceMotion: false) }
        stops.withUnsafeBufferPointer { (s: UnsafeBufferPointer<LinearColor>) -> Void in
            h.drainPending { (ring: Int) -> Void in cells.update(ring: ring, history: h, stops: s.baseAddress!) }
        }
        areas.loadWaterfall(cells, history: h, brightness: Float(NoiseFieldConfiguration.maximumBrightness))
    }

    func testCellsAreTheExactMeanOfTheirTexels() {
        let h = SpectrumWaterfallHistory(), cells = WaterfallFlashCells(), areas = NoiseFieldFlashAreas()
        let stops = Self.stops(.spectrum)
        for f in 0..<900 {   // 30 s at 30 fps of a moving, uneven spectrum
            let bands: [Float] = (0..<32).map { (k: Int) -> Float in 0.5 + 0.5 * sin(Float(k) * 0.7 + Float(f) * 0.05) }
            Self.step(h, cells, areas, stops: stops, bands: bands, t: UInt64(f) * 1_000_000_000 / 30)
        }
        XCTAssertEqual(h.rowsWritten, 255)
        for (row, column) in [(0, 0), (0, 7), (3, 4), (7, 2)] {
            var r: Float = 0, g: Float = 0, b: Float = 0
            for age in (row * 64)..<((row + 1) * 64) {
                let ring: Int = (h.newestRow + SpectrumWaterfallHistory.rows - age) % SpectrumWaterfallHistory.rows
                for x in (column * 32)..<((column + 1) * 32) {
                    let c: LinearColor = stops.withUnsafeBufferPointer { (s: UnsafeBufferPointer<LinearColor>) -> LinearColor in
                        SpectrumWaterfallHistory.color(Float(h.levels[ring * 256 + x]) / 255, stops: s.baseAddress!)
                    }
                    r += c.red; g += c.green; b += c.blue
                }
            }
            let cell: LinearColor = cells.cellColor(row: row, column: column, history: h)
            XCTAssertEqual(cell.red, r / 2048, accuracy: 1e-5, "cell \(row), \(column)")
            XCTAssertEqual(cell.green, g / 2048, accuracy: 1e-5)
            XCTAssertEqual(cell.blue, b / 2048, accuracy: 1e-5)
            XCTAssertEqual(areas.color(row * 8 + column).green, cell.green * 0.8, accuracy: 1e-6, "× brightness 0.8")
        }
        XCTAssertEqual(cells.cellColor(row: 7, column: 0, history: h).red, 0, "rows not yet written are black")
    }

    func testFullLevelStaysBelowFullWhite() {
        let h = SpectrumWaterfallHistory(), cells = WaterfallFlashCells(), areas = NoiseFieldFlashAreas()
        let stops = Self.stops(.mono)
        for f in 0...600 { Self.step(h, cells, areas, stops: stops, bands: [Float](repeating: 5, count: 64), t: UInt64(f) * 100_000_000) }
        for k in 0..<NoiseFieldFlashAreas.sampleCount {
            let c: LinearColor = areas.color(k)
            XCTAssertLessThanOrEqual(max(c.red, c.green, c.blue), 0.8 + 1e-6)
        }
        XCTAssertGreaterThan(areas.color(0).green, 0.79, "full level is shown at the cap")
    }

    private func worstTransitions<T: FrameLuminanceTransfer>(transfer: T, enabled: Bool) -> Int {
        let configuration = FlashEnvelopeConfiguration.forReduceFlashing(enabled)
        let envelope = FlashEnvelope()
        let h = SpectrumWaterfallHistory(), cells = WaterfallFlashCells(), areas = NoiseFieldFlashAreas()
        let stops = Self.stops(.mono)
        stops.withUnsafeBufferPointer { (s: UnsafeBufferPointer<LinearColor>) -> Void in cells.updateAll(history: h, stops: s.baseAddress!) }
        let dt = 1.0 / 60
        var shown: [[FlashLevels]] = []
        for f in 0..<240 {   // full-level bursts alternating with silence every 0.1 s for 4 s
            let level: Float = (f / 6) % 2 == 0 ? 1 : 0
            Self.step(h, cells, areas, stops: stops, bands: [Float](repeating: level, count: 64), t: UInt64(f) * 1_000_000_000 / 60)
            let gain: Float = areas.gain(envelope: envelope, transfer: transfer, frameTime: dt, configuration: configuration)
            var out = [FlashLevels](repeating: .zero, count: FlashZones.count)
            out.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<FlashLevels>) -> Void in
                areas.levels(gain: gain, transfer: transfer, into: b)
            }
            shown.append(out)
        }
        let times = [Double](repeating: dt, count: shown.count)
        var worst = 0
        for z in 0..<FlashZones.count {
            for s in FlashSignal.allCases {
                let out = FlashAnalysis.analyze(shown.map { (l: [FlashLevels]) -> Double in l[z][s] }, frameTimes: times,
                                                threshold: configuration.threshold(for: s))
                worst = max(worst, out.maxTransitionsPerWindow)
                if let rate = configuration.riseRatePerSecond {
                    XCTAssertLessThanOrEqual(out.maxRise, rate * dt + 1e-9, "area \(z) \(s)")
                }
            }
        }
        XCTAssertGreaterThan(shown.map { (l: [FlashLevels]) -> Double in l[0].luminance }.max() ?? 0, 0.005, "something is shown")
        return worst
    }

    func testBurstsObeyTheEnvelope() {
        let glow = BloomLuminanceModel(parameters: BloomParameters(enabled: true, intensity: 1, radius: 0.06, threshold: 0.1, knee: 1))
        var report = ["VIS-020 waterfall (cell means, mono, bursts every 0.1 s for 4 s): worst transitions per window:"]
        for enabled in [true, false] {
            let budget = FlashEnvelopeConfiguration.forReduceFlashing(enabled).transitionBudget
            let plain = worstTransitions(transfer: IdentityLuminanceTransfer(), enabled: enabled)
            let glowing = worstTransitions(transfer: glow, enabled: enabled)
            XCTAssertLessThanOrEqual(plain, budget, "Reduce flashing \(enabled)")
            XCTAssertLessThanOrEqual(glowing, budget, "Reduce flashing \(enabled), glow")
            report.append("Reduce flashing \(enabled ? "on" : "off"): \(plain), with glow \(glowing) (limit \(budget))")
        }
        print(report.joined(separator: "\n"))
    }
}
