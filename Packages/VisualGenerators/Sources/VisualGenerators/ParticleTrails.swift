// ParticleTrails.swift — VIS-010 particle trails: the setting, the decay model, the ACC-012 cap, the CPU reference of one
// accumulation pixel, the strobe envelope's bound of the trail's light and a small CPU accumulation model
// (specs/272-vis-010-particle-trails, research VIS-010-D1 to D5, contracts/particle-trails.md).
//
// The rule (FX-009's, ADR-0051, restated here because this package cannot import the compositor):
//   next = max(particles, cut(min(d · previous, 0.8)))   per premultiplied channel,
//   d = min(0.5^(Δt / h), 0.99),   Δt the frame clock's duration clamped to 0…0.1 s,
// so the fade per second is the same at any frame rate. Values below 1/512 become exactly 0. The result never exceeds
// the brightest particle drawn nor 0.8 (ACC-012: below full white), so it cannot run away.
// Pure Swift (every platform). Not Sendable where it holds storage: one thread drives it.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import FlashSafety

/// VIS-010: how long particle streaks last.
public enum ParticleTrailLength: String, CaseIterable, Sendable {
    case off, short, long

    /// Half-life in seconds before Reduce Motion and Reduce flashing (0 = off).
    public var halfLifeSeconds: Double {
        switch self {
        case .off: 0
        case .short: ParticleTrails.shortHalfLife
        case .long: ParticleTrails.longHalfLife
        }
    }
}

public enum ParticleTrails {
    public static let shortHalfLife = 0.1
    public static let longHalfLife = 0.3
    /// Reduce Motion multiplies the half-life by this (shorter streaks; ACC-001).
    public static let reduceMotionScale = 0.5
    /// Reduce flashing, or a sensory profile stricter than Standard, caps the half-life (FX-009-D6).
    public static let reduceFlashingHalfLife = 0.25
    public static let maximumDecay = 0.99
    public static let maxFrameTime = 0.1
    /// ACC-012: no accumulated channel exceeds this.
    public static let cap: Float = 0.8
    /// Values below this become exactly 0, so a trail ends in finite time.
    public static let cut: Float = 1.0 / 512
    /// Side of the fixed accumulation textures (research VIS-010-D1).
    public static let textureSide = 512

    /// The effective half-life (0 when off).
    public static func halfLife(_ length: ParticleTrailLength, reduceMotion: Bool, reduceFlashing: Bool) -> Double {
        var h: Double = length.halfLifeSeconds
        guard h > 0 else { return 0 }
        if reduceMotion { h *= reduceMotionScale }
        if reduceFlashing { h = min(h, reduceFlashingHalfLife) }
        return h
    }

    /// The per-frame decay `min(0.5^(Δt / h), 0.99)`; 0 when `halfLife` ≤ 0. A NaN or negative duration counts as 0 s.
    public static func decay(frameDuration: Double, halfLife: Double) -> Double {
        guard halfLife.isFinite, halfLife > 0 else { return 0 }
        let seconds: Double = frameDuration.isFinite && frameDuration > 0 ? min(frameDuration, maxFrameTime) : 0
        let raw: Double = seconds > 0 ? pow(0.5, seconds / halfLife) : 1
        return min(raw, maximumDecay)
    }

    /// One decayed history channel: sanitised, × d, capped at 0.8, cut below 1/512.
    @inlinable
    public static func decayed(_ value: Float, decay: Float) -> Float {
        let v: Float = value.isFinite ? max(value, 0) : 0
        let d: Float = decay.isFinite ? min(max(decay, 0), 1) : 0
        let out: Float = min(v * d, cap)
        return out < cut ? 0 : out
    }

    /// The CPU reference of one accumulation pixel (linear premultiplied RGBA): `reset` keeps only the particle.
    public static func accumulate(particle: SIMD4<Float>, previous: SIMD4<Float>, decay: Float, reset: Bool) -> SIMD4<Float> {
        var out = SIMD4<Float>(repeating: 0)
        for c in 0..<4 {
            let p: Float = particle[c].isFinite ? min(max(particle[c], 0), cap) : 0
            let h: Float = reset ? 0 : decayed(previous[c], decay: decay)
            out[c] = max(p, h)
        }
        return out
    }
}

/// VIS-010-R7: a per-area upper bound of the trail's light for FX-019's envelope (research VIS-010-D5).
///
/// `accumulated` bounds the mean of the accumulation texture per area: after each drawn frame
/// `A ← min(P + d · A, 0.8)`, P the particle levels drawn that frame minus the background's. The trail shown in a frame
/// is `min(d · A, 0.8)` scaled by the frame's gain; mean(max(a, b)) ≤ mean(a) + mean(b), so it is never an
/// underestimate. All storage allocated in `init`.
public final class ParticleTrailFlashBound {
    public let accumulated: UnsafeMutableBufferPointer<FlashLevels>
    /// Scratch for the particle levels of the frame just drawn.
    let scratch: UnsafeMutableBufferPointer<FlashLevels>

    public init() {
        accumulated = .allocate(capacity: FlashZones.count)
        accumulated.initialize(repeating: .zero)
        scratch = .allocate(capacity: FlashZones.count)
        scratch.initialize(repeating: .zero)
    }

    deinit {
        accumulated.deallocate()
        scratch.deallocate()
    }

    public func reset() {
        for z in 0..<FlashZones.count { accumulated[z] = .zero }
    }

    /// The trail's levels shown with decay `d` (before gain) in area `z`.
    public func shown(_ z: Int, decay: Double) -> FlashLevels {
        let cap = Double(ParticleTrails.cap)
        let a: FlashLevels = accumulated[z]
        return FlashLevels(luminance: min(decay * a.luminance, cap), redness: min(decay * a.redness, cap))
    }

    /// Adds `gain` × the shown trail to `out` (the envelope's levels of the particles at that gain).
    public func add(gain: Float, decay: Double, into out: UnsafeMutableBufferPointer<FlashLevels>) {
        let g = Double(gain)
        for z in 0..<min(out.count, FlashZones.count) {
            let s: FlashLevels = shown(z, decay: decay)
            out[z].luminance += g * s.luminance
            out[z].redness += g * s.redness
        }
    }

    /// After a frame: `A ← min(max(P − background, 0) + d · A, 0.8)`, P = `particleLevels` (the frame's levels at its
    /// gain, background included).
    public func advance(decay: Double, particleLevels: UnsafeBufferPointer<FlashLevels>, background: FlashLevels) {
        let cap = Double(ParticleTrails.cap)
        for z in 0..<min(particleLevels.count, FlashZones.count) {
            let p: FlashLevels = particleLevels[z]
            let a: FlashLevels = accumulated[z]
            let pl: Double = max(p.luminance - background.luminance, 0)
            let pr: Double = max(p.redness - background.redness, 0)
            accumulated[z] = FlashLevels(luminance: min(pl + decay * a.luminance, cap), redness: min(pr + decay * a.redness, cap))
        }
    }
}

extension ParticleTrailFlashBound {
    /// The frame's gain: FX-019's envelope over the particles at gain g plus g × the shown trail (when `showsTrail`).
    /// The non-escaping closure allocates nothing.
    public func gain<Source: FlashAreaLevelSource, Transfer: FrameLuminanceTransfer>(layout: Source, transfer: Transfer,
                                                                                   limiter: FlashSafetyLimiter, decay: Double,
                                                                                   showsTrail: Bool, frameTime: Double,
                                                                                   configuration: FlashEnvelopeConfiguration) -> Float {
        limiter.envelope.gain(frameTime: frameTime, configuration: configuration) {
            (g: Float, out: UnsafeMutableBufferPointer<FlashLevels>) -> Void in
            layout.meanLevels(gain: g, transfer: transfer, into: out)
            if showsTrail { self.add(gain: g, decay: decay, into: out) }
        }
    }

    /// After a drawn frame: the accumulation bound takes the particles drawn at `gain` over `background`.
    public func record<Source: FlashAreaLevelSource, Transfer: FrameLuminanceTransfer>(layout: Source, transfer: Transfer, gain: Float,
                                                                                     background: LinearColor, decay: Double) {
        layout.meanLevels(gain: gain, transfer: transfer, into: scratch)
        let b = FlashLevels(luminance: transfer.outputLuminance(ofFlatColor: background),
                            redness: transfer.outputRedness(ofFlatColor: background))
        advance(decay: decay, particleLevels: UnsafeBufferPointer(scratch), background: b)
    }
}

/// VIS-010: a small CPU accumulation (the GPU rule per pixel, `ParticleTrails.accumulate`) for the 10-minute fixture and
/// the frame-rate and cap tests. Two fixed buffers, ping-pong; nothing is allocated after `init`.
public final class ParticleTrailModel {
    public let width: Int
    public let height: Int
    private let buffers: (UnsafeMutablePointer<SIMD4<Float>>, UnsafeMutablePointer<SIMD4<Float>>)
    private var newestIsFirst = true
    private var resetPending = true
    private var decay: Float = 0

    public init(width: Int, height: Int) {
        self.width = max(width, 1)
        self.height = max(height, 1)
        let n: Int = self.width * self.height
        let a = UnsafeMutablePointer<SIMD4<Float>>.allocate(capacity: n)
        a.initialize(repeating: SIMD4<Float>(repeating: 0), count: n)
        let b = UnsafeMutablePointer<SIMD4<Float>>.allocate(capacity: n)
        b.initialize(repeating: SIMD4<Float>(repeating: 0), count: n)
        buffers = (a, b)
    }

    deinit {
        let n: Int = width * height
        buffers.0.deinitialize(count: n); buffers.0.deallocate()
        buffers.1.deinitialize(count: n); buffers.1.deallocate()
    }

    /// The addresses of both buffers (tests: they never change).
    public var storageAddresses: [UInt] { [UInt(bitPattern: buffers.0), UInt(bitPattern: buffers.1)] }

    private var newest: UnsafeMutablePointer<SIMD4<Float>> { newestIsFirst ? buffers.0 : buffers.1 }
    private var other: UnsafeMutablePointer<SIMD4<Float>> { newestIsFirst ? buffers.1 : buffers.0 }

    /// The next frame starts empty (loop restart, size change, trails turned on).
    public func reset() { resetPending = true }

    /// Starts a frame: the other buffer becomes the decayed newest one (or empty after a reset).
    public func beginFrame(decay d: Double) {
        let n: Int = width * height
        let src = newest, dst = other
        let df = Float(d)
        decay = df
        if resetPending {
            dst.update(repeating: SIMD4<Float>(repeating: 0), count: n)
        } else {
            for i in 0..<n {
                let p: SIMD4<Float> = src[i]
                dst[i] = SIMD4<Float>(ParticleTrails.decayed(p.x, decay: df), ParticleTrails.decayed(p.y, decay: df),
                                      ParticleTrails.decayed(p.z, decay: df), ParticleTrails.decayed(p.w, decay: df))
            }
        }
        resetPending = false
        newestIsFirst.toggle()
    }

    /// Max-blends a premultiplied colour over pixels [x0, x1) × [y0, y1) of the current frame (clipped; capped at 0.8).
    public func stamp(x0: Int, y0: Int, x1: Int, y1: Int, color: SIMD4<Float>) {
        let cap = SIMD4<Float>(repeating: ParticleTrails.cap)
        let c: SIMD4<Float> = simdMin(simdMax(color, SIMD4<Float>(repeating: 0)), cap)
        let buffer = newest
        for y in max(y0, 0)..<min(max(y1, 0), height) {
            for x in max(x0, 0)..<min(max(x1, 0), width) {
                buffer[y * width + x] = simdMax(buffer[y * width + x], c)
            }
        }
    }

    /// The newest frame's value at (x, y).
    public func value(x: Int, y: Int) -> SIMD4<Float> { newest[min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)] }

    /// The largest channel of the newest frame.
    public var maximumChannel: Float {
        var m: Float = 0
        for i in 0..<(width * height) { m = max(m, newest[i].max()) }
        return m
    }

    /// What the target shows of the history in the next frame at pixel (x, y): `decayed(newest)` (before gain).
    public func shownTrail(x: Int, y: Int, decay d: Double) -> SIMD4<Float> {
        let p: SIMD4<Float> = value(x: x, y: y)
        let df = Float(d)
        return SIMD4<Float>(ParticleTrails.decayed(p.x, decay: df), ParticleTrails.decayed(p.y, decay: df),
                            ParticleTrails.decayed(p.z, decay: df), ParticleTrails.decayed(p.w, decay: df))
    }
}

@inline(__always) private func simdMax(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> SIMD4<Float> { a.replacing(with: b, where: b .> a) }
@inline(__always) private func simdMin(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> SIMD4<Float> { a.replacing(with: b, where: b .< a) }
