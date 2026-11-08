// LevelMeter.swift — peak and RMS level in dBFS (task T025).
// Uses vDSP where Accelerate exists (Apple platforms); a scalar loop elsewhere, so the package
// stays testable on non-Apple toolchains. Allocation-free.
#if canImport(Accelerate)
import Accelerate
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(ucrt)
import ucrt
#endif

public enum LevelMeter {
    /// Floor reported for digital silence.
    public static let floorDBFS: Float = -120

    public struct Levels: Sendable, Equatable {
        public var peakDBFS: Float
        public var rmsDBFS: Float
        public init(peakDBFS: Float, rmsDBFS: Float) {
            self.peakDBFS = peakDBFS
            self.rmsDBFS = rmsDBFS
        }
        public static let silent = Levels(peakDBFS: LevelMeter.floorDBFS, rmsDBFS: LevelMeter.floorDBFS)
    }

    /// Converts a linear amplitude (1.0 = full scale) to dBFS, clamped to `floorDBFS`.
    @inlinable
    public static func dBFS(_ linear: Float) -> Float {
        guard linear > 0 else { return floorDBFS }
        let db = 20 * log10f(linear)
        return db.isFinite ? max(floorDBFS, db) : floorDBFS
    }

    /// Peak (max |x|) and RMS over `count` samples. Channel-agnostic: interleaved input is fine.
    public static func measure(_ samples: UnsafePointer<Float>, count: Int) -> Levels {
        guard count > 0 else { return .silent }
        var peak: Float = 0
        var rms: Float = 0
        #if canImport(Accelerate)
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(count))
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(count))
        #else
        var sumSquares: Double = 0
        for i in 0..<count {
            let v = samples[i]
            let a = abs(v)
            if a > peak { peak = a }
            sumSquares += Double(v) * Double(v)
        }
        rms = Float((sumSquares / Double(count)).squareRoot())
        #endif
        return Levels(peakDBFS: dBFS(peak), rmsDBFS: dBFS(rms))
    }
}
