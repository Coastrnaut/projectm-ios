// SpectrumFlashAreas.swift — a native spectrum's levels in the strobe safety envelope's 17 areas
// (FX-019-R4, R9; research FX-019-D6, VIS-002-D1; ADR-0011 decision 4).
//
// Works on any `FlashRegionLayout`: flat-colored, non-overlapping convex regions over a flat
// background (the circular spectrum's sectors, VIS-001; the linear spectrum's bars and caps,
// VIS-002).
// * Own light: each drawn region's convex quads (for the circular spectrum, the quads of the
//   triangles the GPU draws) are clipped against the 4 × 4 tiles (Sutherland–Hodgman), giving the
//   region's exact area in each tile.
// * Light added downstream (the glow, FX-001): `transfer.outputLuminance − Y` per unit of region
//   area, spread over the tiles that the region's bounding box, grown by the transfer's spread
//   radius, overlaps, in proportion to the overlap (an estimate of where the halo lands; light past
//   the frame's edges is dropped, as the bloom's zero padding does). The whole-frame area keeps
//   FX-001's exact upper bound (Σ area · T(color) / A).
// * Background: the rest of each tile, at the transfer's value of the background color.
// Coverage is computed once per layout generation (and spread radius), lazily on the first query;
// each query then costs one pass over the drawn regions. All storage is allocated in `init`.
// Not Sendable.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import FlashSafety

final class SpectrumFlashAreas {
    static let tiles = FlashZones.tileCount
    /// Regions the storage holds.
    private let bars: Int
    /// [bar × tile]: own covered area in pixels².
    private let own: UnsafeMutablePointer<Double>
    /// [bar × tile]: share of the bar's added light that lands in the tile.
    private let spread: UnsafeMutablePointer<Double>
    /// [bar]: tiles with own or spread light (bit z), so a query visits only those.
    private let touched: UnsafeMutablePointer<UInt16>
    /// Per tile: accumulated luminance, redness, covered area.
    private let accumulator: UnsafeMutablePointer<Double>
    /// Clip scratch: two polygons of at most 16 points (x, y interleaved).
    private let polygonA: UnsafeMutablePointer<Double>
    private let polygonB: UnsafeMutablePointer<Double>
    private var validGeneration = -1
    private var validSpread = -1.0

    init(regionCapacity: Int) {
        bars = max(regionCapacity, 1)
        own = .allocate(capacity: bars * Self.tiles)
        own.initialize(repeating: 0, count: bars * Self.tiles)
        spread = .allocate(capacity: bars * Self.tiles)
        spread.initialize(repeating: 0, count: bars * Self.tiles)
        touched = .allocate(capacity: bars)
        touched.initialize(repeating: 0, count: bars)
        accumulator = .allocate(capacity: Self.tiles * 3)
        accumulator.initialize(repeating: 0, count: Self.tiles * 3)
        polygonA = .allocate(capacity: 32)
        polygonA.initialize(repeating: 0, count: 32)
        polygonB = .allocate(capacity: 32)
        polygonB.initialize(repeating: 0, count: 32)
    }

    deinit {
        own.deinitialize(count: bars * Self.tiles); own.deallocate()
        spread.deinitialize(count: bars * Self.tiles); spread.deallocate()
        touched.deinitialize(count: bars); touched.deallocate()
        accumulator.deinitialize(count: Self.tiles * 3); accumulator.deallocate()
        polygonA.deinitialize(count: 32); polygonA.deallocate()
        polygonB.deinitialize(count: 32); polygonB.deallocate()
    }

    /// Writes the 17 area levels of `layout` drawn with `gain` and passed through `transfer`.
    /// `generation` changes whenever the layout's regions change.
    func levels<Layout: FlashRegionLayout, Transfer: FrameLuminanceTransfer>(of layout: Layout, generation: Int, gain: Float,
                                                  transfer: Transfer, into out: UnsafeMutableBufferPointer<FlashLevels>) {
        guard out.count >= FlashZones.count else { return }
        let w = layout.width, h = layout.height
        guard w > 0, h > 0 else {
            for z in 0..<out.count { out[z] = .zero }
            return
        }
        let radius = max(transfer.spreadRadius(width: w, height: h), 0)
        if generation != validGeneration || radius != validSpread {
            computeCoverage(layout, spreadRadius: radius)
            validGeneration = generation
            validSpread = radius
        }
        let total = Double(w) * Double(h)
        let tileArea = total / Double(Self.tiles)
        for i in 0..<(Self.tiles * 3) { accumulator[i] = 0 }
        let background = layout.flashBackground
        var wholeY = 0.0, wholeR = 0.0, covered = 0.0
        for k in 0..<min(layout.flashRegionCount, bars) {
            let area = layout.flashRegionArea(k)
            guard area > 0 else { continue }
            covered += area
            let c = layout.flashRegionColor(k)
            let a = c.alpha
            let pixel = LinearColor(red: c.red * gain * a + (1 - a) * background.red,
                                    green: c.green * gain * a + (1 - a) * background.green,
                                    blue: c.blue * gain * a + (1 - a) * background.blue,
                                    alpha: a + (1 - a) * background.alpha)
            let y = transfer.outputLuminance(ofFlatColor: pixel)
            let r = transfer.outputRedness(ofFlatColor: pixel)
            wholeY += area * y
            wholeR += area * r
            let ownY = Double(pixel.relativeLuminance), ownR = Double(pixel.redness)
            let addedY = max(y - ownY, 0) * area, addedR = max(r - ownR, 0) * area
            let base = k * Self.tiles
            var mask = touched[k]
            while mask != 0 {
                let z = mask.trailingZeroBitCount
                mask &= mask - 1
                let c = own[base + z]
                if c > 0 {
                    accumulator[z * 3] += c * ownY
                    accumulator[z * 3 + 1] += c * ownR
                    accumulator[z * 3 + 2] += c
                }
                let s = spread[base + z]
                if s > 0 && (addedY > 0 || addedR > 0) {
                    accumulator[z * 3] += s * addedY
                    accumulator[z * 3 + 1] += s * addedR
                }
            }
        }
        let backgroundY = transfer.outputLuminance(ofFlatColor: background)
        let backgroundR = transfer.outputRedness(ofFlatColor: background)
        for z in 0..<Self.tiles {
            let rest = max(0, tileArea - accumulator[z * 3 + 2])
            out[z] = FlashLevels(luminance: (accumulator[z * 3] + rest * backgroundY) / tileArea,
                                 redness: (accumulator[z * 3 + 1] + rest * backgroundR) / tileArea)
        }
        let rest = max(0, total - covered)
        out[FlashZones.wholeFrame] = FlashLevels(luminance: (wholeY + rest * backgroundY) / total,
                                                 redness: (wholeR + rest * backgroundR) / total)
    }

    // MARK: - Coverage

    private func computeCoverage<Layout: FlashRegionLayout>(_ layout: Layout, spreadRadius: Double) {
        let w = Double(layout.width), h = Double(layout.height)
        let tw = w / 4, th = h / 4
        own.update(repeating: 0, count: bars * Self.tiles)
        spread.update(repeating: 0, count: bars * Self.tiles)
        touched.update(repeating: 0, count: bars)
        for k in 0..<min(layout.flashRegionCount, bars) {
            guard layout.flashRegionArea(k) > 0 else { continue }
            let base = k * Self.tiles
            var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
            layout.forEachFlashQuad(ofRegion: k) { ax, ay, bx, by, cx, cy, dx, dy in
                addQuad(ax, ay, bx, by, cx, cy, dx, dy, base: base, tw: tw, th: th)
                // Pairwise min/max: the variadic forms build an array.
                minX = min(minX, min(min(ax, bx), min(cx, dx))); maxX = max(maxX, max(max(ax, bx), max(cx, dx)))
                minY = min(minY, min(min(ay, by), min(cy, dy))); maxY = max(maxY, max(max(ay, by), max(cy, dy)))
            }
            for z in 0..<Self.tiles where own[base + z] > 0 { touched[k] |= UInt16(1) << UInt16(z) }
            guard spreadRadius > 0 else { continue }
            // The halo box: the region's box grown by the spread radius; shares by overlap.
            let bx0 = minX - spreadRadius, bx1 = maxX + spreadRadius
            let by0 = minY - spreadRadius, by1 = maxY + spreadRadius
            let boxArea = (bx1 - bx0) * (by1 - by0)
            guard boxArea > 0 else { continue }
            for row in 0..<4 {
                let oy = min(by1, Double(row + 1) * th) - max(by0, Double(row) * th)
                guard oy > 0 else { continue }
                for col in 0..<4 {
                    let ox = min(bx1, Double(col + 1) * tw) - max(bx0, Double(col) * tw)
                    if ox > 0 {
                        spread[base + row * 4 + col] = ox * oy / boxArea
                        touched[k] |= UInt16(1) << UInt16(row * 4 + col)
                    }
                }
            }
        }
    }

    private func addQuad(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double,
                         _ cx: Double, _ cy: Double, _ dx: Double, _ dy: Double,
                         base: Int, tw: Double, th: Double) {
        let lowX = min(min(ax, bx), min(cx, dx)), highX = max(max(ax, bx), max(cx, dx))
        let lowY = min(min(ay, by), min(cy, dy)), highY = max(max(ay, by), max(cy, dy))
        let c0 = max(0, min(3, Int((lowX / tw).rounded(.down))))
        let c1 = max(0, min(3, Int((highX / tw).rounded(.down))))
        let r0 = max(0, min(3, Int((lowY / th).rounded(.down))))
        let r1 = max(0, min(3, Int((highY / th).rounded(.down))))
        for row in r0...r1 {
            for col in c0...c1 {
                let x0 = Double(col) * tw, x1 = Double(col + 1) * tw, y0 = Double(row) * th, y1 = Double(row + 1) * th
                let area: Double
                if lowX >= x0 && highX <= x1 && lowY >= y0 && highY <= y1 {
                    // Inside one tile (the common case): the quad's own area.
                    area = abs((ax * by - bx * ay) + (bx * cy - cx * by) + (cx * dy - dx * cy) + (dx * ay - ax * dy)) / 2
                } else {
                    area = clippedArea(ax, ay, bx, by, cx, cy, dx, dy, x0: x0, x1: x1, y0: y0, y1: y1,
                                       lowX: lowX, highX: highX, lowY: lowY, highY: highY)
                }
                if area > 0 { own[base + row * 4 + col] += area }
            }
        }
    }

    /// Area of a convex quad clipped to a rectangle (Sutherland–Hodgman, only against the edges the
    /// quad's box crosses).
    private func clippedArea(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double,
                             _ cx: Double, _ cy: Double, _ dx: Double, _ dy: Double,
                             x0: Double, x1: Double, y0: Double, y1: Double,
                             lowX: Double, highX: Double, lowY: Double, highY: Double) -> Double {
        var input = polygonA, output = polygonB
        input[0] = ax; input[1] = ay; input[2] = bx; input[3] = by
        input[4] = cx; input[5] = cy; input[6] = dx; input[7] = dy
        var n = 4
        for edge in 0..<4 {
            switch edge {
            case 0: if lowX >= x0 { continue }
            case 1: if highX <= x1 { continue }
            case 2: if lowY >= y0 { continue }
            default: if highY <= y1 { continue }
            }
            var m = 0
            for i in 0..<n {
                let px = input[i * 2], py = input[i * 2 + 1]
                let j = i + 1 == n ? 0 : i + 1
                let qx = input[j * 2], qy = input[j * 2 + 1]
                let dp = Self.distance(edge, px, py, x0, x1, y0, y1)
                let dq = Self.distance(edge, qx, qy, x0, x1, y0, y1)
                if dp >= 0 {
                    output[m * 2] = px; output[m * 2 + 1] = py; m += 1
                }
                if (dp >= 0) != (dq >= 0) {
                    let t = dp / (dp - dq)
                    output[m * 2] = px + t * (qx - px); output[m * 2 + 1] = py + t * (qy - py); m += 1
                }
            }
            n = m
            if n == 0 { return 0 }
            swap(&input, &output)
        }
        var twice = 0.0
        for i in 0..<n {
            let j = i + 1 == n ? 0 : i + 1
            twice += input[i * 2] * input[j * 2 + 1] - input[j * 2] * input[i * 2 + 1]
        }
        return abs(twice) / 2
    }

    /// Signed distance inside edge `edge` of the rectangle (≥ 0 inside).
    @inline(__always)
    private static func distance(_ edge: Int, _ x: Double, _ y: Double, _ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double) -> Double {
        switch edge {
        case 0: return x - x0
        case 1: return x1 - x
        case 2: return y - y0
        default: return y1 - y
        }
    }
}
