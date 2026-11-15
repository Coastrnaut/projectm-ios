// FluidInkSolver.swift — VIS-011's CPU reference solver (contracts/fluid-ink.md C3; research VIS-011-D7): the passes
// and formulas of `FluidInkShader` (see FluidInk.swift for the step) on an N × N grid in Float, for deterministic tests
// and the comparison with the GPU. Its own target, compiled with -O even in Debug (Package.swift), so the 60-second
// acceptance run takes well under a second in the Debug test build. Pure Swift (every platform); nothing in the app
// draws with it.
import Foundation
import VisualGenerators

/// The CPU reference solver (contracts/fluid-ink.md C3): the shaders' passes and formulas on an N × N grid in Float.
/// All storage is one block made in `init`; `step` allocates nothing. Written with plain Float planes and non-generic
/// helpers so the Debug test build stays fast. Not Sendable: one thread.
public final class FluidInkSolver {
    public let n: Int
    public let h: Float
    /// Steps run, and resets after a non-finite value (VIS-011-R7).
    public private(set) var steps = 0
    public private(set) var nonFiniteResets = 0
    /// Floats held (fixed for the solver's life).
    public let allocatedFloats: Int

    private let cells: Int
    private let storage: UnsafeMutablePointer<Float>
    // Planes: velocity, scratch velocity, pressure pair, divergence, ink (r, g, b) and scratch ink.
    private let vx, vy, wx, wy, p, q, div, r, g, b, r2, g2, b2: UnsafeMutablePointer<Float>

    public init(gridSize: Int = 32) {
        n = max(gridSize, 2)
        h = 1 / Float(n)
        cells = n * n
        allocatedFloats = 13 * cells
        storage = .allocate(capacity: allocatedFloats)
        storage.initialize(repeating: 0, count: allocatedFloats)
        let c: Int = cells
        vx = storage; vy = storage + c; wx = storage + 2 * c; wy = storage + 3 * c
        p = storage + 4 * c; q = storage + 5 * c; div = storage + 6 * c
        r = storage + 7 * c; g = storage + 8 * c; b = storage + 9 * c
        r2 = storage + 10 * c; g2 = storage + 11 * c; b2 = storage + 12 * c
    }

    deinit {
        storage.deinitialize(count: allocatedFloats)
        storage.deallocate()
    }

    /// Velocity of cell (i, j).
    public func velocity(_ i: Int, _ j: Int) -> SIMD2<Float> { SIMD2(vx[j * n + i], vy[j * n + i]) }
    /// Ink (linear rgb) of cell (i, j).
    public func inkColor(_ i: Int, _ j: Int) -> SIMD3<Float> { let k = j * n + i; return SIMD3(r[k], g[k], b[k]) }

    /// Back to rest: zero velocity and ink.
    public func reset() { storage.update(repeating: 0, count: allocatedFloats) }

    /// Writes `value` into cell 0's velocity (tests of the guard).
    public func corruptForTesting(_ value: Float) { vx[0] = value }

    /// One fixed step with `splats` (≤ 2) at `speedCap`. A non-finite value afterwards resets the field (counted).
    public func step(splats: [FluidSplat], speedCap: Float) {
        steps += 1
        if !splats.isEmpty { applySplats(splats, speedCap: speedCap) }
        advectVelocity(speedCap: speedCap)
        divergence()
        pressure()
        project(speedCap: speedCap)
        advectInk()
        if !allFinite() {
            nonFiniteResets += 1
            reset()
        }
    }

    /// Health over the whole grid.
    public var health: FluidInkHealth {
        var result = FluidInkHealth()
        let area: Float = h * h
        var maxSpeed2: Float = 0
        for k in 0..<cells {
            let x: Float = vx[k], y: Float = vy[k]
            if !(x.isFinite && y.isFinite && r[k].isFinite && g[k].isFinite && b[k].isFinite) { result.nonFinite = true; continue }
            let s2: Float = x * x + y * y
            if s2 > maxSpeed2 { maxSpeed2 = s2 }
            let m: Float = Self.larger(r[k], Self.larger(g[k], b[k]))
            if m > result.maxInk { result.maxInk = m }
            result.kineticEnergy += 0.5 * s2 * area
        }
        result.maxSpeed = maxSpeed2.squareRoot()
        return result
    }

    private func allFinite() -> Bool {
        for k in 0..<cells where !(vx[k].isFinite && vy[k].isFinite && r[k].isFinite && g[k].isFinite && b[k].isFinite) {
            return false
        }
        return true
    }

    // MARK: Helpers (non-generic)

    @inline(__always) private static func larger(_ a: Float, _ b: Float) -> Float { a > b ? a : b }
    @inline(__always) private static func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
        v.isFinite ? (v < lo ? lo : (v > hi ? hi : v)) : 0
    }
    @inline(__always) private static func finite(_ v: Float) -> Float { v.isFinite ? v : 0 }
    @inline(__always) private static func lerp(_ a: Float, _ b: Float, _ f: Float) -> Float { a + (b - a) * f }

    /// The speed-capped velocity (non-finite → 0).
    @inline(__always) private static func capped(_ x: Float, _ y: Float, cap: Float) -> (Float, Float) {
        let fx: Float = finite(x), fy: Float = finite(y)
        let s2: Float = fx * fx + fy * fy
        guard s2 > cap * cap else { return (fx, fy) }
        let k: Float = cap / s2.squareRoot()
        return (fx * k, fy * k)
    }

    /// Grid coordinate of domain point `x`: (x·N − 0.5) clamped to 0…N−1 (non-finite → 0); the lower index (≤ N−2)
    /// and the fraction.
    @inline(__always) private func coordinate(_ x: Float) -> (Int, Float) {
        let gx: Float = Self.clamp(x * Float(n) - 0.5, 0, Float(n - 1))
        var i: Int = Int(gx)
        if i > n - 2 { i = n - 2 }
        return (i, gx - Float(i))
    }

    // MARK: Passes (the shader's formulas)

    private func applySplats(_ splats: [FluidSplat], speedCap: Float) {
        let r2Radius: Float = FluidInk.splatRadius * FluidInk.splatRadius
        let cap: Float = FluidInk.inkCap
        for s in splats {
            for j in 0..<n {
                let dy: Float = (Float(j) + 0.5) * h - s.centerY
                for i in 0..<n {
                    let dx: Float = (Float(i) + 0.5) * h - s.centerX
                    let k: Int = j * n + i
                    let w: Float = exp(-(dx * dx + dy * dy) / r2Radius)
                    vx[k] += w * s.velocityX
                    vy[k] += w * s.velocityY
                    r[k] += w * s.red
                    g[k] += w * s.green
                    b[k] += w * s.blue
                }
            }
        }
        for k in 0..<cells {
            (vx[k], vy[k]) = Self.capped(vx[k], vy[k], cap: speedCap)
            r[k] = Self.clamp(r[k], 0, cap); g[k] = Self.clamp(g[k], 0, cap); b[k] = Self.clamp(b[k], 0, cap)
        }
    }

    /// Bilinear sample of `f` at the cell whose lower corner index is `a` (row below: `a + n`).
    @inline(__always) private func sample(_ f: UnsafeMutablePointer<Float>, _ a: Int, _ fx: Float, _ fy: Float) -> Float {
        Self.lerp(Self.lerp(f[a], f[a + 1], fx), Self.lerp(f[a + n], f[a + n + 1], fx), fy)
    }

    private func advectVelocity(speedCap: Float) {
        let dt: Float = FluidInk.stepSeconds
        let factor: Float = FluidInk.velocityFactor
        for j in 0..<n {
            for i in 0..<n {
                let k: Int = j * n + i
                let (i0, fx) = coordinate((Float(i) + 0.5) * h - dt * vx[k])
                let (j0, fy) = coordinate((Float(j) + 0.5) * h - dt * vy[k])
                let a: Int = j0 * n + i0
                (wx[k], wy[k]) = Self.capped(sample(vx, a, fx, fy) * factor, sample(vy, a, fx, fy) * factor, cap: speedCap)
            }
        }
        vx.update(from: wx, count: cells)
        vy.update(from: wy, count: cells)
    }

    private func divergence() {
        let scale: Float = 0.5 / h
        for j in 0..<n {
            let jt: Int = j > 0 ? j - 1 : 0, jb: Int = j < n - 1 ? j + 1 : n - 1
            for i in 0..<n {
                let il: Int = i > 0 ? i - 1 : 0, ir: Int = i < n - 1 ? i + 1 : n - 1
                div[j * n + i] = Self.finite(((vx[j * n + ir] - vx[j * n + il]) + (vy[jb * n + i] - vy[jt * n + i])) * scale)
            }
        }
    }

    private func pressure() {
        let h2: Float = h * h
        p.update(repeating: 0, count: cells)
        var src: UnsafeMutablePointer<Float> = p, dst: UnsafeMutablePointer<Float> = q
        for _ in 0..<FluidInk.jacobiIterations {
            for j in 0..<n {
                let jt: Int = j > 0 ? j - 1 : 0, jb: Int = j < n - 1 ? j + 1 : n - 1
                for i in 0..<n {
                    let il: Int = i > 0 ? i - 1 : 0, ir: Int = i < n - 1 ? i + 1 : n - 1
                    let sum: Float = (src[j * n + il] + src[j * n + ir]) + (src[jt * n + i] + src[jb * n + i])
                    dst[j * n + i] = Self.finite((sum - h2 * div[j * n + i]) * 0.25)
                }
            }
            swap(&src, &dst)
        }
        if src != p { p.update(from: src, count: cells) }   // an even count leaves the result in p
    }

    private func project(speedCap: Float) {
        let scale: Float = 0.5 / h
        for j in 0..<n {
            let jt: Int = j > 0 ? j - 1 : 0, jb: Int = j < n - 1 ? j + 1 : n - 1
            for i in 0..<n {
                let il: Int = i > 0 ? i - 1 : 0, ir: Int = i < n - 1 ? i + 1 : n - 1
                let k: Int = j * n + i
                (vx[k], vy[k]) = Self.capped(vx[k] - (p[j * n + ir] - p[j * n + il]) * scale,
                                             vy[k] - (p[jb * n + i] - p[jt * n + i]) * scale, cap: speedCap)
            }
        }
    }

    private func advectInk() {
        let dt: Float = FluidInk.stepSeconds
        let factor: Float = FluidInk.inkFactor
        let cap: Float = FluidInk.inkCap
        for j in 0..<n {
            for i in 0..<n {
                let k: Int = j * n + i
                let (i0, fx) = coordinate((Float(i) + 0.5) * h - dt * vx[k])
                let (j0, fy) = coordinate((Float(j) + 0.5) * h - dt * vy[k])
                let a: Int = j0 * n + i0
                r2[k] = Self.clamp(sample(r, a, fx, fy) * factor, 0, cap)
                g2[k] = Self.clamp(sample(g, a, fx, fy) * factor, 0, cap)
                b2[k] = Self.clamp(sample(b, a, fx, fy) * factor, 0, cap)
            }
        }
        r.update(from: r2, count: cells)
        g.update(from: g2, count: cells)
        b.update(from: b2, count: cells)
    }
}
