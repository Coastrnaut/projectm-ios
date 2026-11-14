// ParticleOrbitLayout.swift — the particle orbit's geometry on the CPU (VIS-009-R5, R7, R8; contracts/particle-orbit.md
// C2; research VIS-009-D6).
//
// Per frame: square 0 is the centre (side 0.12·R·(1 + A·pulse), palette colour 0, alpha 0.7); squares 1…n are the
// particles, slot k centred at (W/2 + R·r·o_k·cos φ_k, H/2 − R·r·o_k·sin φ_k), side max(size·R, 2 px), colour
// palette(k mod 16) of 16 with alpha 0.75, where R = min(W, H)/2 and r is the simulation's radius. The squares are the
// strobe safety envelope's regions (FX-019-R4, R9); overlaps count twice (an overestimate).
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

public final class ParticleOrbitLayout: FlashAreaLevelSource {
    /// The centre plus every particle.
    public static let regionCapacity = ParticleOrbitConfiguration.capacity + 1
    /// Six vertices per square.
    public static let maximumVertexCount = regionCapacity * 6

    public private(set) var width = 0
    public private(set) var height = 0
    /// Squares of the last layout (0 at size 0).
    public private(set) var squareCount = 0
    /// The radius (R) the last layout drew the ring at.
    public private(set) var drawnRadius = 0.0
    /// The background of the last layout.
    public private(set) var background: LinearColor = .opaqueBlack

    /// Per square: 4 corners (x, y interleaved: top-left, top-right, bottom-right, bottom-left), pixels.
    private let quads: UnsafeMutablePointer<Double>
    private let colors: UnsafeMutablePointer<LinearColor>
    private let sides: UnsafeMutablePointer<Double>
    private let flashAreas = SpectrumFlashAreas(regionCapacity: ParticleOrbitLayout.regionCapacity)
    private var generation = 0

    public init() {
        let n = Self.regionCapacity
        quads = .allocate(capacity: 8 * n); quads.initialize(repeating: 0, count: 8 * n)
        colors = .allocate(capacity: n); colors.initialize(repeating: .opaqueBlack, count: n)
        sides = .allocate(capacity: n); sides.initialize(repeating: 0, count: n)
    }

    deinit {
        let n = Self.regionCapacity
        quads.deinitialize(count: 8 * n); quads.deallocate()
        colors.deinitialize(count: n); colors.deallocate()
        sides.deinitialize(count: n); sides.deallocate()
    }

    // Storage introspection for the allocation tests.
    var storageAddresses: [UInt] { [UInt(bitPattern: quads), UInt(bitPattern: colors), UInt(bitPattern: sides)] }

    /// Square `k`'s corners in pixels (top-left, top-right, bottom-right, bottom-left).
    public func quad(_ k: Int) -> [Double] { (0..<8).map { (i: Int) -> Double in quads[8 * k + i] } }

    /// Square `k`'s centre in pixels.
    public func center(_ k: Int) -> (x: Double, y: Double) {
        let q = quads + 8 * k
        return ((q[0] + q[4]) / 2, (q[1] + q[5]) / 2)
    }

    /// Square `k`'s side in pixels.
    public func side(_ k: Int) -> Double { sides[k] }

    /// Square `k`'s colour (alpha = its alpha).
    public func color(_ k: Int) -> LinearColor { colors[k] }

    /// Lays out `simulation` for a `width × height` output. Does not advance the simulation.
    public func layout(simulation: ParticleOrbitSimulation, width: Int, height: Int) {
        let c = simulation.configuration
        generation &+= 1
        background = c.background
        drawnRadius = simulation.radius
        self.width = max(width, 0)
        self.height = max(height, 0)
        guard self.width > 0, self.height > 0 else {
            squareCount = 0   // nothing is drawn at size 0
            return
        }
        let fw = Double(self.width), fh = Double(self.height)
        let big: Double = min(fw, fh) / 2
        let cx: Double = fw / 2, cy: Double = fh / 2
        let minimum: Double = ParticleOrbitConfiguration.minimumSidePixels
        let core: Double = max(ParticleOrbitConfiguration.coreSize * big * (1 + c.effectivePulseAmplitude * simulation.pulse), minimum)
        let base0: LinearColor = c.palette.color(bar: 0, of: ParticleOrbitConfiguration.paletteColors)
        place(0, x: cx, y: cy, side: core,
              color: LinearColor(red: base0.red, green: base0.green, blue: base0.blue, alpha: Float(ParticleOrbitConfiguration.coreAlpha)))
        let side: Double = max(c.particleSize * big, minimum)
        let ring: Double = big * simulation.radius
        let alpha = Float(ParticleOrbitConfiguration.particleAlpha)
        let n = min(simulation.count, ParticleOrbitConfiguration.capacity)
        for k in 0..<n {
            let phi: Double = simulation.phase(k)
            let r: Double = ring * simulation.offset(k)
            let base: LinearColor = c.palette.color(bar: k % ParticleOrbitConfiguration.paletteColors,
                                                    of: ParticleOrbitConfiguration.paletteColors)
            place(k + 1, x: cx + r * cos(phi), y: cy - r * sin(phi), side: side,
                  color: LinearColor(red: base.red, green: base.green, blue: base.blue, alpha: alpha))
        }
        squareCount = n + 1
    }

    private func place(_ k: Int, x: Double, y: Double, side: Double, color: LinearColor) {
        let half: Double = side / 2
        let q = quads + 8 * k
        q[0] = x - half; q[1] = y - half
        q[2] = x + half; q[3] = y - half
        q[4] = x + half; q[5] = y + half
        q[6] = x - half; q[7] = y + half
        sides[k] = side
        colors[k] = color
    }

    /// Two triangles per square (whole squares only, at most `capacity` vertices); returns the vertex count.
    /// `gain` scales colours.
    public func tessellate(into out: UnsafeMutablePointer<SpectrumVertex>, capacity: Int, gain: Float) -> Int {
        guard width > 0, height > 0 else { return 0 }
        let sx: Double = 2 / Double(width), sy: Double = 2 / Double(height)
        var count = 0
        for k in 0..<squareCount {
            guard count + 6 <= capacity else { return count }
            let q = quads + 8 * k
            let color = colors[k]
            // NDC: x = 2·px/W − 1, y = 1 − 2·py/H.
            let a = SpectrumVertex(x: Float(q[0] * sx - 1), y: Float(1 - q[1] * sy), color: color, gain: gain)
            let b = SpectrumVertex(x: Float(q[2] * sx - 1), y: Float(1 - q[3] * sy), color: color, gain: gain)
            let d = SpectrumVertex(x: Float(q[4] * sx - 1), y: Float(1 - q[5] * sy), color: color, gain: gain)
            let e = SpectrumVertex(x: Float(q[6] * sx - 1), y: Float(1 - q[7] * sy), color: color, gain: gain)
            out[count] = a; out[count + 1] = b; out[count + 2] = d
            out[count + 3] = a; out[count + 4] = d; out[count + 5] = e
            count += 6
        }
        return count
    }

    /// The frame's levels in the strobe safety envelope's 17 areas (FX-019-R4) when drawn with `gain` and passed
    /// through `transfer`. No allocation.
    public func meanLevels<Transfer: FrameLuminanceTransfer>(gain: Float, transfer: Transfer,
                                                             into out: UnsafeMutableBufferPointer<FlashLevels>) {
        flashAreas.levels(of: self, generation: generation, gain: gain, transfer: transfer, into: out)
    }
}

// MARK: - The envelope's region model (FX-019-R4; VIS-009-R8)

extension ParticleOrbitLayout: FlashRegionLayout {
    var flashRegionCount: Int { squareCount }
    var flashBackground: LinearColor { background }

    func flashRegionArea(_ k: Int) -> Double { sides[k] * sides[k] }

    func flashRegionColor(_ k: Int) -> LinearColor { colors[k] }

    func forEachFlashQuad(ofRegion k: Int,
                          _ body: (Double, Double, Double, Double, Double, Double, Double, Double) -> Void) {
        let q = quads + 8 * k
        body(q[0], q[1], q[2], q[3], q[4], q[5], q[6], q[7])
    }
}
