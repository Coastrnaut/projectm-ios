// MandalaLayout.swift — the mandala's geometry on the CPU (VIS-007-R2 to R7, R14; contracts/mandala.md C1;
// research VIS-007-D2 to D5).
//
// Per frame: the bands' three group energies → sector 0's petal (one, or two with Mirror), 12 flat quads from
// the inner radius to the tip → N copies, sector k being sector 0 rotated clockwise by 2πk/N about the centre
// (screen model W × H pixels, y down; angles clockwise from the top). The whole figure turns by ψ, a function
// of the injected frame time through a rotation anchor (time, angle, speed): a change of the effective speed
// (Reduce Motion) moves the anchor to that frame, so the angle stays continuous.
//
// Region k = (sector × petalsPerSector + petal) × 12 + step. Its corners: inner-left, outer-left, outer-right,
// inner-right. Every quad of step i has palette color (i of 12) with the frame's alpha, so the shared
// premultiplied pass draws it at α. Petals stay inside their sector (or half-sector), so regions never overlap
// and the strobe safety envelope's areas are exact (FX-019-R4, R9).
//
// Real-time safety (Constitution VII): every buffer is allocated in `init`. Not Sendable: one owner.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import FlashSafety

public final class MandalaLayout: FlashAreaLevelSource {
    public static let stepsPerPetal = MandalaConfiguration.stepsPerPetal
    public static let regionCapacity = MandalaConfiguration.maximumSymmetry * 2 * MandalaConfiguration.stepsPerPetal
    /// Six vertices per quad.
    public static let maximumVertexCount = regionCapacity * 6

    public var configuration: MandalaConfiguration {
        didSet { configuration = configuration.clamped() }
    }

    public private(set) var width = 0
    public private(set) var height = 0
    /// Sectors of the last layout (N; 0 at size 0).
    public private(set) var sectorCount = 0
    /// Quads per sector of the last layout (12, or 24 with Mirror).
    public private(set) var regionsPerSector = 0
    /// ψ of the last layout, radians in 0..<2π (clockwise).
    public private(set) var angle = 0.0
    /// The band groups and alpha of the last layout.
    public private(set) var groups = MandalaBandGroups.silence
    public private(set) var alpha = MandalaConfiguration.baseAlpha

    // Rotation anchor (research VIS-007-D5): the angle in turns at `anchorNanoseconds` and the speed since.
    private var anchorNanoseconds: UInt64 = 0
    private var anchorTurns = 0.0
    private var anchorSpeed: Double

    /// Per region: 4 corners (x, y interleaved), and its area.
    private let quads: UnsafeMutablePointer<Double>
    private let areas: UnsafeMutablePointer<Double>
    /// Sector 0's corners relative to the centre (before the per-sector rotation): 2 petals × 12 steps × 8.
    private let local: UnsafeMutablePointer<Double>
    /// Per step: its palette color with the frame's alpha.
    private let stepColors: UnsafeMutablePointer<LinearColor>
    private let flashAreas = SpectrumFlashAreas(regionCapacity: MandalaLayout.regionCapacity)
    private var generation = 0

    public init(configuration: MandalaConfiguration = MandalaConfiguration()) {
        self.configuration = configuration.clamped()
        anchorSpeed = self.configuration.effectiveTurnsPerSecond
        let regions = Self.regionCapacity
        quads = .allocate(capacity: 8 * regions); quads.initialize(repeating: 0, count: 8 * regions)
        areas = .allocate(capacity: regions); areas.initialize(repeating: 0, count: regions)
        local = .allocate(capacity: 16 * Self.stepsPerPetal); local.initialize(repeating: 0, count: 16 * Self.stepsPerPetal)
        stepColors = .allocate(capacity: Self.stepsPerPetal)
        stepColors.initialize(repeating: .opaqueBlack, count: Self.stepsPerPetal)
    }

    deinit {
        let regions = Self.regionCapacity
        quads.deinitialize(count: 8 * regions); quads.deallocate()
        areas.deinitialize(count: regions); areas.deallocate()
        local.deinitialize(count: 16 * Self.stepsPerPetal); local.deallocate()
        stepColors.deinitialize(count: Self.stepsPerPetal); stepColors.deallocate()
    }

    // Storage introspection for the allocation tests (VIS-007-R14).
    var storageAddresses: [UInt] {
        [UInt(bitPattern: quads), UInt(bitPattern: areas), UInt(bitPattern: local), UInt(bitPattern: stepColors)]
    }

    /// Quads of the last layout.
    public var regionCount: Int { sectorCount * regionsPerSector }

    /// Region `k`'s corners in pixels (inner-left, outer-left, outer-right, inner-right; x, y interleaved).
    public func quad(_ k: Int) -> [Double] { (0..<8).map { (i: Int) -> Double in quads[8 * k + i] } }

    /// Region `k`'s color with the frame's alpha.
    public func color(ofRegion k: Int) -> LinearColor { stepColors[k % Self.stepsPerPetal] }

    /// The figure's rotation in radians (0..<2π) at `nanoseconds` for the current anchor and speed. Does not
    /// move the anchor.
    public func angle(atNanoseconds nanoseconds: UInt64) -> Double {
        2 * Double.pi * turns(atNanoseconds: nanoseconds, speed: anchorSpeed)
    }

    private func turns(atNanoseconds nanoseconds: UInt64, speed: Double) -> Double {
        let elapsed: Double = Double(Int64(bitPattern: nanoseconds &- anchorNanoseconds)) * 1e-9
        let raw: Double = anchorTurns + speed * elapsed
        let fraction: Double = raw - raw.rounded(.down)
        return fraction.isFinite ? fraction : 0
    }

    /// Lays out `bands` at `nanoseconds` for a `width × height` output.
    public func layout(bands: UnsafeBufferPointer<Float>, atNanoseconds nanoseconds: UInt64, width: Int, height: Int) {
        layout(groups: MandalaBandGroups.from(bands), atNanoseconds: nanoseconds, width: width, height: height)
    }

    /// Lays out the group energies `groups` (each clamped to 0…1) at `nanoseconds`.
    public func layout(groups input: MandalaBandGroups, atNanoseconds nanoseconds: UInt64, width: Int, height: Int) {
        let c = configuration
        generation &+= 1
        // Re-anchor on a speed change so the angle continues (VIS-007-R5).
        let speed: Double = c.effectiveTurnsPerSecond
        if speed != anchorSpeed {
            anchorTurns = turns(atNanoseconds: nanoseconds, speed: anchorSpeed)
            anchorNanoseconds = nanoseconds
            anchorSpeed = speed
        }
        angle = 2 * Double.pi * turns(atNanoseconds: nanoseconds, speed: speed)
        groups = MandalaBandGroups(low: Self.unit(input.low), mid: Self.unit(input.mid), high: Self.unit(input.high))
        alpha = MandalaConfiguration.alpha(overall: groups.overall)
        self.width = max(width, 0)
        self.height = max(height, 0)
        guard self.width > 0, self.height > 0 else {
            sectorCount = 0   // nothing is drawn at size 0
            regionsPerSector = 0
            return
        }
        sectorCount = c.symmetry
        regionsPerSector = c.petalsPerSector * Self.stepsPerPetal
        for i in 0..<Self.stepsPerPetal {
            let base: LinearColor = c.palette.color(bar: i, of: Self.stepsPerPetal)
            stepColors[i] = LinearColor(red: base.red, green: base.green, blue: base.blue, alpha: Float(alpha))
        }
        buildSectorZero()
        buildSectors()
    }

    private static func unit(_ v: Double) -> Double { v.isFinite ? min(max(v, 0), 1) : 0 }

    /// Sector 0's petal (and its mirror image) relative to the centre, before rotation by ψ.
    private func buildSectorZero() {
        let c = configuration
        let big: Double = Double(min(width, height)) / 2
        let half: Double = Double.pi / Double(c.symmetry)   // half the sector angle
        let sigma: Double = c.mirror ? half / 2 : half      // the petal's angular half-span
        let inner: Double = MandalaConfiguration.innerRadius
        let tip: Double = MandalaConfiguration.tipRadius(low: groups.low)
        let widest: Double = MandalaConfiguration.widestHalfWidth(mid: groups.mid) * sigma
        let curl: Double = MandalaConfiguration.tipCurl(high: groups.high) * sigma
        let n = Self.stepsPerPetal
        for i in 0..<n {
            let t0: Double = Double(i) / Double(n), t1: Double = Double(i + 1) / Double(n)
            let r0: Double = (inner + (tip - inner) * t0) * big, r1: Double = (inner + (tip - inner) * t1) * big
            let c0: Double = sigma + curl * t0 * t0, c1: Double = sigma + curl * t1 * t1
            let h0: Double = widest * c.petalStyle.profile(t0), h1: Double = widest * c.petalStyle.profile(t1)
            let p = local + 8 * i
            Self.polar(r0, c0 - h0, into: p)        // inner-left
            Self.polar(r1, c1 - h1, into: p + 2)    // outer-left
            Self.polar(r1, c1 + h1, into: p + 4)    // outer-right
            Self.polar(r0, c0 + h0, into: p + 6)    // inner-right
            guard c.mirror else { continue }
            // The reflection across the sector's centre line (angle 2σ): φ → 4σ − φ; left and right swap so the
            // corner order (and winding) is kept.
            let m = local + 8 * (n + i)
            Self.polar(r0, 4 * sigma - (c0 + h0), into: m)
            Self.polar(r1, 4 * sigma - (c1 + h1), into: m + 2)
            Self.polar(r1, 4 * sigma - (c1 - h1), into: m + 4)
            Self.polar(r0, 4 * sigma - (c0 - h0), into: m + 6)
        }
    }

    /// (x, y) relative to the centre of radius `r` at `phi` clockwise from the top (y down).
    @inline(__always)
    private static func polar(_ r: Double, _ phi: Double, into p: UnsafeMutablePointer<Double>) {
        p[0] = r * sin(phi)
        p[1] = -r * cos(phi)
    }

    /// N copies: sector k = sector 0 rotated clockwise by ψ + 2πk/N, then moved to the centre.
    private func buildSectors() {
        let cx: Double = Double(width) / 2, cy: Double = Double(height) / 2
        let perSector = regionsPerSector
        let corners = 4 * perSector
        // Sector 0 rotated by ψ, written in place (region 0…perSector − 1, relative to the centre).
        let cosPsi: Double = cos(angle), sinPsi: Double = sin(angle)
        for j in 0..<corners {
            let x: Double = local[2 * j], y: Double = local[2 * j + 1]
            quads[2 * j] = x * cosPsi - y * sinPsi
            quads[2 * j + 1] = y * cosPsi + x * sinPsi
        }
        // Sectors N−1…1 from sector 0 by 2πk/N (exact copies: one rotation each), then sector 0 itself.
        for k in stride(from: sectorCount - 1, through: 0, by: -1) {
            let theta: Double = 2 * Double.pi * Double(k) / Double(sectorCount)
            let ck: Double = k == 0 ? 1 : cos(theta), sk: Double = k == 0 ? 0 : sin(theta)
            let target = quads + 8 * k * perSector
            for j in 0..<corners {
                let x: Double = quads[2 * j], y: Double = quads[2 * j + 1]
                target[2 * j] = cx + x * ck - y * sk
                target[2 * j + 1] = cy + y * ck + x * sk
            }
        }
        for k in 0..<regionCount {
            let q = quads + 8 * k
            // Shoelace (a convex quad, or a triangle at a zero-width end).
            let twice: Double = (q[0] * q[3] - q[2] * q[1]) + (q[2] * q[5] - q[4] * q[3])
                + (q[4] * q[7] - q[6] * q[5]) + (q[6] * q[1] - q[0] * q[7])
            areas[k] = abs(twice) / 2
        }
    }

    /// Two triangles per quad (whole quads only, at most `capacity` vertices); returns the vertex count.
    /// `gain` scales colors.
    public func tessellate(into out: UnsafeMutablePointer<SpectrumVertex>, capacity: Int, gain: Float) -> Int {
        guard width > 0, height > 0 else { return 0 }
        let sx: Double = 2 / Double(width), sy: Double = 2 / Double(height)
        var count = 0
        for k in 0..<regionCount {
            guard count + 6 <= capacity else { return count }
            let q = quads + 8 * k
            let color = stepColors[k % Self.stepsPerPetal]
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

// MARK: - The envelope's region model (FX-019-R4; VIS-007-R8)

extension MandalaLayout: FlashRegionLayout {
    var flashRegionCount: Int { regionCount }
    var flashBackground: LinearColor { configuration.background }

    func flashRegionArea(_ k: Int) -> Double { areas[k] }

    func flashRegionColor(_ k: Int) -> LinearColor { stepColors[k % Self.stepsPerPetal] }

    func forEachFlashQuad(ofRegion k: Int,
                          _ body: (Double, Double, Double, Double, Double, Double, Double, Double) -> Void) {
        guard areas[k] > 0 else { return }
        let q = quads + 8 * k
        body(q[0], q[1], q[2], q[3], q[4], q[5], q[6], q[7])
    }
}
