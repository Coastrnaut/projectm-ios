// TessellationAlignmentTests.swift — VIS-018-T04 (VIS-018-R3, R4; S1): the roadmap acceptance "different tile counts
// remain aligned at all supported aspect ratios", on the CPU lattice that the shader repeats (spec Clarifications Q2).
// For 5 tilings × N 2…16 × 6 aspect ratios at a grid of sample points: A1 centred (the pixel mirrored through the frame
// centre lies in the mirrored tile), A2 exact size (tile size = shorter / N; one tile size along x is one lattice
// step; squares: the shorter side's edges are seams, N whole squares across), A5 the same tile at the same offset
// (in shorter-side units) at every aspect ratio. Per pixel at quarter scale for representative N: A3 equal tiles (whole
// tiles' pixel bounding boxes per shape differ ≤ 1 px) and A4 no gaps or overlaps (the classified tile's polygon,
// built independently here in Double, contains the pixel and agrees on the edge distance). The prototype areas fill
// one lattice period exactly. `VIS018_ALIGNMENT_SWEEP=1` runs A3/A4 per pixel at full size for every N (on demand).
// Pure Swift (Linux too).
import Foundation
import XCTest
@testable import VisualGenerators

/// The supported aspect ratios (spec Assumptions), in pixels.
enum TessellationAspects {
    static let all: [(name: String, width: Int, height: Int)] = [
        ("phone portrait", 1179, 2556), ("phone landscape", 2556, 1179), ("iPad 4:3", 2048, 1536),
        ("16:9", 1920, 1080), ("21:9", 2520, 1080), ("square", 1080, 1080),
    ]
}

/// An independent polygon for a tile (Double; built from the tile's lattice coordinates and shape only).
enum TessellationPolygonOracle {
    static let h: Double = 3.0.squareRoot() / 2

    static func cart(_ u: Double, _ v: Double) -> SIMD2<Double> { SIMD2<Double>(u + 0.5 * v, v * h) }

    static func regular(centre: SIMD2<Double>, radius: Double, startDegrees: Double, count: Int) -> [SIMD2<Double>] {
        (0..<count).map { (m: Int) -> SIMD2<Double> in
            let a: Double = (startDegrees + 360.0 * Double(m) / Double(count)) * Double.pi / 180
            return centre + radius * SIMD2<Double>(cos(a), sin(a))
        }
    }

    static func polygon(tiling: TessellationTiling, i: Int, j: Int, shape: Int) -> [SIMD2<Double>] {
        let u = Double(i), v = Double(j)
        switch tiling {
        case .square:
            return [SIMD2(u, v), SIMD2(u + 1, v), SIMD2(u + 1, v + 1), SIMD2(u, v + 1)]
        case .triangle:
            return shape == 0 ? [cart(u, v), cart(u + 1, v), cart(u, v + 1)] : [cart(u + 1, v), cart(u + 1, v + 1), cart(u, v + 1)]
        case .hexagon:
            return regular(centre: cart(u, v), radius: 1 / 3.0.squareRoot(), startDegrees: 30, count: 6)
        case .trihexagonal:
            if shape == 0 { return regular(centre: cart(u, v), radius: 0.5, startDegrees: 0, count: 6) }
            let t: [SIMD2<Double>] = shape == 1 ? [cart(u, v), cart(u + 1, v), cart(u, v + 1)]
                : [cart(u + 1, v), cart(u + 1, v + 1), cart(u, v + 1)]
            return [(t[0] + t[1]) / 2, (t[1] + t[2]) / 2, (t[2] + t[0]) / 2]
        case .truncatedSquare:
            if shape == 0 { return regular(centre: SIMD2(u, v), radius: 0.5 / cos(Double.pi / 8), startDegrees: 22.5, count: 8) }
            let k: Double = 1 - 1 / 2.0.squareRoot()
            let c = SIMD2<Double>(u + 0.5, v + 0.5)
            return [c + SIMD2(k, 0), c + SIMD2(0, k), c - SIMD2(k, 0), c - SIMD2(0, k)]
        }
    }

    /// The smallest signed distance from `p` to the polygon's edge lines (positive inside a convex polygon).
    static func edgeDistance(_ p: SIMD2<Double>, polygon: [SIMD2<Double>]) -> Double {
        let centroid: SIMD2<Double> = polygon.reduce(SIMD2<Double>(0, 0), +) / Double(polygon.count)
        var best = Double.infinity
        for k in 0..<polygon.count {
            let a: SIMD2<Double> = polygon[k], b: SIMD2<Double> = polygon[(k + 1) % polygon.count]
            let e: SIMD2<Double> = b - a
            var n = SIMD2<Double>(-e.y, e.x) / (e * e).sum().squareRoot()
            if ((centroid - a) * n).sum() < 0 { n = -n }
            best = min(best, ((p - a) * n).sum())
        }
        return best
    }

    static func area(_ polygon: [SIMD2<Double>]) -> Double {
        var s = 0.0
        for k in 0..<polygon.count {
            let a = polygon[k], b = polygon[(k + 1) % polygon.count]
            s += a.x * b.y - b.x * a.y
        }
        return abs(s) / 2
    }
}

final class TessellationAlignmentTests: XCTestCase {
    private static let grid = 48
    private static let counts: [Int] = Array(TessellationSettings.tileRange)
    private static let seamPixels: Float = 0.01

    private func pixelCentre(_ k: Int, of n: Int, size: Int) -> Float {
        Float(min((2 * k + 1) * size / (2 * n), size - 1)) + 0.5
    }

    /// A1 and A2 at a 48 × 48 grid, every tiling × N × aspect ratio.
    func testCentredAndExactSizeForEveryTileCountAndAspectRatio() {
        var checked = 0
        var failures: [String] = []
        for tiling in TessellationTiling.allCases {
            for n in Self.counts {
                for aspect in TessellationAspects.all {
                    let placement = TessellationPlacement(width: aspect.width, height: aspect.height, tiles: n, tiling: tiling)
                    let s: Float = placement.tileSize
                    let shorter = Float(min(aspect.width, aspect.height))
                    if abs(s * Float(n) - shorter) > 1e-3 { failures.append("\(tiling) N=\(n) \(aspect.name): size \(s)") }
                    let o: SIMD2<Float> = placement.origin
                    let size = SIMD2<Float>(Float(aspect.width), Float(aspect.height))
                    for gy in 0..<Self.grid {
                        for gx in 0..<Self.grid {
                            let p = SIMD2<Float>(pixelCentre(gx, of: Self.grid, size: aspect.width), pixelCentre(gy, of: Self.grid, size: aspect.height))
                            let a: TessellationCell = placement.cell(pixel: p)
                            // A1: the mirrored pixel lies in the mirrored tile.
                            let b: TessellationCell = placement.cell(pixel: size - p)
                            if a.edge * s >= Self.seamPixels && b.edge * s >= Self.seamPixels {
                                let m: SIMD2<Float> = ((b.centre - o) + (a.centre - o)) * s
                                let miss: Float = max(abs(m.x), abs(m.y))
                                if miss > 0.01 { failures.append("A1 \(tiling) N=\(n) \(aspect.name) at \(p): \(miss) px") }
                                checked += 1
                            }
                            // A2: one tile size along x is one lattice step (i + 1, same j and shape).
                            let shifted: TessellationCell = placement.cell(pixel: p + SIMD2<Float>(s, 0))
                            if a.edge * s >= Self.seamPixels && shifted.edge * s >= Self.seamPixels {
                                if !(shifted.i == a.i + 1 && shifted.j == a.j && shifted.shape == a.shape) {
                                    failures.append("A2 \(tiling) N=\(n) \(aspect.name) at \(p): \(a) → \(shifted)")
                                }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(failures.count, 0, failures.prefix(5).joined(separator: "\n"))
        XCTAssertGreaterThan(checked, 1_000_000)
        print("VIS-018 A1/A2: \(checked) mirrored sample pairs over 5 tilings × 15 tile counts × 6 aspect ratios, \(failures.count) failures")
    }

    /// A2 for squares: the shorter side's two edges are seams and it holds exactly N whole squares.
    func testSquaresFillTheShorterSideWithWholeTiles() {
        for n in Self.counts {
            for aspect in TessellationAspects.all {
                let placement = TessellationPlacement(width: aspect.width, height: aspect.height, tiles: n, tiling: .square)
                let portrait: Bool = aspect.width <= aspect.height
                let length: Int = min(aspect.width, aspect.height)
                let first: SIMD2<Float> = placement.unit(pixel: SIMD2<Float>(0, 0))
                let last: SIMD2<Float> = placement.unit(pixel: SIMD2<Float>(Float(aspect.width), Float(aspect.height)))
                let a: Float = portrait ? first.x : first.y
                let b: Float = portrait ? last.x : last.y
                XCTAssertEqual(a, a.rounded(), accuracy: 1e-4, "N=\(n) \(aspect.name): leading edge on a seam")
                XCTAssertEqual(b, b.rounded(), accuracy: 1e-4, "N=\(n) \(aspect.name): trailing edge on a seam")
                XCTAssertEqual(Int((b - a).rounded()), n, "N=\(n) \(aspect.name): N whole squares")
                var tiles = Set<Int>()
                for k in 0..<length {
                    let pixel: SIMD2<Float> = portrait ? SIMD2<Float>(Float(k) + 0.5, Float(aspect.height / 2) + 0.25)
                        : SIMD2<Float>(Float(aspect.width / 2) + 0.25, Float(k) + 0.5)
                    let cell: TessellationCell = placement.cell(pixel: pixel)
                    tiles.insert(portrait ? cell.i : cell.j)
                }
                XCTAssertEqual(tiles.count, n, "N=\(n) \(aspect.name): tiles across the shorter side")
            }
        }
    }

    /// A5: the same offset from the centre (in shorter-side units) lies in the same tile at every aspect ratio.
    func testSamePatternAtEveryAspectRatio() {
        var compared = 0
        for tiling in TessellationTiling.allCases {
            for n in Self.counts {
                let placements: [TessellationPlacement] = TessellationAspects.all.map { (a: (name: String, width: Int, height: Int)) -> TessellationPlacement in
                    TessellationPlacement(width: a.width, height: a.height, tiles: n, tiling: tiling)
                }
                for gy in 0..<32 {
                    for gx in 0..<32 {
                        let u = SIMD2<Float>((Float(gx) + 0.37) / 32 - 0.5, (Float(gy) + 0.61) / 32 - 0.5)
                        let cells: [TessellationCell] = placements.map { (p: TessellationPlacement) -> TessellationCell in
                            p.cell(pixel: p.centre + u * Float(min(p.width, p.height)))
                        }
                        guard cells.allSatisfy({ (c: TessellationCell) -> Bool in c.edge >= 1e-3 }) else { continue }
                        compared += 1
                        for (k, c) in cells.enumerated() where !c.sameTile(cells[0]) {
                            XCTFail("\(tiling) N=\(n) offset \(u): \(TessellationAspects.all[k].name) \(c) vs \(cells[0])")
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(compared, 60_000)
    }

    private struct Key: Hashable { var i: Int; var j: Int; var shape: Int }
    private struct Box { var minX: Int; var maxX: Int; var minY: Int; var maxY: Int; var count: Int }
    /// The largest |pixel count − exact area| / perimeter seen (reported).
    private var worstCountError = 0.0

    /// A3 and A4 over every pixel of one output (returns the number of pixels checked).
    private func checkEveryPixel(_ placement: TessellationPlacement, containmentStride: Int) -> Int {
        var boxes: [Key: Box] = [:]
        let tiling: TessellationTiling = placement.tiling
        var failures: [String] = []
        var cache: [Key: [SIMD2<Double>]] = [:]
        for y in 0..<placement.height {
            for x in 0..<placement.width {
                let p = SIMD2<Float>(Float(x) + 0.5, Float(y) + 0.5)
                let cell: TessellationCell = placement.cell(pixel: p)
                let key = Key(i: cell.i, j: cell.j, shape: cell.shape)
                if var b = boxes[key] {
                    b.minX = min(b.minX, x); b.maxX = max(b.maxX, x); b.minY = min(b.minY, y); b.maxY = max(b.maxY, y); b.count += 1
                    boxes[key] = b
                } else {
                    boxes[key] = Box(minX: x, maxX: x, minY: y, maxY: y, count: 1)
                }
                guard (x + y * placement.width) % containmentStride == 0 else { continue }
                let polygon: [SIMD2<Double>]
                if let cached = cache[key] { polygon = cached } else {
                    polygon = TessellationPolygonOracle.polygon(tiling: tiling, i: cell.i, j: cell.j, shape: cell.shape)
                    cache[key] = polygon
                }
                let q: SIMD2<Float> = placement.unit(pixel: p)
                let d: Double = TessellationPolygonOracle.edgeDistance(SIMD2<Double>(Double(q.x), Double(q.y)), polygon: polygon)
                if d < -1e-3 { failures.append("A4 \(tiling) N=\(placement.tiles) \(placement.width)×\(placement.height) pixel \(x),\(y) outside its tile \(cell) by \(d)") }
                if abs(d - Double(cell.edge)) > 1e-3 { failures.append("A4 edge \(tiling) at \(x),\(y): \(cell.edge) vs \(d)") }
            }
        }
        // A3: whole tiles (not touching the frame's border) of one shape are the same tile up to pixel sampling: their
        // pixel bounding boxes differ by ≤ 1 px for squares and ≤ 2 px for shapes with slanted edges (a pixel-centre
        // grid can miss a corner narrower than a pixel), and each tile's pixel count is within half its perimeter (px)
        // of its exact area.
        let s: Double = Double(placement.tileSize)
        for shape in 0..<tiling.shapeCount {
            let prototype: [SIMD2<Double>] = TessellationPolygonOracle.polygon(tiling: tiling, i: 0, j: 0, shape: shape)
            let area: Double = TessellationPolygonOracle.area(prototype) * s * s
            var perimeter = 0.0
            for k in 0..<prototype.count {
                let e: SIMD2<Double> = prototype[(k + 1) % prototype.count] - prototype[k]
                perimeter += (e * e).sum().squareRoot() * s
            }
            let whole = boxes.filter { (e: (key: Key, value: Box)) -> Bool in
                e.key.shape == shape && e.value.minX > 0 && e.value.minY > 0 && e.value.maxX < placement.width - 1 && e.value.maxY < placement.height - 1
            }
            let widths: [Int] = whole.values.map { (b: Box) -> Int in b.maxX - b.minX }
            let heights: [Int] = whole.values.map { (b: Box) -> Int in b.maxY - b.minY }
            guard let wMin = widths.min(), let wMax = widths.max(), let hMin = heights.min(), let hMax = heights.max() else { continue }
            let limit: Int = tiling == .square ? 1 : 2
            if wMax - wMin > limit || hMax - hMin > limit {
                failures.append("A3 \(tiling) shape \(shape) N=\(placement.tiles) \(placement.width)×\(placement.height): widths \(wMin)…\(wMax), heights \(hMin)…\(hMax)")
            }
            for box in whole.values where abs(Double(box.count) - area) > 0.5 * perimeter {
                failures.append("A3 count \(tiling) shape \(shape) N=\(placement.tiles): \(box.count) px vs area \(area) (perimeter \(perimeter))")
            }
            worstCountError = max(worstCountError, whole.values.map { (b: Box) -> Double in abs(Double(b.count) - area) / perimeter }.max() ?? 0)
        }
        XCTAssertEqual(failures.count, 0, failures.prefix(5).joined(separator: "\n"))
        return placement.width * placement.height
    }

    /// A3, A4 per pixel at quarter scale for N 2, 7, 16 in portrait phone and 21:9.
    func testEqualTilesWithNoGapsOrOverlapsPerPixel() {
        var pixels = 0
        for tiling in TessellationTiling.allCases {
            for n in [2, 7, 16] {
                for size in [(295, 639), (630, 270)] {
                    pixels += checkEveryPixel(TessellationPlacement(width: size.0, height: size.1, tiles: n, tiling: tiling), containmentStride: 7)
                }
            }
        }
        print("VIS-018 A3/A4: \(pixels) pixels classified (polygon containment and edge distance every 7th); worst |count − area| / perimeter \(worstCountError)")
    }

    /// On demand (`VIS018_ALIGNMENT_SWEEP=1`): A3, A4 per pixel at full size for every tiling, N and aspect ratio.
    func testFullPixelSweep() throws {
        guard ProcessInfo.processInfo.environment["VIS018_ALIGNMENT_SWEEP"] == "1" else {
            throw XCTSkip("Full sweep runs with VIS018_ALIGNMENT_SWEEP=1 (owner rule 7: on demand)")
        }
        for tiling in TessellationTiling.allCases {
            for n in Self.counts {
                for aspect in TessellationAspects.all {
                    _ = checkEveryPixel(TessellationPlacement(width: aspect.width, height: aspect.height, tiles: n, tiling: tiling),
                                        containmentStride: 97)
                }
            }
        }
    }

    /// No gaps or overlaps at the polygon level: the prototypes of one lattice period fill its area exactly.
    func testPrototypeTilesFillOneLatticePeriod() {
        let h: Double = TessellationPolygonOracle.h
        let periods: [(TessellationTiling, Double)] = [(.square, 1), (.triangle, h), (.hexagon, h), (.trihexagonal, h), (.truncatedSquare, 1)]
        for (tiling, period) in periods {
            var sum = 0.0
            for shape in 0..<tiling.shapeCount {
                sum += TessellationPolygonOracle.area(TessellationPolygonOracle.polygon(tiling: tiling, i: 0, j: 0, shape: shape))
            }
            XCTAssertEqual(sum, period, accuracy: 1e-9, "\(tiling)")
            for shape in 0..<tiling.shapeCount {   // the classifier's inradius matches the polygon's
                let polygon = TessellationPolygonOracle.polygon(tiling: tiling, i: 0, j: 0, shape: shape)
                let centroid: SIMD2<Double> = polygon.reduce(SIMD2<Double>(0, 0), +) / Double(polygon.count)
                XCTAssertEqual(TessellationPolygonOracle.edgeDistance(centroid, polygon: polygon),
                               Double(TessellationLattice.inradius(tiling: tiling, shape: shape)), accuracy: 1e-6, "\(tiling) \(shape)")
            }
        }
    }

    /// Points exactly on seams and vertices classify into exactly one tile, deterministically, whose polygon holds them.
    func testSeamPointsBelongToExactlyOneTile() {
        let h: Float = TessellationLattice.rowHeight
        let seams: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 1), SIMD2(0.5, h), SIMD2(0.25, h / 2), SIMD2(0.5, 0.5),
                                     SIMD2(-0.5, -h), SIMD2(0.75, h / 2), SIMD2(0.70710678, 0), SIMD2(-3, 2)]
        for tiling in TessellationTiling.allCases {
            for q in seams {
                let a: TessellationCell = TessellationLattice.classify(q, tiling: tiling)
                XCTAssertEqual(a, TessellationLattice.classify(q, tiling: tiling))
                let polygon = TessellationPolygonOracle.polygon(tiling: tiling, i: a.i, j: a.j, shape: a.shape)
                XCTAssertGreaterThanOrEqual(TessellationPolygonOracle.edgeDistance(SIMD2<Double>(Double(q.x), Double(q.y)), polygon: polygon),
                                            -1e-4, "\(tiling) \(q) → \(a)")
            }
            let odd: TessellationCell = TessellationLattice.classify(SIMD2<Float>(.nan, .infinity), tiling: tiling)
            XCTAssertTrue(odd.edge.isFinite, "non-finite input classifies safely")
        }
    }
}
