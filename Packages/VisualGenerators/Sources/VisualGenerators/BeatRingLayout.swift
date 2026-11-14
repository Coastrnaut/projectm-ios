// BeatRingLayout.swift — the beat rings' geometry on the CPU (VIS-006-R3, R7, R8, R14; contracts/beat-rings.md
// C1; research VIS-006-D4).
//
// Per frame: the field's live rings at the frame time (oldest first). Ring i of radius r (fraction of half the
// shorter side) is an annulus of thickness T = max(thickness × the shorter side, 1 px) centred on r·R (R =
// min(W, H)/2; the inner edge never below 0), cut into 64 flat segments: segment j is the convex quad between
// angles 2π·j/64 and 2π·(j + 1)/64 clockwise from the top, inner and outer chord (screen model W × H pixels,
// y down). Every segment of a ring has palette color (sequence mod 16) of 16 with the ring's alpha, so the
// shared premultiplied pass draws it at α.
//
// The strobe safety envelope (FX-019-R4, R9): regions are the segments, colored with their alpha. Rings
// overlap only briefly after a birth; overlapping light is counted twice: an overestimate, never an
// underestimate.
//
// Real-time safety (Constitution VII): every buffer (and the sine and cosine tables) is allocated in `init`.
// Not Sendable: one owner.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import FlashSafety

public final class BeatRingLayout: FlashAreaLevelSource {
    public static let segmentsPerRing = BeatRingConfiguration.segmentsPerRing
    public static let regionCapacity = BeatRingConfiguration.maximumRings * BeatRingConfiguration.segmentsPerRing
    /// Six vertices per segment.
    public static let maximumVertexCount = regionCapacity * 6

    public var configuration: BeatRingConfiguration {
        didSet { configuration = configuration.clamped() }
    }

    public private(set) var width = 0
    public private(set) var height = 0
    /// Rings of the last layout (0 at size 0).
    public private(set) var ringCount = 0
    /// T in pixels of the last layout.
    public private(set) var thicknessPixels = 1.0

    private let rings: UnsafeMutablePointer<BeatRing>
    private let sines: UnsafeMutablePointer<Double>      // segmentsPerRing + 1 (the last equals the first)
    private let cosines: UnsafeMutablePointer<Double>
    /// Per region: 4 corners (x, y interleaved), and its area.
    private let quads: UnsafeMutablePointer<Double>
    private let areas: UnsafeMutablePointer<Double>
    /// Per ring: its color with the ring's alpha.
    private let ringColors: UnsafeMutablePointer<LinearColor>
    private let flashAreas = SpectrumFlashAreas(regionCapacity: BeatRingLayout.regionCapacity)
    private var generation = 0

    public init(configuration: BeatRingConfiguration = BeatRingConfiguration()) {
        self.configuration = configuration.clamped()
        let n = Self.segmentsPerRing, regions = Self.regionCapacity, ringsMax = BeatRingConfiguration.maximumRings
        rings = .allocate(capacity: ringsMax)
        rings.initialize(repeating: BeatRing(sequence: 0, birthNanoseconds: 0, age: 0, radius: 0, alpha: 0), count: ringsMax)
        sines = .allocate(capacity: n + 1); cosines = .allocate(capacity: n + 1)
        for j in 0...n {
            let theta: Double = 2 * Double.pi * Double(j % n) / Double(n)
            (sines + j).initialize(to: sin(theta))
            (cosines + j).initialize(to: cos(theta))
        }
        quads = .allocate(capacity: 8 * regions); quads.initialize(repeating: 0, count: 8 * regions)
        areas = .allocate(capacity: regions); areas.initialize(repeating: 0, count: regions)
        ringColors = .allocate(capacity: ringsMax); ringColors.initialize(repeating: .opaqueBlack, count: ringsMax)
    }

    deinit {
        let n = Self.segmentsPerRing, regions = Self.regionCapacity, ringsMax = BeatRingConfiguration.maximumRings
        rings.deinitialize(count: ringsMax); rings.deallocate()
        sines.deinitialize(count: n + 1); sines.deallocate()
        cosines.deinitialize(count: n + 1); cosines.deallocate()
        quads.deinitialize(count: 8 * regions); quads.deallocate()
        areas.deinitialize(count: regions); areas.deallocate()
        ringColors.deinitialize(count: ringsMax); ringColors.deallocate()
    }

    // Storage introspection for the allocation tests (VIS-006-R14).
    var storageAddresses: [UInt] {
        [UInt(bitPattern: rings), UInt(bitPattern: sines), UInt(bitPattern: cosines), UInt(bitPattern: quads),
         UInt(bitPattern: areas), UInt(bitPattern: ringColors)]
    }

    /// Segments of the last layout (64 per ring).
    public var segmentCount: Int { ringCount * Self.segmentsPerRing }

    /// Ring `i` (oldest first) of the last layout.
    public func ring(_ i: Int) -> BeatRing { rings[i] }

    /// Region `k`'s corners in pixels (inner start, outer start, outer end, inner end).
    public func quad(_ k: Int) -> [Double] { (0..<8).map { (i: Int) -> Double in quads[8 * k + i] } }

    /// Lays out `field`'s live rings at `nanoseconds` for a `width × height` output.
    public func layout(field: BeatRingField, atNanoseconds nanoseconds: UInt64, width: Int, height: Int) {
        let c = configuration
        generation &+= 1
        self.width = max(width, 0)
        self.height = max(height, 0)
        var count = 0
        let target = rings
        field.forEachRing(atNanoseconds: nanoseconds, life: c.life) { (ring: BeatRing) -> Void in
            guard count < BeatRingConfiguration.maximumRings else { return }
            target[count] = ring
            count += 1
        }
        guard self.width > 0, self.height > 0 else {
            ringCount = 0   // nothing is drawn at size 0
            return
        }
        ringCount = count
        buildGeometry()
    }

    private func buildGeometry() {
        let c = configuration
        let fw = Double(width), fh = Double(height)
        let shorter: Double = min(fw, fh)
        let big: Double = shorter / 2
        let cx: Double = fw / 2, cy: Double = fh / 2
        let t: Double = max(c.lineThickness * shorter, 1)
        thicknessPixels = t
        let n = Self.segmentsPerRing
        for i in 0..<ringCount {
            let ring = rings[i]
            let base: LinearColor = c.palette.color(bar: ring.sequence % BeatRingConfiguration.paletteColors,
                                                    of: BeatRingConfiguration.paletteColors)
            ringColors[i] = LinearColor(red: base.red, green: base.green, blue: base.blue, alpha: Float(ring.alpha))
            let centre: Double = ring.radius * big
            let inner: Double = max(centre - t / 2, 0)
            let outer: Double = centre + t / 2
            for j in 0..<n {
                setQuad(i * n + j, cx: cx, cy: cy, inner: inner, outer: outer, j: j)
            }
        }
    }

    private func setQuad(_ k: Int, cx: Double, cy: Double, inner: Double, outer: Double, j: Int) {
        let s0: Double = sines[j], c0: Double = cosines[j], s1: Double = sines[j + 1], c1: Double = cosines[j + 1]
        let q = quads + 8 * k
        q[0] = cx + inner * s0; q[1] = cy - inner * c0
        q[2] = cx + outer * s0; q[3] = cy - outer * c0
        q[4] = cx + outer * s1; q[5] = cy - outer * c1
        q[6] = cx + inner * s1; q[7] = cy - inner * c1
        // Shoelace (a trapezoid, or a triangle when the inner edge is the centre).
        let twice: Double = (q[0] * q[3] - q[2] * q[1]) + (q[2] * q[5] - q[4] * q[3])
            + (q[4] * q[7] - q[6] * q[5]) + (q[6] * q[1] - q[0] * q[7])
        areas[k] = abs(twice) / 2
    }

    /// Two triangles per drawn segment (whole shapes only, at most `capacity` vertices); returns the vertex
    /// count. `gain` scales colors.
    public func tessellate(into out: UnsafeMutablePointer<SpectrumVertex>, capacity: Int, gain: Float) -> Int {
        guard width > 0, height > 0 else { return 0 }
        let sx: Double = 2 / Double(width), sy: Double = 2 / Double(height)
        var count = 0
        for k in 0..<segmentCount where areas[k] > 0 {
            guard count + 6 <= capacity else { return count }
            let q = quads + 8 * k
            let color = ringColors[k / Self.segmentsPerRing]
            // NDC: x = 2·px/W − 1, y = 1 − 2·py/H.
            let a = SpectrumVertex(x: Float(q[0] * sx - 1), y: Float(1 - q[1] * sy), color: color, gain: gain)
            let b = SpectrumVertex(x: Float(q[2] * sx - 1), y: Float(1 - q[3] * sy), color: color, gain: gain)
            let c = SpectrumVertex(x: Float(q[4] * sx - 1), y: Float(1 - q[5] * sy), color: color, gain: gain)
            let d = SpectrumVertex(x: Float(q[6] * sx - 1), y: Float(1 - q[7] * sy), color: color, gain: gain)
            out[count] = a; out[count + 1] = b; out[count + 2] = c
            out[count + 3] = a; out[count + 4] = c; out[count + 5] = d
            count += 6
        }
        return count
    }

    /// The frame's levels in the strobe safety envelope's 17 areas (FX-019-R4) when drawn with `gain` and
    /// passed through `transfer`. No allocation.
    public func meanLevels<Transfer: FrameLuminanceTransfer>(gain: Float, transfer: Transfer,
                                                             into out: UnsafeMutableBufferPointer<FlashLevels>) {
        flashAreas.levels(of: self, generation: generation, gain: gain, transfer: transfer, into: out)
    }
}

// MARK: - The envelope's region model (FX-019-R4; VIS-006-R8)

extension BeatRingLayout: FlashRegionLayout {
    var flashRegionCount: Int { segmentCount }
    var flashBackground: LinearColor { configuration.background }

    func flashRegionArea(_ k: Int) -> Double { ringColors[k / Self.segmentsPerRing].alpha > 0 ? areas[k] : 0 }

    func flashRegionColor(_ k: Int) -> LinearColor { ringColors[k / Self.segmentsPerRing] }

    func forEachFlashQuad(ofRegion k: Int,
                          _ body: (Double, Double, Double, Double, Double, Double, Double, Double) -> Void) {
        guard areas[k] > 0 else { return }
        let q = quads + 8 * k
        body(q[0], q[1], q[2], q[3], q[4], q[5], q[6], q[7])
    }
}
