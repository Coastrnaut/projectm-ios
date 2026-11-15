// TessellationDriveTests.swift — VIS-018-T05 (VIS-018-R5 to R8; US3, US4): symmetry of the colouring (tiles that are
// k-fold rotations of each other about the frame centre — and reflections when mirrored — look identical; without
// mirror the colouring is chiral), palette resolution, settings clamping, the drive's bounds (inset, speeds,
// brightness, Reduce Motion half, time backwards, long gaps, invalid bands) and finite looks for extreme inputs.
// Pure Swift (Linux too).
import XCTest
@testable import VisualGenerators

final class TessellationDriveTests: XCTestCase {
    private func rotate(_ p: SIMD2<Float>, _ a: Float) -> SIMD2<Float> {
        SIMD2<Float>(cosf(a) * p.x - sinf(a) * p.y, sinf(a) * p.x + cosf(a) * p.y)
    }

    /// Compares every tile within 6 units of the centre with its image under `map` (which must be a symmetry of the lattice).
    private func assertSymmetric(_ tiling: TessellationTiling, tiles: Int, order: Int, mirror: Bool,
                                 map: (SIMD2<Float>) -> SIMD2<Float>, file: StaticString = #filePath, line: UInt = #line) -> Int {
        let o: SIMD2<Float> = TessellationLattice.origin(tiling: tiling, tiles: tiles)
        var compared = 0
        for gy in -24...24 {
            for gx in -24...24 {
                let q = SIMD2<Float>(Float(gx) * 0.25 + 0.031, Float(gy) * 0.25 + 0.017) + o
                let a: TessellationCell = TessellationLattice.classify(q, tiling: tiling)
                let mapped: SIMD2<Float> = map(a.centre - o) + o
                let b: TessellationCell = TessellationLattice.classify(mapped, tiling: tiling)
                XCTAssertLessThan(abs((b.centre - mapped).x) + abs((b.centre - mapped).y), 1e-3,
                                  "\(tiling): the map is a lattice symmetry", file: file, line: line)
                let la = TessellationLattice.tileLook(offset: a.centre - o, order: order, mirror: mirror, drift: 0.3, light: 0.6)
                let lb = TessellationLattice.tileLook(offset: b.centre - o, order: order, mirror: mirror, drift: 0.3, light: 0.6)
                XCTAssertEqual(la.t, lb.t, accuracy: 1e-3, "\(tiling) k=\(order) mirror \(mirror) tile \(a)", file: file, line: line)
                XCTAssertEqual(la.light, lb.light, accuracy: 1e-4, file: file, line: line)
                compared += 1
            }
        }
        return compared
    }

    func testSymmetricTilesLookIdentical() {
        var compared = 0
        let cases: [(TessellationTiling, Int, Int)] = [(.hexagon, 6, 6), (.hexagon, 7, 3), (.hexagon, 6, 2), (.triangle, 5, 6),
                                                      (.trihexagonal, 4, 6), (.square, 5, 4), (.square, 6, 4), (.square, 9, 2),
                                                      (.truncatedSquare, 8, 4)]
        for (tiling, tiles, order) in cases {
            let turn: Float = 2 * Float.pi / Float(order)
            compared += assertSymmetric(tiling, tiles: tiles, order: order, mirror: false) { (p: SIMD2<Float>) -> SIMD2<Float> in self.rotate(p, turn) }
            compared += assertSymmetric(tiling, tiles: tiles, order: order, mirror: true) { (p: SIMD2<Float>) -> SIMD2<Float> in self.rotate(p, turn) }
            // Mirrored: the reflection across the x-axis (θ → −θ) maps every one of these lattices to itself.
            compared += assertSymmetric(tiling, tiles: tiles, order: order, mirror: true) { (p: SIMD2<Float>) -> SIMD2<Float> in SIMD2<Float>(p.x, -p.y) }
        }
        XCTAssertGreaterThan(compared, 50_000)
    }

    func testWithoutMirrorTheColouringIsChiralAndOrderOneHasNoSymmetry() {
        let p = SIMD2<Float>(2, 1)
        let reflected = SIMD2<Float>(2, -1)
        XCTAssertNotEqual(TessellationLattice.symmetryValue(p, order: 6, mirror: false),
                          TessellationLattice.symmetryValue(reflected, order: 6, mirror: false), accuracy: 1e-3)
        XCTAssertEqual(TessellationLattice.symmetryValue(p, order: 6, mirror: true),
                       TessellationLattice.symmetryValue(reflected, order: 6, mirror: true), accuracy: 1e-6)
        XCTAssertNotEqual(TessellationLattice.symmetryValue(p, order: 1, mirror: false),
                          TessellationLattice.symmetryValue(rotate(p, Float.pi / 2), order: 1, mirror: false), accuracy: 1e-3)
        XCTAssertEqual(TessellationLattice.symmetryValue(.zero, order: 4, mirror: false), 0.5, "the centre tile")
    }

    func testPaletteResolutionAndSettingsClamping() {
        XCTAssertEqual(TessellationPalette.ice.resolved(over: .spectrum), .ice)
        XCTAssertEqual(TessellationPalette.mono.resolved(over: .colorBlindSafe), .colorBlindSafe, "ACC-003-R13 wins")
        let custom = VisualPalette.custom(PaletteRamp(stops: [LinearColor(red: 1, green: 0, blue: 0)], blended: true))
        XCTAssertEqual(TessellationPalette.ice.resolved(over: custom), custom, "a user palette wins")
        var config = NoiseFieldConfiguration.tessellation(TessellationSettings(palette: .ice))
        XCTAssertEqual(config.effectivePalette, .ice)
        config.palette = .colorBlindSafe
        XCTAssertEqual(config.effectivePalette, .colorBlindSafe)
        XCTAssertEqual(NoiseFieldConfiguration(palette: .ice).effectivePalette, .ice, "other modes: the shared palette")

        XCTAssertEqual(TessellationSettings(tiles: 1).tiles, 6)
        XCTAssertEqual(TessellationSettings(tiles: 17).tiles, 6)
        XCTAssertEqual(TessellationSettings(tiles: 16).tiles, 16)
        XCTAssertEqual(TessellationSettings(symmetry: 5).symmetry, 6)
        XCTAssertEqual(TessellationSettings(symmetry: 0).symmetry, 6)
        XCTAssertEqual(TessellationSettings(symmetry: 1).symmetryDescription, "no symmetry")
        XCTAssertEqual(TessellationSettings(symmetry: 4, mirror: true).symmetryDescription, "mirrored 4-fold symmetry")
        var bad = NoiseFieldConfiguration(wedges: 6, tunnelPace: 1, waterfall: true, fluidInk: true,
                                          signedDistance: .default, tessellation: .default)
        bad.tessellation?.tiles = 99
        let clean = bad.clamped()
        XCTAssertEqual(clean.tessellation?.tiles, 6)
        XCTAssertNil(clean.signedDistance)
        XCTAssertEqual(clean.wedges, 0)
        XCTAssertFalse(clean.waterfall || clean.fluidInk)
        XCTAssertEqual(clean.tunnelPace, 0)
    }

    private func settle(_ groups: MandalaBandGroups, reduceMotion: Bool, frames: Int = 240) -> TessellationDrive {
        var drive = TessellationDrive()
        for f in 0..<frames {
            drive.advance(groups: groups, timeNanoseconds: UInt64(f) * 1_000_000_000 / 60, reduceMotion: reduceMotion)
        }
        return drive
    }

    func testDriveBoundsAndReduceMotion() {
        let silent = settle(.silence, reduceMotion: false)
        XCTAssertEqual(silent.frame.inset, TessellationDrive.restInset, accuracy: 1e-4)
        XCTAssertEqual(silent.driftSpeed, TessellationDrive.baseDrift, accuracy: 1e-6)
        XCTAssertEqual(silent.frame.brightness, Float(TessellationDrive.baseBrightness), accuracy: 1e-4)
        let loud = settle(MandalaBandGroups(low: 1, mid: 1, high: 1), reduceMotion: false)
        XCTAssertEqual(loud.frame.inset, TessellationDrive.fullInset, accuracy: 1e-3, "full bass narrows the seams")
        XCTAssertEqual(loud.driftSpeed, TessellationDrive.maximumDrift, accuracy: 1e-4)
        XCTAssertEqual(loud.lightSpeed, TessellationDrive.maximumLight, accuracy: 1e-4)
        XCTAssertEqual(loud.frame.brightness, Float(TessellationDrive.maximumBrightness), accuracy: 1e-3)
        XCTAssertLessThan(loud.frame.brightness, 0.8, "ACC-012")
        let calm = settle(MandalaBandGroups(low: 1, mid: 1, high: 1), reduceMotion: true)
        XCTAssertEqual(calm.driftSpeed, TessellationDrive.maximumDrift / 2, accuracy: 1e-4, "Reduce Motion halves the drift")
        XCTAssertEqual(calm.lightSpeed, TessellationDrive.maximumLight / 2, accuracy: 1e-4, "and the light")
        let halfway: Float = TessellationDrive.restInset - (TessellationDrive.restInset - TessellationDrive.fullInset) / 2
        XCTAssertEqual(calm.frame.inset, halfway, accuracy: 1e-3, "and the swell depth")
    }

    func testDriveIgnoresTimeGoingBackwardsAndCapsLongGaps() {
        var drive = TessellationDrive()
        let loud = MandalaBandGroups(low: 1, mid: 1, high: 1)
        drive.advance(groups: loud, timeNanoseconds: 10_000_000_000, reduceMotion: false)
        drive.advance(groups: loud, timeNanoseconds: 10_100_000_000, reduceMotion: false)
        let before = drive
        drive.advance(groups: loud, timeNanoseconds: 5_000_000_000, reduceMotion: false)
        XCTAssertEqual(drive, before, "time going backwards changes nothing")
        let light: Double = drive.light
        drive.advance(groups: loud, timeNanoseconds: 1_000_000_000 * 1_000_000_000, reduceMotion: false)
        let moved: Double = (drive.light - light + 1).truncatingRemainder(dividingBy: 1)
        XCTAssertLessThanOrEqual(moved, TessellationDrive.maximumLight * TessellationDrive.maxStep + 1e-9, "a long gap moves one capped step")
        var odd = TessellationDrive()
        for f in 0..<30 {
            odd.advance(groups: MandalaBandGroups(low: .nan, mid: .infinity, high: -5), timeNanoseconds: UInt64(f) * 16_666_667,
                        reduceMotion: false)
        }
        let frame = odd.frame
        XCTAssertTrue(frame.inset.isFinite && frame.drift.isFinite && frame.light.isFinite && frame.brightness.isFinite)
        let wild = TessellationFrame(inset: .nan, drift: .infinity, light: -3.25, brightness: 9).sanitized()
        XCTAssertEqual(wild.inset, TessellationDrive.restInset)
        XCTAssertEqual(wild.drift, 0)
        XCTAssertEqual(wild.light, 0.75, accuracy: 1e-6)
        XCTAssertEqual(wild.brightness, Float(TessellationDrive.maximumBrightness))
    }

    func testTileLooksAreFiniteForExtremeInputs() {
        for offset in [SIMD2<Float>(.nan, 1), SIMD2<Float>(.infinity, -.infinity), SIMD2<Float>(1e30, 1e30), SIMD2<Float>(0, 0)] {
            for mirror in [true, false] {
                let look = TessellationLattice.tileLook(offset: offset, order: 6, mirror: mirror, drift: .nan, light: .infinity)
                XCTAssertTrue(look.t.isFinite && look.t >= 0 && look.t <= 1, "\(offset)")
                XCTAssertTrue(look.light.isFinite && look.light >= 0 && look.light <= 1, "\(offset)")
            }
        }
    }
}
