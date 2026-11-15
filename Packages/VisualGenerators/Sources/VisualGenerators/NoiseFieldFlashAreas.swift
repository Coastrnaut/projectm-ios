// NoiseFieldFlashAreas.swift — the noise field's levels in the strobe safety envelope's 17 areas (VIS-013-R6;
// research VIS-013-D4; FX-019-R4, R9).
//
// The field is not flat geometry, so its light is estimated from the CPU mirror (`SeededNoise`): an 8 × 8 grid of
// sample points (the cell centres; four per 4 × 4 safety tile) is evaluated with the frame's frequency, octaves,
// seed, warp and drift, and each sample's colour at gain 1 (palette × (0.25 + 0.75 n) × brightness, as the shader) is
// kept. VIS-014: with the kaleidoscope on, each sample point is folded first, exactly as the shader does. VIS-015: the
// tunnel's samples come from `TunnelMapping` (palette at its texture × light × brightness, as its shader). VIS-020: the
// waterfall's samples are `WaterfallFlashCells`' exact cell means. VIS-017: the SDF shapes' samples come from
// `SignedDistanceScene.shade` (the same bounded march as the shader).
// `levels(gain:transfer:into:)` gives each tile the mean of its four samples after the downstream stages, and
// the whole frame the mean of all 64. Exact at the sample points; the field is smooth at these scales. All storage is
// allocated in `init`; ≤ 64 × 3 × 6 noise evaluations per frame. Pure Swift (every platform). Not Sendable.
import FlashSafety

public final class NoiseFieldFlashAreas {
    public static let gridSide = 8
    public static let sampleCount = gridSide * gridSide

    /// Linear colours at gain 1, rows top first.
    private let colors: UnsafeMutablePointer<LinearColor>
    /// Noise values of the last `sample` call (tests).
    private let values: UnsafeMutablePointer<Float>
    /// 16 palette colours of the last `sample` call.
    private let palette: UnsafeMutablePointer<LinearColor>

    public init() {
        colors = .allocate(capacity: Self.sampleCount)
        colors.initialize(repeating: .opaqueBlack, count: Self.sampleCount)
        values = .allocate(capacity: Self.sampleCount)
        values.initialize(repeating: 0, count: Self.sampleCount)
        palette = .allocate(capacity: NoiseFieldConfiguration.paletteColors)
        palette.initialize(repeating: .opaqueBlack, count: NoiseFieldConfiguration.paletteColors)
    }

    deinit {
        colors.deinitialize(count: Self.sampleCount); colors.deallocate()
        values.deinitialize(count: Self.sampleCount); values.deallocate()
        palette.deinitialize(count: NoiseFieldConfiguration.paletteColors); palette.deallocate()
    }

    /// Sample k's noise value (row-major, rows top first).
    public func value(_ k: Int) -> Float { values[min(max(k, 0), Self.sampleCount - 1)] }
    /// Sample k's colour at gain 1.
    public func color(_ k: Int) -> LinearColor { colors[min(max(k, 0), Self.sampleCount - 1)] }

    /// The pixel position (x, y; pixel units, rows top first) of sample (column, row) in a `width × height` output.
    public static func samplePoint(column: Int, row: Int, width: Int, height: Int) -> SIMD2<Float> {
        let side: Float = Float(gridSide)
        return SIMD2<Float>((Float(column) + 0.5) / side * Float(width), (Float(row) + 0.5) / side * Float(height))
    }

    /// The palette colour at noise value `n` from 16 stops in linear light (the shader's interpolation).
    public static func paletteColor(_ n: Float, stops: UnsafePointer<LinearColor>) -> LinearColor {
        let position: Float = NoiseFieldConfiguration.paletteT(n) * Float(NoiseFieldConfiguration.paletteColors - 1)
        let i: Int = min(Int(position), NoiseFieldConfiguration.paletteColors - 2)
        let f: Float = position - Float(i)
        let a: LinearColor = stops[i], b: LinearColor = stops[i + 1]
        return LinearColor(red: a.red + (b.red - a.red) * f, green: a.green + (b.green - a.green) * f,
                           blue: a.blue + (b.blue - a.blue) * f, alpha: 1)
    }

    /// VIS-014: the domain point of pixel centre `pixel` folded into the kaleidoscope's first half-wedge, then scaled and
    /// drifted (the shader: `p` relative to the centre over the shorter side → `vis_kfold` → × scale + (phase, phase / 2)).
    public static func foldedDomainPoint(_ pixel: SIMD2<Float>, width: Int, height: Int, scale: Float, phase: Float,
                                         fold: KaleidoscopeFold) -> SIMD2<Float> {
        let size: SIMD2<Float> = SIMD2(Float(max(width, 1)), Float(max(height, 1)))
        let p: SIMD2<Float> = (pixel - 0.5 * size) / min(size.x, size.y)
        return fold.fold(p) * scale + SIMD2<Float>(phase, 0.5 * phase)
    }

    /// Evaluates the 64 samples for this frame. `paletteStops` holds 16 colours.
    public func sample(configuration c: NoiseFieldConfiguration, drive: NoiseFieldDrive, paletteStops: UnsafePointer<LinearColor>,
                       width: Int, height: Int) {
        let w: Int = max(width, 1), h: Int = max(height, 1)
        let seed: UInt32 = UInt32(c.seed)
        let warp: Float = Float(drive.warp)
        let lit: Float = Float(drive.brightness)
        let fold = KaleidoscopeFold(wedges: c.wedges, rotation: Float(drive.rotation))   // VIS-014: identity when unfolded
        for row in 0..<Self.gridSide {
            for column in 0..<Self.gridSide {
                let k: Int = row * Self.gridSide + column
                let pixel: SIMD2<Float> = Self.samplePoint(column: column, row: row, width: w, height: h)
                let q: SIMD2<Float> = fold.wedges >= 2
                    ? Self.foldedDomainPoint(pixel, width: w, height: h, scale: Float(c.frequency), phase: Float(drive.phase), fold: fold)
                    : SeededNoise.domainPoint(x: pixel.x, y: pixel.y, width: w, height: h, scale: Float(c.frequency),
                                              phase: Float(drive.phase))
                let n: Float = SeededNoise.warped(q, octaves: c.octaves, lacunarity: NoiseFieldConfiguration.lacunarity,
                                                  gain: NoiseFieldConfiguration.gain, seed: seed, warpAmount: warp, warpFrequency: 1)
                values[k] = n
                let base: LinearColor = Self.paletteColor(n, stops: paletteStops)
                let scale: Float = (0.25 + 0.75 * n) * lit
                colors[k] = LinearColor(red: base.red * scale, green: base.green * scale, blue: base.blue * scale, alpha: 1)
            }
        }
    }

    /// VIS-015: evaluates the 64 samples of the tunnel for this frame. `paletteStops` holds 16 colours.
    public func sampleTunnel(configuration c: NoiseFieldConfiguration, drive: TunnelDrive, paletteStops: UnsafePointer<LinearColor>,
                             width: Int, height: Int) {
        let w: Int = max(width, 1), h: Int = max(height, 1)
        let size: SIMD2<Float> = SIMD2(Float(w), Float(h))
        let shorter: Float = min(size.x, size.y)
        let seed: UInt32 = UInt32(c.seed)
        let phase: Float = Float(drive.phase)
        let lit: Float = Float(drive.brightness)
        for row in 0..<Self.gridSide {
            for column in 0..<Self.gridSide {
                let k: Int = row * Self.gridSide + column
                let pixel: SIMD2<Float> = Self.samplePoint(column: column, row: row, width: w, height: h)
                let p: SIMD2<Float> = (pixel - 0.5 * size) / shorter
                let s: (t: Float, light: Float) = TunnelMapping.sample(p, phase: phase, seed: seed)
                values[k] = s.t
                let base: LinearColor = Self.paletteColor(s.t, stops: paletteStops)
                let scale: Float = s.light * lit
                colors[k] = LinearColor(red: base.red * scale, green: base.green * scale, blue: base.blue * scale, alpha: 1)
            }
        }
    }

    /// VIS-017: evaluates the 64 samples of the SDF shapes for this frame from the CPU mirror of the shader's march
    /// (`SignedDistanceScene.shade`); values hold each sample's luminance. `paletteStops` holds 16 colours.
    public func sampleSignedDistance(pose: SignedDistancePose, quality: SignedDistanceQuality,
                                     paletteStops: UnsafePointer<LinearColor>, width: Int, height: Int) {
        let w: Int = max(width, 1), h: Int = max(height, 1)
        for row in 0..<Self.gridSide {
            for column in 0..<Self.gridSide {
                let k: Int = row * Self.gridSide + column
                let pixel: SIMD2<Float> = Self.samplePoint(column: column, row: row, width: w, height: h)
                let p: SIMD2<Float> = SignedDistanceScene.offset(pixel: pixel, width: w, height: h)
                let c: LinearColor = SignedDistanceScene.shade(p, pose: pose, quality: quality, stops: paletteStops).color
                values[k] = c.relativeLuminance
                colors[k] = c
            }
        }
    }

    /// VIS-020: the 64 samples of the waterfall are the cells' mean colours (exact mean of the texels each shows) ×
    /// `brightness`; values hold the cells' luminance at brightness 1.
    public func loadWaterfall(_ cells: WaterfallFlashCells, history: SpectrumWaterfallHistory, brightness: Float) {
        for row in 0..<Self.gridSide {
            for column in 0..<Self.gridSide {
                let k: Int = row * Self.gridSide + column
                let c: LinearColor = cells.cellColor(row: row, column: column, history: history)
                values[k] = c.relativeLuminance
                colors[k] = LinearColor(red: c.red * brightness, green: c.green * brightness, blue: c.blue * brightness, alpha: 1)
            }
        }
    }

    /// VIS-011: every sample takes `color` (the ink bound, linear; ACC-012 caps it at 0.8), values its luminance.
    public func loadUniform(_ color: LinearColor) {
        for k in 0..<Self.sampleCount {
            values[k] = color.relativeLuminance
            colors[k] = LinearColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
        }
    }

    /// The 17 area levels at `gain`, after `transfer`. No allocation.
    public func levels<Transfer: FrameLuminanceTransfer>(gain: Float, transfer: Transfer, into out: UnsafeMutableBufferPointer<FlashLevels>) {
        guard out.count >= FlashZones.count else { return }
        for z in 0..<FlashZones.count { out[z] = .zero }
        let perTile: Int = Self.gridSide / FlashZones.gridSide
        for k in 0..<Self.sampleCount {
            let c: LinearColor = colors[k]
            let lit = LinearColor(red: c.red * gain, green: c.green * gain, blue: c.blue * gain, alpha: 1)
            let y: Double = transfer.outputLuminance(ofFlatColor: lit)
            let r: Double = transfer.outputRedness(ofFlatColor: lit)
            let row: Int = k / Self.gridSide, column: Int = k % Self.gridSide
            let tile: Int = (row / perTile) * FlashZones.gridSide + column / perTile
            out[tile].luminance += y
            out[tile].redness += r
            out[FlashZones.wholeFrame].luminance += y
            out[FlashZones.wholeFrame].redness += r
        }
        let tileSamples: Double = Double(perTile * perTile)
        for t in 0..<FlashZones.tileCount {
            out[t].luminance /= tileSamples
            out[t].redness /= tileSamples
        }
        out[FlashZones.wholeFrame].luminance /= Double(Self.sampleCount)
        out[FlashZones.wholeFrame].redness /= Double(Self.sampleCount)
    }

    /// The envelope's gain for this frame's samples (the largest g within every ceiling; FX-019). No allocation.
    public func gain<Transfer: FrameLuminanceTransfer>(envelope: FlashEnvelope, transfer: Transfer, frameTime: Double,
                                                       configuration: FlashEnvelopeConfiguration) -> Float {
        envelope.gain(frameTime: frameTime, configuration: configuration) { (g: Float, out: UnsafeMutableBufferPointer<FlashLevels>) -> Void in
            self.levels(gain: g, transfer: transfer, into: out)
        }
    }
}
