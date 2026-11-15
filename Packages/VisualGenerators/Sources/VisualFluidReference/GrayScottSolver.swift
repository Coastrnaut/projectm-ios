// GrayScottSolver.swift — VIS-012's CPU reference (contracts/reaction-diffusion.md C3): the iteration of
// `ReactionDiffusionShader` (see ReactionDiffusion.swift for the formula) on an N × N torus in Float, for deterministic
// tests and the comparison with the GPU. In the tests-only target compiled with -O (Package.swift), so long runs stay
// short in the Debug test build. Nothing in the app draws with it.
import Foundation
import VisualGenerators

/// The CPU reference: same seed (`ReactionDiffusionSeed.fill`), same formula and order, same guard. All storage is made
/// in `init`; `iterate` allocates nothing. Not Sendable: one thread.
public final class GrayScottSolver {
    public let n: Int
    public var parameters: GrayScottParameters
    public private(set) var iterations = 0
    /// Values the guard had to map (non-finite → 0) or clamp from outside [0, 1] — the guard's work, counted.
    public private(set) var nonFiniteValues = 0

    private let state: UnsafeMutablePointer<SIMD2<Float>>
    private let scratch: UnsafeMutablePointer<SIMD2<Float>>
    private var current: UnsafeMutablePointer<SIMD2<Float>>
    private var other: UnsafeMutablePointer<SIMD2<Float>>

    public init(gridSize: Int = 32, parameters: GrayScottParameters = ReactionDiffusionPreset.coral.parameters) {
        n = max(gridSize, 3)
        self.parameters = parameters
        state = .allocate(capacity: n * n)
        state.initialize(repeating: SIMD2<Float>(1, 0), count: n * n)
        scratch = .allocate(capacity: n * n)
        scratch.initialize(repeating: SIMD2<Float>(1, 0), count: n * n)
        current = state
        other = scratch
    }

    deinit {
        state.deinitialize(count: n * n); state.deallocate()
        scratch.deinitialize(count: n * n); scratch.deallocate()
    }

    /// Re-seeds from `pattern` and `seed` (the GPU's staging buffer gets the same values).
    public func seed(pattern: ReactionDiffusionPattern, seed: Int) {
        current = state
        other = scratch
        ReactionDiffusionSeed.fill(pattern: pattern, seed: seed, gridSize: n, into: current)
        iterations = 0
    }

    /// (U, V) of cell (i, j), row j from the top.
    public func cell(_ i: Int, _ j: Int) -> SIMD2<Float> { current[j * n + i] }

    /// Writes a value directly (tests: a corrupt cell).
    public func poke(_ i: Int, _ j: Int, _ value: SIMD2<Float>) { current[j * n + i] = value }

    /// Every cell, rows top first (tests; allocates).
    public var cells: [SIMD2<Float>] { Array(UnsafeBufferPointer(start: current, count: n * n)) }

    /// The guard of the shader: exponent bits all set → 0; then clamp to [0, 1].
    @inline(__always)
    static func clean(_ v: Float) -> Float {
        if v.bitPattern & 0x7f80_0000 == 0x7f80_0000 { return 0 }
        return min(max(v, 0), 1)
    }

    /// One iteration; `injection` applies after the reaction update.
    public func iterate(injection: ReactionInjection? = nil) {
        let n: Int = n
        let p: GrayScottParameters = parameters
        let inv: Float = 1 / Float(n)
        let r2: Float = ReactionDiffusion.injectionRadius * ReactionDiffusion.injectionRadius
        let src: UnsafeMutablePointer<SIMD2<Float>> = current
        let dst: UnsafeMutablePointer<SIMD2<Float>> = other
        for j in 0..<n {
            let up: Int = (j + n - 1) % n, down: Int = (j + 1) % n
            for i in 0..<n {
                let left: Int = (i + n - 1) % n, right: Int = (i + 1) % n
                let s: SIMD2<Float> = src[j * n + i]
                let e: SIMD2<Float> = (src[j * n + left] + src[j * n + right]) + (src[up * n + i] + src[down * n + i])
                let d: SIMD2<Float> = (src[up * n + left] + src[up * n + right]) + (src[down * n + left] + src[down * n + right])
                let lap: SIMD2<Float> = 0.2 * e + 0.05 * d - s
                let uvv: Float = s.x * s.y * s.y
                var un: Float = s.x + (p.du * lap.x - uvv + p.feed * (1 - s.x))
                var vn: Float = s.y + (p.dv * lap.y + uvv - (p.feed + p.kill) * s.y)
                if let injection {
                    let dx: Float = (Float(i) + 0.5) * inv - injection.x
                    let dy: Float = (Float(j) + 0.5) * inv - injection.y
                    let a: Float = injection.amount * exp(-(dx * dx + dy * dy) / r2)
                    vn += a
                    un -= a
                }
                if !un.isFinite || !vn.isFinite { nonFiniteValues += 1 }
                dst[j * n + i] = SIMD2<Float>(Self.clean(un), Self.clean(vn))
            }
        }
        current = dst
        other = src
        iterations += 1
    }

    /// The health of the grid now (VIS-012-R9).
    public func health() -> ReactionDiffusionHealth {
        var h = ReactionDiffusionHealth()
        for k in 0..<(n * n) {
            let s: SIMD2<Float> = current[k]
            if !s.x.isFinite || !s.y.isFinite { h.flagged = true; continue }
            if s.x < 0 || s.x > 1 || s.y < 0 || s.y > 1 { h.flagged = true }
            h.maxU = max(h.maxU, s.x)
            h.maxV = max(h.maxV, s.y)
            h.minValue = min(h.minValue, min(s.x, s.y))
        }
        return h
    }
}
