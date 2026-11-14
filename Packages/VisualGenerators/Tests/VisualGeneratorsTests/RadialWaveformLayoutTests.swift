// RadialWaveformLayoutTests.swift — VIS-005-T03: the roadmap acceptance "Ring closes without seam and reacts to
// signed input samples" on the CPU geometry (VIS-005-S1 to S3; R2 to R7, R14). Runs everywhere, Linux included.
import XCTest
@testable import VisualGenerators

final class RadialWaveformLayoutTests: XCTestCase {
    /// Sines whose period does not divide N = 1,024 (454.6 and 200.5 samples), ending at three phases each.
    private let seamCases: [(frequency: Double, end: Int64)] = [(97, 60_000), (97, 60_311), (97, 61_007),
                                                                (220, 60_000), (220, 60_137), (220, 60_401)]

    func testRingClosesWithoutSeam() {
        for c in seamCases {
            let layout = RadialWaveformLayout()
            layout.layout(RadialFixture.sine(c.frequency, endingAt: c.end))
            XCTAssertEqual(layout.pointCount, RadialWaveformLayout.windowSamples)
            XCTAssertEqual(layout.segmentCount, RadialWaveformLayout.windowSamples, "the closing segment is drawn")
            let ratio = layout.seamRatio()
            XCTAssertLessThanOrEqual(ratio, 1.5, "\(c): max neighbour distance (closing included) / median")
            let d = layout.neighbourDistances()
            let median = d.sorted()[d.count / 2]
            XCTAssertLessThanOrEqual(d[d.count - 1], 1.5 * median, "\(c): the closing segment is an ordinary step")
        }
    }

    /// The negative control: without the taper the same windows jump at the join.
    func testWithoutTheTaperTheRingHasASeam() {
        var worst = 0.0
        for c in seamCases {
            let layout = RadialWaveformLayout()
            layout.taperEnabled = false
            layout.layout(RadialFixture.sine(c.frequency, endingAt: c.end))
            XCTAssertGreaterThan(layout.seamRatio(), 1.5, "\(c): the raw window fails the seam rule")
            worst = max(worst, layout.seamRatio())
        }
        XCTAssertGreaterThan(worst, 5, "the raw window jumps by several segment lengths at the join")
    }

    func testSignedSamplesPushOutAndPullIn() {
        let r0 = RadialWaveformConfiguration.defaultBaseRadius
        let up = RadialWaveformLayout()
        up.layout(RadialFixture.constant(0.5))
        XCTAssertTrue(up.radii.allSatisfy { (r: Double) -> Bool in r > r0 }, "DC +0.5: every radius > R₀")
        let down = RadialWaveformLayout()
        down.layout(RadialFixture.constant(-0.5))
        XCTAssertTrue(down.radii.allSatisfy { (r: Double) -> Bool in r < r0 }, "DC −0.5: every radius < R₀")
        // The taper keeps a constant exactly constant (its weights sum to 1).
        for j in 0..<RadialWaveformLayout.windowSamples { XCTAssertEqual(up.normalizedSample(j), 1, accuracy: 1e-12) }
        let quiet = RadialWaveformLayout()
        quiet.layout(RadialFixture.silence())
        XCTAssertTrue(quiet.radii.allSatisfy { (r: Double) -> Bool in abs(r - r0) <= 1e-12 }, "silence: a perfect circle at R₀")
        let big = 0.5 * 192.0
        for j in 0..<quiet.pointCount {
            let p = quiet.point(j)
            let distance = ((p.x - 128) * (p.x - 128) + (p.y - 96) * (p.y - 96)).squareRoot()
            XCTAssertEqual(distance, r0 * big, accuracy: 1e-9)
        }
        XCTAssertGreaterThan(quiet.vertexCount(), 0, "silence draws the base circle")
        // A sine moves the ring both ways.
        let wave = RadialWaveformLayout()
        wave.layout(RadialFixture.sine(220))
        XCTAssertGreaterThan(wave.radii.max() ?? 0, r0 + 0.9 * RadialWaveformConfiguration.defaultAmplitude)
        XCTAssertLessThan(wave.radii.min() ?? 1, r0 - 0.9 * RadialWaveformConfiguration.defaultAmplitude)
    }

    func testSteadyFixtureIsIdenticalFrameToFrame() {
        let layout = RadialWaveformLayout()
        let history = RadialFixture.sine(97)
        layout.layout(history)
        let first = (0..<layout.pointCount).map { (j: Int) -> Double in layout.point(j).x + 1_000 * layout.point(j).y }
        for _ in 0..<10 {
            layout.layout(history)
            XCTAssertEqual((0..<layout.pointCount).map { (j: Int) -> Double in layout.point(j).x + 1_000 * layout.point(j).y }, first)
        }
        let other = RadialWaveformLayout()
        other.layout(history)
        XCTAssertEqual((0..<other.pointCount).map { (j: Int) -> Double in other.point(j).x + 1_000 * other.point(j).y }, first,
                       "a fresh layout gives the same points")
    }

    func testOldestAtTheTopClockwise() {
        let layout = RadialWaveformLayout()
        layout.layout(RadialFixture.silence(), width: 200, height: 200)
        let r = RadialWaveformConfiguration.defaultBaseRadius * 100
        let top = layout.point(0), right = layout.point(RadialWaveformLayout.windowSamples / 4)
        XCTAssertEqual(top.x, 100, accuracy: 1e-9); XCTAssertEqual(top.y, 100 - r, accuracy: 1e-9)
        XCTAssertEqual(right.x, 100 + r, accuracy: 1e-9); XCTAssertEqual(right.y, 100, accuracy: 1e-9)
    }

    func testGeometryStaysInsideTheInscribedCircleAtAnySize() {
        let configuration = RadialWaveformConfiguration(baseRadius: 0.75, amplitude: 0.25)
        for (w, h) in [(390, 844), (844, 390), (3, 2), (1, 1)] {
            let layout = RadialWaveformLayout(configuration: configuration)
            layout.layout(RadialFixture.sine(220, amplitude: 1), width: w, height: h)
            let big = Double(min(w, h)) / 2
            for j in 0..<layout.pointCount {
                let p = layout.point(j)
                let dx = p.x - Double(w) / 2, dy = p.y - Double(h) / 2
                XCTAssertLessThanOrEqual((dx * dx + dy * dy).squareRoot(), big + 1e-9, "\(w)x\(h)")
            }
            XCTAssertGreaterThan(layout.vertexCount(), 0)
        }
        let empty = RadialWaveformLayout()
        empty.layout(RadialFixture.sine(220), width: 0, height: 100)
        XCTAssertEqual(empty.vertexCount(), 0)
    }

    func testNonFiniteAndMissingSamplesReadZero() {
        var history = RadialFixture.sine(220)
        for i in stride(from: 0, to: history.count, by: 7) { history[i] = i % 2 == 0 ? .nan : .infinity }
        let layout = RadialWaveformLayout()
        layout.layout(history)
        for j in 0..<RadialWaveformLayout.windowSamples {
            XCTAssertTrue(layout.normalizedSample(j).isFinite && abs(layout.normalizedSample(j)) <= 1)
        }
        let fresh = RadialWaveformLayout()
        fresh.layout([Float](repeating: .nan, count: 4_096))
        XCTAssertEqual(fresh.lastPeak, 0, "non-finite only reads as silence")
        // Fewer samples than the window: the missing older ones read 0 (the base circle there).
        let short = Array(RadialFixture.constant(0.5).suffix(100))
        let partial = RadialWaveformLayout()
        partial.layout(short)
        for j in 0..<(RadialWaveformLayout.windowSamples - 100) {
            XCTAssertEqual(partial.radius(j), RadialWaveformConfiguration.defaultBaseRadius, accuracy: 1e-12)
        }
        XCTAssertGreaterThan(partial.radius(RadialWaveformLayout.windowSamples - 50), RadialWaveformConfiguration.defaultBaseRadius)
    }

    func testColorsFollowThePaletteOldestToNewest() {
        let layout = RadialWaveformLayout(configuration: RadialWaveformConfiguration(palette: .colorBlindSafe))
        layout.layout(RadialFixture.sine(97))
        let n = RadialWaveformLayout.windowSamples
        XCTAssertEqual(layout.flashRegionCount, n)
        for k in [0, n / 2, n - 1] {
            XCTAssertEqual(layout.flashRegionColor(k), VisualPalette.colorBlindSafe.color(bar: k, of: n))
        }
    }

    func testConfigurationClampsAndStorageIsStable() {
        let wild = RadialWaveformConfiguration(baseRadius: 9, amplitude: -1, lineThickness: .nan)
        XCTAssertEqual(wild.baseRadius, 0.75)
        XCTAssertEqual(wild.amplitude, 0)
        XCTAssertEqual(wild.lineThickness, RadialWaveformConfiguration.defaultLineThickness)
        XCTAssertEqual(RadialWaveformConfiguration(baseRadius: .infinity).baseRadius, RadialWaveformConfiguration.defaultBaseRadius)
        let layout = RadialWaveformLayout()
        let before = layout.storageAddresses
        for f in 0..<120 { layout.layout(f % 2 == 0 ? RadialFixture.sine(97, endingAt: 60_000 + Int64(f) * 735) : RadialFixture.silence()) }
        XCTAssertEqual(layout.storageAddresses, before, "no reallocation per frame")
    }
}
