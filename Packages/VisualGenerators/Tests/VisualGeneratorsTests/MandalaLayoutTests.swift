// MandalaLayoutTests.swift — VIS-007-T03, T05: the mandala's CPU geometry (VIS-007-R2 to R7, R14; S1 to S3,
// S5). The roadmap acceptance: the same bands and time at N = 4 and N = 8 double the sectors and the vertex
// count exactly, every sector equals sector 0 rotated by 2πk/N within 1e-9, and a repeat is bit-identical.
// Plus mirror symmetry, the silence base shape, band groups, rotation cap and Reduce Motion, sizes and
// storage. The clock is injected. Pure Swift (runs in the Linux shape).
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import XCTest
@testable import VisualGenerators

final class MandalaLayoutTests: XCTestCase {
    private let width = 390, height = 844
    /// 48 bands: low 0.6, mid 0.5, high 0.4.
    private let bands: [Float] = [Float](repeating: 0.6, count: 16) + [Float](repeating: 0.5, count: 16)
        + [Float](repeating: 0.4, count: 16)
    private let time: UInt64 = 7_250_000_000

    private func layout(_ configuration: MandalaConfiguration, bands input: [Float]? = nil, at t: UInt64? = nil,
                        width w: Int? = nil, height h: Int? = nil) -> MandalaLayout {
        let layout = MandalaLayout(configuration: configuration)
        (input ?? bands).withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
            layout.layout(bands: b, atNanoseconds: t ?? time, width: w ?? width, height: h ?? height)
        }
        return layout
    }

    private func vertexCount(_ layout: MandalaLayout) -> Int {
        let out = UnsafeMutablePointer<SpectrumVertex>.allocate(capacity: MandalaLayout.maximumVertexCount)
        defer { out.deallocate() }
        return layout.tessellate(into: out, capacity: MandalaLayout.maximumVertexCount, gain: 1)
    }

    /// Largest distance between sector k's corners and sector 0's rotated clockwise by 2πk/N about the centre.
    private func worstRotationError(_ layout: MandalaLayout) -> Double {
        let cx = Double(width) / 2, cy = Double(height) / 2
        let n = layout.sectorCount, per = layout.regionsPerSector
        var worst = 0.0
        for k in 1..<n {
            let theta = 2 * Double.pi * Double(k) / Double(n)
            for r in 0..<per {
                let base = layout.quad(r), copy = layout.quad(k * per + r)
                for c in 0..<4 {
                    let x = base[2 * c] - cx, y = base[2 * c + 1] - cy
                    let ex = cx + x * cos(theta) - y * sin(theta), ey = cy + y * cos(theta) + x * sin(theta)
                    worst = max(worst, abs(ex - copy[2 * c]), abs(ey - copy[2 * c + 1]))
                }
            }
        }
        return worst
    }

    private func allCorners(_ layout: MandalaLayout) -> [Double] {
        (0..<layout.regionCount).flatMap { (k: Int) -> [Double] in layout.quad(k) }
    }

    // MARK: - Acceptance (VIS-007-S1)

    func testSymmetryFourToEightDoublesSectorsDeterministically() {
        for mirror in [false, true] {
            let four = layout(MandalaConfiguration(symmetry: 4, mirror: mirror))
            let eight = layout(MandalaConfiguration(symmetry: 8, mirror: mirror))
            XCTAssertEqual(four.sectorCount, 4)
            XCTAssertEqual(eight.sectorCount, 8, "sector copies go from 4 to 8")
            XCTAssertEqual(eight.regionsPerSector, four.regionsPerSector, "each sector holds the same shape")
            XCTAssertEqual(eight.regionCount, 2 * four.regionCount)
            let v4 = vertexCount(four), v8 = vertexCount(eight)
            XCTAssertGreaterThan(v4, 0)
            XCTAssertEqual(v8, 2 * v4, "the vertex count doubles exactly (mirror \(mirror))")
            XCTAssertLessThanOrEqual(worstRotationError(four), 1e-9)
            XCTAssertLessThanOrEqual(worstRotationError(eight), 1e-9)
            // Repeated runs (fresh layouts and the same layout again) are bit-identical.
            XCTAssertEqual(allCorners(layout(MandalaConfiguration(symmetry: 8, mirror: mirror))), allCorners(eight))
            let again = layout(MandalaConfiguration(symmetry: 4, mirror: mirror))
            bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
                again.layout(bands: b, atNanoseconds: time, width: width, height: height)
            }
            XCTAssertEqual(allCorners(again), allCorners(four))
            print("VIS-007 acceptance (mirror \(mirror)): N=4 → \(four.sectorCount) sectors, \(v4) vertices; N=8 → "
                  + "\(eight.sectorCount) sectors, \(v8) vertices; worst rotation error "
                  + "\(max(worstRotationError(four), worstRotationError(eight))) px")
        }
    }

    func testEverySupportedSymmetryIsExact() {
        for n in MandalaConfiguration.supportedSymmetries {
            let l = layout(MandalaConfiguration(symmetry: n, mirror: n % 2 == 0, petalStyle: .round))
            XCTAssertEqual(l.sectorCount, n)
            XCTAssertLessThanOrEqual(worstRotationError(l), 1e-9, "N = \(n)")
        }
    }

    // MARK: - Mirror (VIS-007-S2)

    func testMirrorReflectsEachSectorAcrossItsCentreLine() {
        let plain = layout(MandalaConfiguration(symmetry: 6, mirror: false))
        let mirrored = layout(MandalaConfiguration(symmetry: 6, mirror: true))
        XCTAssertEqual(mirrored.sectorCount, 6, "Mirror keeps the sector count")
        XCTAssertEqual(mirrored.regionsPerSector, 2 * plain.regionsPerSector)
        XCTAssertEqual(vertexCount(mirrored), 2 * vertexCount(plain))
        let cx = Double(width) / 2, cy = Double(height) / 2
        let steps = MandalaLayout.stepsPerPetal, per = mirrored.regionsPerSector
        var worst = 0.0
        for k in 0..<6 {
            // The sector's centre line, clockwise from the top: ψ + 2πk/N + π/N.
            let line = mirrored.angle + 2 * Double.pi * Double(k) / 6 + Double.pi / 6
            let ux = sin(line), uy = -cos(line)
            for i in 0..<steps {
                let first = mirrored.quad(k * per + i), second = mirrored.quad(k * per + steps + i)
                // Reflection swaps left and right: corner c of the first ↔ corner 3 − c of the second.
                for c in 0..<4 {
                    let x = first[2 * c] - cx, y = first[2 * c + 1] - cy
                    let along = x * ux + y * uy
                    let rx = cx + 2 * along * ux - x, ry = cy + 2 * along * uy - y
                    worst = max(worst, abs(rx - second[2 * (3 - c)]), abs(ry - second[2 * (3 - c) + 1]))
                }
            }
        }
        XCTAssertLessThanOrEqual(worst, 1e-9, "second half = first half reflected")
        // Without Mirror a curled petal is not symmetric about its centre line (cyclic, not dihedral).
        XCTAssertGreaterThan(plain.groups.high, 0)
    }

    // MARK: - Silence (VIS-007-S3) and band groups (R2)

    func testSilenceGivesTheBaseShape() {
        for input in [[Float](), [Float](repeating: 0, count: 64)] {
            let l = layout(MandalaConfiguration(symmetry: 6), bands: input, at: 0)
            XCTAssertEqual(l.groups, .silence)
            XCTAssertEqual(l.alpha, MandalaConfiguration.baseAlpha, accuracy: 1e-12)
            XCTAssertEqual(l.angle, 0, "time 0 is the anchor")
            let big = Double(min(width, height)) / 2, cx = Double(width) / 2, cy = Double(height) / 2
            let sigma = Double.pi / 6
            // The tip (outer corners of the last step) at 0.35 of half the shorter side, on the centre line.
            let last = l.quad(MandalaLayout.stepsPerPetal - 1)
            for c in [1, 2] {
                let r = hypot(last[2 * c] - cx, last[2 * c + 1] - cy)
                XCTAssertEqual(r / big, MandalaConfiguration.baseLength, accuracy: 1e-12)
            }
            // The widest step (t = 0.5, the start of step 6) spans ±0.2σ about the centre line: no curl.
            let mid = l.quad(6)
            let left = atan2(mid[0] - cx, -(mid[1] - cy)), right = atan2(mid[6] - cx, -(mid[7] - cy))
            XCTAssertEqual(left, sigma - 0.2 * sigma, accuracy: 1e-12)
            XCTAssertEqual(right, sigma + 0.2 * sigma, accuracy: 1e-12)
            XCTAssertGreaterThan(vertexCount(l), 0, "silence still draws the base shape")
        }
    }

    func testBandGroupsClampAndSplit() {
        let odd: [Float] = [2, -1, .nan, 0.5, 0.5, 0.5, 1, 1, 1, 0.25]   // 10 bands: groups of 3, 3, 4
        let g = odd.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> MandalaBandGroups in MandalaBandGroups.from(b) }
        XCTAssertEqual(g.low, 1.0 / 3, accuracy: 1e-12, "2 → 1, −1 → 0, NaN → 0")
        XCTAssertEqual(g.mid, 0.5, accuracy: 1e-12)
        XCTAssertEqual(g.high, 3.25 / 4, accuracy: 1e-12, "the remainder goes to high")
        let two: [Float] = [1, 1]
        let h = two.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> MandalaBandGroups in MandalaBandGroups.from(b) }
        XCTAssertEqual(h, MandalaBandGroups(low: 0, mid: 0, high: 1), "fewer than 3 bands: missing groups read 0")
        let loud = layout(MandalaConfiguration(), bands: [Float](repeating: 1, count: 32))
        XCTAssertEqual(loud.alpha, 0.8, accuracy: 1e-12, "peak alpha 0.8 (ACC-012)")
    }

    func testConfigurationClampsAndReadsUnsupportedSymmetryAsSix() {
        for bad in [0, 1, 2, 7, 9, 13, -4] {
            XCTAssertEqual(MandalaConfiguration(symmetry: bad).symmetry, 6, "\(bad) → 6")
        }
        XCTAssertEqual(MandalaConfiguration(turnsPerSecond: .nan).turnsPerSecond, 0.025)
        XCTAssertEqual(MandalaConfiguration(turnsPerSecond: 0.2).turnsPerSecond, 0.05, "capped")
        XCTAssertEqual(MandalaConfiguration(turnsPerSecond: -1).turnsPerSecond, 0)
        let l = MandalaLayout()
        l.configuration.symmetry = 7
        XCTAssertEqual(l.configuration.symmetry, 6, "set later: clamped too")
        XCTAssertEqual(MandalaPetalStyle.spike.profile(0), 1)
        XCTAssertEqual(MandalaPetalStyle.petal.profile(0), 0)
        XCTAssertEqual(MandalaPetalStyle.round.profile(0.5), 1, accuracy: 1e-12)
    }

    /// Every corner of a sector lies within that sector's wedge, so copies never overlap; inside the picture.
    func testPetalsStayInsideTheirSectorAndThePicture() {
        for style in MandalaPetalStyle.allCases {
            for mirror in [false, true] {
                let l = layout(MandalaConfiguration(symmetry: 12, mirror: mirror, petalStyle: style),
                               bands: [Float](repeating: 1, count: 48), at: 0)
                let cx = Double(width) / 2, cy = Double(height) / 2, wedge = 2 * Double.pi / 12
                for k in 0..<l.regionCount {
                    let sector = k / l.regionsPerSector
                    let q = l.quad(k)
                    for c in 0..<4 {
                        let x = q[2 * c] - cx, y = q[2 * c + 1] - cy
                        XCTAssertLessThanOrEqual(hypot(x, y), Double(min(width, height)) / 2 + 1e-9)
                        guard hypot(x, y) > 1e-6 else { continue }
                        var phi = atan2(x, -y) - wedge * Double(sector)
                        phi = phi - 2 * Double.pi * (phi / (2 * Double.pi)).rounded(.down)
                        XCTAssertLessThanOrEqual(phi, wedge + 1e-9, "\(style) mirror \(mirror) region \(k)")
                    }
                }
            }
        }
    }

    func testSymmetryChangeAppliesFromTheNextLayoutAndColorsByStep() {
        let l = layout(MandalaConfiguration(symmetry: 3, palette: .spectrum))
        XCTAssertEqual(l.sectorCount, 3)
        l.configuration.symmetry = 12
        bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
            l.layout(bands: b, atNanoseconds: time, width: width, height: height)
        }
        XCTAssertEqual(l.sectorCount, 12)
        for k in [0, 5, 11, 12 * 12 - 1] {
            let expected = VisualPalette.spectrum.color(bar: k % 12, of: 12)
            XCTAssertEqual(l.color(ofRegion: k).red, expected.red)
            XCTAssertEqual(l.color(ofRegion: k).alpha, Float(l.alpha))
        }
    }

    func testSizesAndStorage() {
        let l = layout(MandalaConfiguration(), width: 0, height: 100)
        XCTAssertEqual(l.regionCount, 0)
        XCTAssertEqual(vertexCount(l), 0, "size 0 draws nothing")
        let tiny = layout(MandalaConfiguration(symmetry: 12, mirror: true), width: 3, height: 2)
        XCTAssertTrue(allCorners(tiny).allSatisfy(\.isFinite))
        let addresses = tiny.storageAddresses
        bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
            for f in 0..<60 { tiny.layout(bands: b, atNanoseconds: UInt64(f) * 16_666_667, width: 844, height: 390) }
        }
        XCTAssertEqual(tiny.storageAddresses, addresses, "no reallocation per frame")
    }

    // MARK: - Rotation (VIS-007-T05, S5)

    private func turns(_ l: MandalaLayout, at t: UInt64) -> Double {
        [Float]().withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
            l.layout(bands: b, atNanoseconds: t, width: 100, height: 100)
        }
        return l.angle / (2 * Double.pi)
    }

    /// Clockwise turn between two angles in turns, assuming less than half a turn.
    private func step(_ a: Double, _ b: Double) -> Double {
        var d = b - a
        d -= d.rounded()
        return d
    }

    func testRotationIsCappedAndHalvedUnderReduceMotion() {
        let dt: UInt64 = 16_666_667
        for (configured, reduce, expected) in [(0.025, false, 0.025), (0.2, false, 0.05), (0.025, true, 0.0125), (0.2, true, 0.025)] {
            let l = MandalaLayout(configuration: MandalaConfiguration(turnsPerSecond: configured, reduceMotion: reduce))
            var previous = turns(l, at: 0)
            var total = 0.0
            for f in 1...600 {   // 10 s at 60 Hz
                let now = turns(l, at: UInt64(f) * dt)
                let d = step(previous, now)
                XCTAssertGreaterThanOrEqual(d, 0, "clockwise")
                XCTAssertLessThanOrEqual(d / (Double(dt) * 1e-9), MandalaConfiguration.maximumTurnsPerSecond + 1e-9)
                total += d
                previous = now
            }
            XCTAssertEqual(total / (600 * Double(dt) * 1e-9), expected, accuracy: 1e-9,
                           "configured \(configured), Reduce Motion \(reduce)")
        }
    }

    func testReduceMotionToggleKeepsTheAngleContinuous() {
        let l = MandalaLayout()
        let t1: UInt64 = 12_000_000_000
        let before = turns(l, at: t1)
        XCTAssertEqual(before, 0.3, accuracy: 1e-12, "12 s × 0.025 turns per second")
        l.configuration.reduceMotion = true
        XCTAssertEqual(turns(l, at: t1), before, accuracy: 1e-12, "no jump at the toggle")
        XCTAssertEqual(turns(l, at: t1 + 4_000_000_000), before + 0.05, accuracy: 1e-12, "half speed after it")
        l.configuration.reduceMotion = false
        XCTAssertEqual(turns(l, at: t1 + 4_000_000_000), before + 0.05, accuracy: 1e-12)
        XCTAssertEqual(turns(l, at: t1 + 8_000_000_000), before + 0.15, accuracy: 1e-12)
        // Time going backwards: still a finite angle in 0..<2π.
        let back = turns(l, at: 1_000)
        XCTAssertTrue(back.isFinite && back >= 0 && back < 1)
        // A pure function of time at a constant speed: two layouts agree.
        let a = MandalaLayout(), b = MandalaLayout()
        _ = turns(a, at: 5_000_000_000)
        XCTAssertEqual(turns(a, at: 33_000_000_000), turns(b, at: 33_000_000_000))
    }
}
