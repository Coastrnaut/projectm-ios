// StarfieldLayout.swift — the starfield's squares on the CPU (VIS-016-R5, R7; contract S5; research VIS-016-D4).
//
// Per frame, for the first `activeCount` stars of the pool: centre (W/2 + x·f·R/z, H/2 − y·f·R/z) with f = 0.5 and
// R = min(W, H)/2; side clamp(0.004·R/z, 1 px, 0.04·R); alpha min(0.12/z, 0.8) × fade-in (over 0.15 of depth after the
// far plane) × fade-out (over 0.05 before the near plane); colour half white, half palette(k mod 16 of 16). Squares
// wholly outside the frame are not drawn. Total light (VIS-016-R7): when Σ side²·alpha·Y / (W·H) exceeds 0.05, every
// alpha is scaled by the same factor so the mean is 0.05 (a square's whole area counts, even past the edge: an
// overestimate). The squares are the strobe safety envelope's regions (FX-019-R4, R9); overlaps count twice.
//
// Real-time safety (Constitution VII): every buffer is allocated in `init`. Not Sendable: one owner.
import FlashSafety

public final class StarfieldLayout: FlashAreaLevelSource {
    public static let regionCapacity = StarfieldConfiguration.capacity
    /// Six vertices per square.
    public static let maximumVertexCount = regionCapacity * 6

    public private(set) var width = 0
    public private(set) var height = 0
    /// Squares of the last layout.
    public private(set) var squareCount = 0
    /// The alpha factor the light bound applied (1 when under the bound).
    public private(set) var lightScale = 1.0
    /// The frame's mean light after the bound (relative luminance × coverage, 0…1).
    public private(set) var meanLight = 0.0
    public private(set) var background: LinearColor = .opaqueBlack

    /// Per square: centre x, y and side, pixels (y down); the pool index; colour (alpha = its alpha).
    private let centers: UnsafeMutablePointer<Double>
    private let sides: UnsafeMutablePointer<Double>
    private let indices: UnsafeMutablePointer<Int>
    private let colors: UnsafeMutablePointer<LinearColor>
    private let flashAreas = SpectrumFlashAreas(regionCapacity: StarfieldLayout.regionCapacity)
    private var generation = 0

    public init() {
        let n = Self.regionCapacity
        centers = .allocate(capacity: 2 * n); centers.initialize(repeating: 0, count: 2 * n)
        sides = .allocate(capacity: n); sides.initialize(repeating: 0, count: n)
        indices = .allocate(capacity: n); indices.initialize(repeating: 0, count: n)
        colors = .allocate(capacity: n); colors.initialize(repeating: .opaqueBlack, count: n)
    }

    deinit {
        let n = Self.regionCapacity
        centers.deinitialize(count: 2 * n); centers.deallocate()
        sides.deinitialize(count: n); sides.deallocate()
        indices.deinitialize(count: n); indices.deallocate()
        colors.deinitialize(count: n); colors.deallocate()
    }

    /// Square `k`'s centre in pixels.
    public func center(_ k: Int) -> (x: Double, y: Double) { (centers[2 * k], centers[2 * k + 1]) }
    /// Square `k`'s side in pixels.
    public func side(_ k: Int) -> Double { sides[k] }
    /// Square `k`'s pool index.
    public func starIndex(_ k: Int) -> Int { indices[k] }
    /// Square `k`'s colour (alpha = its alpha, after the light bound).
    public func color(_ k: Int) -> LinearColor { colors[k] }

    /// VIS-016-R5: a star's side (pixels) at depth `z` for a frame whose half shorter side is `big`.
    public static func side(z: Double, big: Double) -> Double {
        let raw: Double = StarfieldConfiguration.baseSide * big / max(z, StarfieldConfiguration.near)
        return max(min(raw, StarfieldConfiguration.maximumSide * big), StarfieldConfiguration.minimumSidePixels)
    }

    /// VIS-016-R5: a star's alpha at depth `z`, fades included (before the light bound).
    public static func alpha(z: Double) -> Double {
        let near: Double = StarfieldConfiguration.near
        let far: Double = StarfieldConfiguration.far
        let base: Double = min(StarfieldConfiguration.brightness / max(z, near), StarfieldConfiguration.maximumAlpha)
        let fadeIn: Double = min(max((far - z) / StarfieldConfiguration.fadeInDepth, 0), 1)
        let fadeOut: Double = min(max((z - near) / StarfieldConfiguration.fadeOutDepth, 0), 1)
        return base * fadeIn * fadeOut
    }

    /// Lays out `simulation` for a `width × height` output. Does not advance the simulation.
    public func layout(simulation: StarfieldSimulation, width: Int, height: Int) {
        let c = simulation.configuration
        generation &+= 1
        background = c.background
        self.width = max(width, 0)
        self.height = max(height, 0)
        squareCount = 0
        lightScale = 1
        meanLight = 0
        guard self.width > 0, self.height > 0 else { return }
        let fw = Double(self.width), fh = Double(self.height)
        let big: Double = min(fw, fh) / 2
        let cx: Double = fw / 2, cy: Double = fh / 2
        let reach: Double = StarfieldConfiguration.focal * big
        let n: Int = min(simulation.activeCount, StarfieldConfiguration.capacity)
        var light = 0.0
        for k in 0..<n {
            let s: Star = simulation.star(k)
            let side: Double = Self.side(z: s.z, big: big)
            let x: Double = cx + s.x * reach / s.z
            let y: Double = cy - s.y * reach / s.z
            let half: Double = side / 2
            guard x + half > 0, x - half < fw, y + half > 0, y - half < fh else { continue }   // outside: not drawn
            let a: Double = Self.alpha(z: s.z)
            guard a > 0 else { continue }
            let tint: LinearColor = c.palette.color(bar: k % StarfieldConfiguration.paletteColors, of: StarfieldConfiguration.paletteColors)
            let w: Float = StarfieldConfiguration.whiteShare
            let color = LinearColor(red: w + (1 - w) * tint.red, green: w + (1 - w) * tint.green,
                                    blue: w + (1 - w) * tint.blue, alpha: Float(a))
            let q = squareCount
            centers[2 * q] = x
            centers[2 * q + 1] = y
            sides[q] = side
            indices[q] = k
            colors[q] = color
            light += side * side * a * Double(color.relativeLuminance)
            squareCount += 1
        }
        let mean: Double = light / (fw * fh)
        if mean > StarfieldConfiguration.lightBound {
            lightScale = StarfieldConfiguration.lightBound / mean
            for q in 0..<squareCount { colors[q].alpha = Float(Double(colors[q].alpha) * lightScale) }
        }
        meanLight = min(mean, StarfieldConfiguration.lightBound)
    }

    /// Two triangles per square (whole squares only, at most `capacity` vertices); returns the vertex count.
    /// `gain` scales colours.
    public func tessellate(into out: UnsafeMutablePointer<SpectrumVertex>, capacity: Int, gain: Float) -> Int {
        guard width > 0, height > 0 else { return 0 }
        let sx: Double = 2 / Double(width), sy: Double = 2 / Double(height)
        var count = 0
        for k in 0..<squareCount {
            guard count + 6 <= capacity else { return count }
            let half: Double = sides[k] / 2
            let x0: Float = Float((centers[2 * k] - half) * sx - 1), x1: Float = Float((centers[2 * k] + half) * sx - 1)
            let y0: Float = Float(1 - (centers[2 * k + 1] - half) * sy), y1: Float = Float(1 - (centers[2 * k + 1] + half) * sy)
            let color = colors[k]
            let a = SpectrumVertex(x: x0, y: y0, color: color, gain: gain)
            let b = SpectrumVertex(x: x1, y: y0, color: color, gain: gain)
            let d = SpectrumVertex(x: x1, y: y1, color: color, gain: gain)
            let e = SpectrumVertex(x: x0, y: y1, color: color, gain: gain)
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

// MARK: - The envelope's region model (FX-019-R4; VIS-016-R7)

extension StarfieldLayout: FlashRegionLayout {
    var flashRegionCount: Int { squareCount }
    var flashBackground: LinearColor { background }

    func flashRegionArea(_ k: Int) -> Double { sides[k] * sides[k] }

    func flashRegionColor(_ k: Int) -> LinearColor { colors[k] }

    func forEachFlashQuad(ofRegion k: Int,
                          _ body: (Double, Double, Double, Double, Double, Double, Double, Double) -> Void) {
        let half: Double = sides[k] / 2
        let x: Double = centers[2 * k], y: Double = centers[2 * k + 1]
        body(x - half, y - half, x + half, y - half, x + half, y + half, x - half, y + half)
    }
}
