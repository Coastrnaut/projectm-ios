// SpectrumAnalyzer.swift — windowed magnitude spectra (ANL-001-R1, R3, R4, R8, R10, R13).
//
// One call: sanitize every sample (NaN/±∞ → 0, |x| below the smallest normal float → 0, clamp to
// ±64; research ANL-001-D5), multiply by the periodic Hann window, real FFT (vDSP or portable),
// then scale to linear amplitude: |X[k]|·4/N for 0 < k < N/2, |X[k]|·2/N for DC and Nyquist, so a
// bin-centred sine of amplitude A reads A (research ANL-001-D4). The sanitize-and-window pass and
// the scaling are shared by both backends; they differ only in the transform.
//
// Real-time safety (Constitution VII): every buffer, window and FFT setup is created in `init`
// for every size; `magnitudes(of:size:into:)` only reads and writes preallocated memory. Not
// Sendable: an analyzer is confined to the one worker that owns it (ANL-001-R14).
//
// Boundary (Constitution VIII, ADR-0008 decision 5): nothing computed here is passed to projectM.
#if canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE
import Accelerate
#endif

public enum SpectrumBackend: Sendable, Hashable {
    /// vDSP where compiled in, else portable.
    case automatic
    /// vDSP (Apple platforms); falls back to portable where Accelerate is compiled out.
    case accelerated
    /// The in-package radix-2 FFT, available everywhere.
    case portable

    /// True when this build contains the vDSP backend.
    public static var isAcceleratedAvailable: Bool {
        #if canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE
        return true
        #else
        return false
        #endif
    }
}

public final class SpectrumAnalyzer {
    /// Largest accepted |sample| after sanitizing (+36 dBFS).
    public static let clampLimit: Float = 64

    public let resolvedBackend: SpectrumBackend
    private let windows = HannWindowTables()
    private let work: UnsafeMutablePointer<Float>
    private let portable: PortableRealFFT?
    #if canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE
    private let accelerated: AcceleratedRealFFT?
    #endif

    public init(backend: SpectrumBackend = .automatic) {
        let useAccelerated = backend != .portable && SpectrumBackend.isAcceleratedAvailable
        resolvedBackend = useAccelerated ? .accelerated : .portable
        #if canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE
        accelerated = useAccelerated ? AcceleratedRealFFT() : nil
        #endif
        portable = useAccelerated ? nil : PortableRealFFT()
        work = .allocate(capacity: FFTSize.maximum.rawValue)
        work.initialize(repeating: 0, count: FFTSize.maximum.rawValue)
    }

    deinit {
        work.deinitialize(count: FFTSize.maximum.rawValue)
        work.deallocate()
    }

    /// Linear-amplitude magnitudes of `samples[0..<size]` into `output[0..<size.binCount]`.
    /// Every value is finite and ≥ 0. Allocation-, lock- and I/O-free.
    public func magnitudes(of samples: UnsafePointer<Float>, size: FFTSize, into output: UnsafeMutablePointer<Float>) {
        let n = size.rawValue
        let window = windows.window(for: size)
        let limit = SpectrumAnalyzer.clampLimit
        for i in 0..<n {
            var x = samples[i]
            if !x.isFinite || abs(x) < Float.leastNormalMagnitude {
                x = 0
            } else if x > limit {
                x = limit
            } else if x < -limit {
                x = -limit
            }
            work[i] = x * window[i]
        }
        #if canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE
        if let accelerated {
            accelerated.rawMagnitudes(work, size: size, into: output)
        } else {
            portable!.rawMagnitudes(work, size: size, into: output)
        }
        #else
        portable!.rawMagnitudes(work, size: size, into: output)
        #endif
        // Linear amplitude. Both factors are powers of two, so the scaling is exact.
        let interior = 4 / Float(n)
        let edge = 2 / Float(n)
        let m = n / 2
        output[0] = SpectrumAnalyzer.finite(output[0] * edge)
        output[m] = SpectrumAnalyzer.finite(output[m] * edge)
        for k in 1..<m { output[k] = SpectrumAnalyzer.finite(output[k] * interior) }
    }

    /// Convenience for tests and callers off the real-time path (allocates the result).
    /// `samples` must hold at least `size.rawValue` values.
    public func magnitudes(of samples: [Float], size: FFTSize) -> [Float] {
        precondition(samples.count >= size.rawValue, "need \(size.rawValue) samples, got \(samples.count)")
        var result = [Float](repeating: 0, count: size.binCount)
        samples.withUnsafeBufferPointer { src in
            result.withUnsafeMutableBufferPointer { dst in
                magnitudes(of: src.baseAddress!, size: size, into: dst.baseAddress!)
            }
        }
        return result
    }

    /// Defence in depth: sanitized input cannot overflow, but a value is never published non-finite.
    @inline(__always)
    private static func finite(_ value: Float) -> Float {
        value.isFinite ? value : 0
    }
}
