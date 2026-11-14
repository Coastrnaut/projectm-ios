// ParticleFountainLayout.swift — the particle fountain's geometry on the CPU (VIS-008-R7, R8; contracts/
// particle-fountain.md C2; research VIS-008-D7).
//
// Per frame: one axis-aligned square per live particle, side max(size·R, 2 px) (R = min(W, H)/2), centred at
// (W/2 + x·R, H − 0.1·R − y·R) in the screen model W × H pixels, y down; colour palette (sequence mod 16) of 16
// with alpha 0.8 × attack × fade, so the shared premultiplied pass draws it at α.
//
// The strobe safety envelope (FX-019-R4, R9): regions are the squares, coloured with their alpha. Overlapping
// particles are counted twice: an overestimate, never an underestimate.
//
// Real-time safety (Constitution VII): every buffer is allocated in `init`. Not Sendable: one owner.
import FlashSafety

public final class ParticleFountainLayout: FlashAreaLevelSource {
    public static let regionCapacity = ParticleFountainConfiguration.capacity
    /// Six vertices per square.
    public static let maximumVertexCount = regionCapacity * 6

    public private(set) var width = 0
    public private(set) var height = 0
    /// Squares of the last layout (0 at size 0).
    public private(set) var squareCount = 0
    /// The side in pixels of the last layout.
    public private(set) var sidePixels = 0.0
    /// The palette and background of the last layout.
    public private(set) var background: LinearColor = .opaqueBlack

    /// Per square: 4 corners (x, y interleaved: top-left, top-right, bottom-right, bottom-left).
    private let quads: UnsafeMutablePointer<Double>
    private let colors: UnsafeMutablePointer<LinearColor>
    private let flashAreas = SpectrumFlashAreas(regionCapacity: ParticleFountainLayout.regionCapacity)
    private var generation = 0

    public init() {
        let n = Self.regionCapacity
        quads = .allocate(capacity: 8 * n); quads.initialize(repeating: 0, count: 8 * n)
        colors = .allocate(capacity: n); colors.initialize(repeating: .opaqueBlack, count: n)
    }

    deinit {
        let n = Self.regionCapacity
        quads.deinitialize(count: 8 * n); quads.deallocate()
        colors.deinitialize(count: n); colors.deallocate()
    }

    // Storage introspection for the allocation tests.
    var storageAddresses: [UInt] { [UInt(bitPattern: quads), UInt(bitPattern: colors)] }

    /// Square `k`'s corners in pixels (top-left, top-right, bottom-right, bottom-left).
    public func quad(_ k: Int) -> [Double] { (0..<8).map { (i: Int) -> Double in quads[8 * k + i] } }

    /// Square `k`'s colour (alpha = the particle's alpha).
    public func color(_ k: Int) -> LinearColor { colors[k] }

    /// Lays out `simulation`'s live particles for a `width × height` output. Does not advance the simulation.
    public func layout(simulation: ParticleFountainSimulation, width: Int, height: Int) {
        let c = simulation.configuration
        generation &+= 1
        background = c.background
        self.width = max(width, 0)
        self.height = max(height, 0)
        guard self.width > 0, self.height > 0 else {
            squareCount = 0   // nothing is drawn at size 0
            return
        }
        let fw = Double(self.width), fh = Double(self.height)
        let big: Double = min(fw, fh) / 2
        let side: Double = max(c.particleSize * big, ParticleFountainConfiguration.minimumSidePixels)
        sidePixels = side
        let half: Double = side / 2
        let cx: Double = fw / 2
        let baseY: Double = fh - ParticleFountainConfiguration.emitterHeight * big
        let count = min(simulation.liveCount, Self.regionCapacity)
        for k in 0..<count {
            let p = simulation.particle(k)
            let px: Double = cx + p.x * big
            let py: Double = baseY - p.y * big
            let q = quads + 8 * k
            q[0] = px - half; q[1] = py - half
            q[2] = px + half; q[3] = py - half
            q[4] = px + half; q[5] = py + half
            q[6] = px - half; q[7] = py + half
            let base: LinearColor = c.palette.color(bar: p.sequence % ParticleFountainConfiguration.paletteColors,
                                                    of: ParticleFountainConfiguration.paletteColors)
            let alpha: Double = ParticleFountainConfiguration.alpha(age: p.age, life: p.life)
            colors[k] = LinearColor(red: base.red, green: base.green, blue: base.blue, alpha: Float(alpha))
        }
        squareCount = count
    }

    /// Two triangles per square (whole squares only, at most `capacity` vertices); returns the vertex count.
    /// `gain` scales colours.
    public func tessellate(into out: UnsafeMutablePointer<SpectrumVertex>, capacity: Int, gain: Float) -> Int {
        guard width > 0, height > 0 else { return 0 }
        let sx: Double = 2 / Double(width), sy: Double = 2 / Double(height)
        var count = 0
        for k in 0..<squareCount where colors[k].alpha > 0 {
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

// MARK: - The envelope's region model (FX-019-R4; VIS-008-R8)

extension ParticleFountainLayout: FlashRegionLayout {
    var flashRegionCount: Int { squareCount }
    var flashBackground: LinearColor { background }

    func flashRegionArea(_ k: Int) -> Double { colors[k].alpha > 0 ? sidePixels * sidePixels : 0 }

    func flashRegionColor(_ k: Int) -> LinearColor { colors[k] }

    func forEachFlashQuad(ofRegion k: Int,
                          _ body: (Double, Double, Double, Double, Double, Double, Double, Double) -> Void) {
        let q = quads + 8 * k
        body(q[0], q[1], q[2], q[3], q[4], q[5], q[6], q[7])
    }
}
