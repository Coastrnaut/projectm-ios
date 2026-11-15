// GridWarpOutputTests.swift — OUT-008-T04 (specs/309-out-008-grid-warp, contract C2; OUT-008-S1, S2, S4): the grid warp in
// the compositor's real screen pass on the app's screen format (`bgra8Unorm_srgb`, read back as encoded bytes). The
// roadmap acceptance "Identity mesh is exact pass-through": `.none` runs no pass and an explicit identity mesh (3 × 3 and
// 9 × 9) reproduces the unwarped bytes exactly. A known affine warp and a curved warp match an independent CPU reference
// (its own Catmull-Rom, triangle rasterization and bilinear sampling in linear light) at ≥ 99 % of covered pixels within
// 5/255 (2 % of full scale); uncovered pixels are opaque black and every covered pixel shows picture content. Guides
// draw white lines only on the control grid. The recording output (`encodeOutput`) stays unwarped. Small frames, one
// frame each (owner rule 7). Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
@testable import Compositor
import Foundation
import Metal
import XCTest

final class GridWarpOutputTests: XCTestCase {
    private static let width = 48
    private static let height = 32

    /// A smooth picture whose blue is never 0 (so black means "not covered"), half-exact values.
    private static let picture: [Pixel] = (0..<(width * height)).map { (k: Int) -> Pixel in
        let x: Int = k % width, y: Int = k / width
        let r: Float = Float((x * 1024) / width) / 1024, g: Float = Float((y * 1024) / height) / 1024
        return Pixel(r * 0.9 + 0.05, g * 0.8 + 0.1, 0.5, 1)
    }

    private struct Frame {
        let screen: [SIMD4<Float>]
        let recording: [SIMD4<Float>]
        let warped: Int
        let holdsPicture: Bool
    }

    private func frame(_ mesh: OutputWarpMesh) throws -> Frame {
        let passes = try OutputPassRig()
        let rig: GPURig = passes.rig
        let layer = PixelsLayer(width: Self.width, height: Self.height, pixels: Self.picture)
        let compositor = try Compositor(device: rig.device, layers: [layer])
        compositor.outputWarp = mesh
        let screen: MTLTexture = try passes.target(.bgra8Unorm_srgb, width: Self.width, height: Self.height)
        let recording: MTLTexture = try passes.target(.bgra8Unorm_srgb, width: Self.width, height: Self.height)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        XCTAssertTrue(compositor.composite(into: screen, commandBuffer: commands, presentationTimeNanoseconds: 1_000_000_000,
                                           contentScale: 2, reduceFlashing: false, audio: .empty))
        XCTAssertTrue(compositor.encodeOutput(into: recording, commandBuffer: commands))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertNil(commands.error)
        let holds: Bool = compositor.holdsWarpPicture
        compositor.outputWarp = .none
        XCTAssertFalse(compositor.holdsWarpPicture, "turning the warp off returns its picture")
        return Frame(screen: passes.readRaw(screen), recording: passes.readRaw(recording), warped: compositor.warpedFrames,
                     holdsPicture: holds)
    }

    // MARK: Identity (OUT-008-S1)

    func testNoMeshRunsNoPassAndTheIdentityMeshIsExactPassThrough() throws {
        let plain = try frame(.none)
        XCTAssertEqual(plain.warped, 0, "no mesh: no pass")
        XCTAssertFalse(plain.holdsPicture)
        XCTAssertEqual(plain.screen, plain.recording)
        for side in [3, 9] {
            let identity = try frame(.identity(columns: side, rows: side))
            XCTAssertEqual(identity.warped, 1, "the pass really ran (\(side) × \(side))")
            XCTAssertTrue(identity.holdsPicture)
            XCTAssertEqual(identity.screen, plain.screen, "identity \(side) × \(side) is bit for bit the unwarped output")
            XCTAssertEqual(identity.recording, plain.recording, "the recording is never warped")
        }
    }

    // MARK: Known warps against an independent reference (OUT-008-S2, S4)

    func testAnAffineWarpMatchesTheReference() throws {
        // The picture at half size in the middle: points 0.25…0.75.
        let mesh = Self.mesh(3, 3) { (u: Float, v: Float) -> SIMD2<Float> in SIMD2<Float>(0.25 + 0.5 * u, 0.25 + 0.5 * v) }
        try check(mesh)
    }

    func testACurvedWarpMatchesTheReference() throws {
        var mesh = Self.mesh(5, 5) { (u: Float, v: Float) -> SIMD2<Float> in SIMD2<Float>(0.05 + 0.9 * u, 0.05 + 0.9 * v) }
        var points: [SIMD2<Float>] = mesh.points
        points[2 * 5 + 2] += SIMD2<Float>(0.08, -0.05)
        points[1 * 5 + 3] += SIMD2<Float>(-0.03, 0.04)
        points[3 * 5 + 1] += SIMD2<Float>(0.02, 0.03)
        mesh = OutputWarpMesh(columns: 5, rows: 5, points: points, showsGuides: false)
        try check(mesh)
    }

    private func check(_ mesh: OutputWarpMesh, file: StaticString = #filePath, line: UInt = #line) throws {
        let plain = try frame(.none)
        let warped = try frame(mesh)
        XCTAssertEqual(warped.recording, plain.recording, "the recording is unwarped", file: file, line: line)
        let expected: [SIMD4<Float>?] = Self.reference(mesh, source: plain.screen)
        var covered = 0, close = 0
        for k in 0..<expected.count {
            let shown: SIMD4<Float> = warped.screen[k]
            guard let want = expected[k] else {
                if shown.z > 0.1 { continue }   // a pixel on the outline: coverage may differ by rounding
                XCTAssertEqual(shown, SIMD4<Float>(0, 0, 0, 1), "uncovered pixel \(k) is opaque black", file: file, line: line)
                continue
            }
            covered += 1
            if shown == SIMD4<Float>(0, 0, 0, 1) { continue }   // outline rounding, counted against the 99 %
            XCTAssertEqual(shown.z, plain.screen[0].z, accuracy: 2.0 / 255, "covered pixel \(k) shows picture content",
                           file: file, line: line)
            let d: SIMD4<Float> = shown - want
            let worst: Float = max(Swift.abs(d.x), Swift.abs(d.y), Swift.abs(d.z))
            if worst <= 5.0 / 255 { close += 1 }
        }
        XCTAssertGreaterThan(covered, Self.width * Self.height / 5, file: file, line: line)
        XCTAssertGreaterThanOrEqual(Double(close), 0.99 * Double(covered), "\(close) of \(covered) within 5/255",
                                    file: file, line: line)
    }

    // MARK: Guides (OUT-008-D7)

    func testGuidesDrawWhiteLinesOnlyOnTheControlGrid() throws {
        let plain = try frame(.none)
        let guided = try frame(.identity(columns: 3, rows: 3, showsGuides: true))
        var white = 0, farEqual = 0, far = 0
        for k in 0..<plain.screen.count {
            let x = Float(k % Self.width) + 0.5, y = Float(k / Self.width) + 0.5
            let gx: Float = x / Float(Self.width) * 2, gy: Float = y / Float(Self.height) * 2   // grid units (2 cells)
            let dx: Float = abs(gx - gx.rounded()) * Float(Self.width) / 2, dy: Float = abs(gy - gy.rounded()) * Float(Self.height) / 2
            if guided.screen[k] == SIMD4<Float>(1, 1, 1, 1) {
                white += 1
                XCTAssertLessThan(min(dx, dy), 1.01, "white pixel \(k) lies on a grid line")
            }
            if min(dx, dy) > 1.5 {
                far += 1
                if guided.screen[k] == plain.screen[k] { farEqual += 1 }
            }
        }
        XCTAssertGreaterThan(white, Self.width + Self.height, "the middle lines and the border are drawn")
        XCTAssertEqual(farEqual, far, "away from the lines the picture is unchanged")
    }

    // MARK: Reference (independent of the pass)

    private static func mesh(_ columns: Int, _ rows: Int, _ f: (Float, Float) -> SIMD2<Float>) -> OutputWarpMesh {
        var points: [SIMD2<Float>] = []
        for r in 0..<rows {
            for c in 0..<columns { points.append(f(Float(c) / Float(columns - 1), Float(r) / Float(rows - 1))) }
        }
        return OutputWarpMesh(columns: columns, rows: rows, points: points, showsGuides: false)
    }

    /// The surface by its definition: Catmull-Rom over a grid padded by linear extrapolation, in Double.
    private static func surface(_ mesh: OutputWarpMesh, u: Double, v: Double) -> SIMD2<Double> {
        let cols: Int = mesh.columns, rows: Int = mesh.rows
        func point(_ r: Int, _ c: Int) -> SIMD2<Double> { SIMD2<Double>(mesh.points[r * cols + c]) }
        // Phantom points: linear continuation one step past the border, columns first, then rows.
        func inRow(_ r: Int, _ c: Int) -> SIMD2<Double> {
            if c < 0 { return 2 * point(r, 0) - point(r, 1) }
            if c >= cols { return 2 * point(r, cols - 1) - point(r, cols - 2) }
            return point(r, c)
        }
        func at(_ r: Int, _ c: Int) -> SIMD2<Double> {
            if r < 0 { return 2 * inRow(0, c) - inRow(1, c) }
            if r >= rows { return 2 * inRow(rows - 1, c) - inRow(rows - 2, c) }
            return inRow(r, c)
        }
        func spline(_ p0: SIMD2<Double>, _ p1: SIMD2<Double>, _ p2: SIMD2<Double>, _ p3: SIMD2<Double>, _ t: Double) -> SIMD2<Double> {
            let a: SIMD2<Double> = 2 * p1
            let b: SIMD2<Double> = (p2 - p0) * t
            let c: SIMD2<Double> = (2 * p0 - 5 * p1 + 4 * p2 - p3) * (t * t)
            let d: SIMD2<Double> = (3 * p1 - p0 - 3 * p2 + p3) * (t * t * t)
            return 0.5 * (a + b + c + d)
        }
        let su: Double = u * Double(cols - 1), sv: Double = v * Double(rows - 1)
        let c: Int = min(Int(su), cols - 2), r: Int = min(Int(sv), rows - 2)
        let tx: Double = su - Double(c), ty: Double = sv - Double(r)
        let rowsAt: [SIMD2<Double>] = (-1...2).map { (j: Int) -> SIMD2<Double> in
            spline(at(r + j, c - 1), at(r + j, c), at(r + j, c + 1), at(r + j, c + 2), tx)
        }
        return spline(rowsAt[0], rowsAt[1], rowsAt[2], rowsAt[3], ty)
    }

    /// Rasterizes the 16 × 16-per-cell triangles at pixel centres; nil where nothing is drawn.
    private static func reference(_ mesh: OutputWarpMesh, source: [SIMD4<Float>]) -> [SIMD4<Float>?] {
        let n: Int = OutputWarpMesh.subdivisions
        let lw: Int = (mesh.columns - 1) * n, lh: Int = (mesh.rows - 1) * n
        var vertices: [SIMD2<Double>] = []
        for j in 0...lh {
            for i in 0...lw {
                let s = surface(mesh, u: Double(i) / Double(lw), v: Double(j) / Double(lh))
                vertices.append(SIMD2<Double>(s.x * Double(width), s.y * Double(height)))
            }
        }
        var out = [SIMD4<Float>?](repeating: nil, count: width * height)
        for j in 0..<lh {
            for i in 0..<lw {
                let ia = j * (lw + 1) + i
                let corners: [(Int, SIMD2<Double>)] = [(ia, SIMD2<Double>(Double(i), Double(j))),
                                                       (ia + 1, SIMD2<Double>(Double(i + 1), Double(j))),
                                                       (ia + lw + 2, SIMD2<Double>(Double(i + 1), Double(j + 1))),
                                                       (ia + lw + 1, SIMD2<Double>(Double(i), Double(j + 1)))]
                for tri in [[0, 1, 3], [1, 2, 3]] {
                    fill(tri.map { (k: Int) -> (SIMD2<Double>, SIMD2<Double>) in
                        (vertices[corners[k].0], corners[k].1 / SIMD2<Double>(Double(lw), Double(lh)))
                    }, source: source, into: &out)
                }
            }
        }
        return out
    }

    private static func fill(_ t: [(SIMD2<Double>, SIMD2<Double>)], source: [SIMD4<Float>], into out: inout [SIMD4<Float>?]) {
        let a = t[0].0, b = t[1].0, c = t[2].0
        let area: Double = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        guard area != 0 else { return }
        let x0 = max(Int(min(a.x, b.x, c.x)), 0), x1 = min(Int(max(a.x, b.x, c.x)) + 1, width - 1)
        let y0 = max(Int(min(a.y, b.y, c.y)), 0), y1 = min(Int(max(a.y, b.y, c.y)) + 1, height - 1)
        guard x0 <= x1, y0 <= y1 else { return }
        for y in y0...y1 {
            for x in x0...x1 {
                let p = SIMD2<Double>(Double(x) + 0.5, Double(y) + 0.5)
                let w0: Double = ((b.x - p.x) * (c.y - p.y) - (b.y - p.y) * (c.x - p.x)) / area
                let w1: Double = ((c.x - p.x) * (a.y - p.y) - (c.y - p.y) * (a.x - p.x)) / area
                let w2: Double = 1 - w0 - w1
                guard w0 >= 0, w1 >= 0, w2 >= 0 else { continue }
                let uv: SIMD2<Double> = w0 * t[0].1 + w1 * t[1].1 + w2 * t[2].1
                out[y * width + x] = bilinear(source, uv)
            }
        }
    }

    /// Bilinear sampling in linear light of an sRGB-encoded picture, clamped at the edges, re-encoded.
    private static func bilinear(_ source: [SIMD4<Float>], _ uv: SIMD2<Double>) -> SIMD4<Float> {
        let fx: Double = uv.x * Double(width) - 0.5, fy: Double = uv.y * Double(height) - 0.5
        let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
        let ax = Float(fx - Double(x0)), ay = Float(fy - Double(y0))
        func texel(_ x: Int, _ y: Int) -> SIMD4<Float> {
            let e: SIMD4<Float> = source[min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)]
            return SIMD4<Float>(decode(e.x), decode(e.y), decode(e.z), e.w)
        }
        let top: SIMD4<Float> = texel(x0, y0) * (1 - ax) + texel(x0 + 1, y0) * ax
        let bottom: SIMD4<Float> = texel(x0, y0 + 1) * (1 - ax) + texel(x0 + 1, y0 + 1) * ax
        let l: SIMD4<Float> = top * (1 - ay) + bottom * ay
        return SIMD4<Float>(encode(l.x), encode(l.y), encode(l.z), l.w)
    }

    private static func decode(_ e: Float) -> Float { e <= 0.04045 ? e / 12.92 : powf((e + 0.055) / 1.055, 2.4) }
    private static func encode(_ l: Float) -> Float { l <= 0.0031308 ? l * 12.92 : 1.055 * powf(l, 1 / 2.4) - 0.055 }
}
#endif
