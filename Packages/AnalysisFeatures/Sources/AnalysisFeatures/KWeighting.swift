// KWeighting.swift — ITU-R BS.1770 K-weighting as a power response per spectrum bin (ANL-014-R1;
// research ANL-014-D2; contracts/loudness-envelope.md C1).
//
// BS.1770 defines K-weighting as two biquads: a high shelf (+4 dB above about 1.7 kHz, the head's
// acoustic effect) and a high-pass near 38 Hz (the "RLB" curve). The standard publishes their
// coefficients at 48 kHz; for any rate they are designed here from the analog parameters with the
// formulas libebur128 uses (at 48 kHz these reproduce the published table to about 1e-8).
//
// Rather than filtering samples, the loudness envelope weights each spectrum bin by the cascade's
// exact power response at the bin's frequency: |H(e^jω)|² = |B(e^jω)|² / |A(e^jω)|² with
// |b0 + b1·z⁻¹ + b2·z⁻²|² = b0² + b1² + b2² + 2(b0·b1 + b1·b2)·cos ω + 2·b0·b2·cos 2ω.
// Pure, deterministic, Linux-portable; the table is built once per FFT size (never per frame).
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public enum KWeighting {
    /// Normalized biquad coefficients (a0 = 1).
    public struct Biquad: Sendable, Hashable {
        public let b0: Double
        public let b1: Double
        public let b2: Double
        public let a1: Double
        public let a2: Double

        /// |H(e^jω)|² at `omega` radians per sample.
        public func powerResponse(omega: Double) -> Double {
            let c1: Double = cos(omega)
            let c2: Double = cos(2 * omega)
            let numeratorSquares: Double = b0 * b0 + b1 * b1 + b2 * b2
            let numeratorFirst: Double = 2 * (b0 * b1 + b1 * b2) * c1
            let numeratorSecond: Double = 2 * b0 * b2 * c2
            let numerator: Double = numeratorSquares + numeratorFirst + numeratorSecond
            let denominatorSquares: Double = 1 + a1 * a1 + a2 * a2
            let denominatorFirst: Double = 2 * (a1 + a1 * a2) * c1
            let denominatorSecond: Double = 2 * a2 * c2
            let denominator: Double = denominatorSquares + denominatorFirst + denominatorSecond
            guard denominator > 0, numerator.isFinite, denominator.isFinite else { return 0 }
            return max(numerator / denominator, 0)
        }
    }

    // BS.1770 stage parameters (libebur128).
    public static let shelfFrequency: Double = 1_681.974450955533
    public static let shelfGainDecibels: Double = 3.999843853973347
    public static let shelfQ: Double = 0.7071752369554196
    public static let highPassFrequency: Double = 38.13547087602444
    public static let highPassQ: Double = 0.5003270373238773
    /// The lowest rate whose Nyquist lies above the shelf frequency.
    public static var minimumSampleRate: Double { 2 * shelfFrequency }

    /// Stage 1: the high shelf, designed for `sampleRate`.
    public static func shelf(sampleRate: Double) -> Biquad {
        let k: Double = tan(Double.pi * shelfFrequency / sampleRate)
        let kSquared: Double = k * k
        let vh: Double = pow(10, shelfGainDecibels / 20)
        let vb: Double = pow(vh, 0.4996667741545416)
        let kOverQ: Double = k / shelfQ
        let a0: Double = 1 + kOverQ + kSquared
        let b0: Double = (vh + vb * kOverQ + kSquared) / a0
        let b1: Double = 2 * (kSquared - vh) / a0
        let b2: Double = (vh - vb * kOverQ + kSquared) / a0
        let a1: Double = 2 * (kSquared - 1) / a0
        let a2: Double = (1 - kOverQ + kSquared) / a0
        return Biquad(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
    }

    /// Stage 2: the high-pass, designed for `sampleRate` (numerator 1, −2, 1 as in BS.1770).
    public static func highPass(sampleRate: Double) -> Biquad {
        let k: Double = tan(Double.pi * highPassFrequency / sampleRate)
        let kSquared: Double = k * k
        let kOverQ: Double = k / highPassQ
        let a0: Double = 1 + kOverQ + kSquared
        let a1: Double = 2 * (kSquared - 1) / a0
        let a2: Double = (1 - kOverQ + kSquared) / a0
        return Biquad(b0: 1, b1: -2, b2: 1, a1: a1, a2: a2)
    }

    /// The cascade's power gain at `frequency` Hz for `sampleRate`.
    public static func powerGain(frequency: Double, sampleRate: Double) -> Double {
        let omega: Double = 2 * Double.pi * frequency / sampleRate
        let first: Double = shelf(sampleRate: sampleRate).powerResponse(omega: omega)
        let second: Double = highPass(sampleRate: sampleRate).powerResponse(omega: omega)
        return first * second
    }

    /// One power weight per bin of `size` (k·R/N); bin 0 (DC) is 0.
    public static func table(size: FFTSize, sampleRate: Double) -> [Float] {
        let first = shelf(sampleRate: sampleRate)
        let second = highPass(sampleRate: sampleRate)
        let points = Double(size.rawValue)
        return (0..<size.binCount).map { (k: Int) -> Float in
            guard k > 0 else { return 0 }
            let omega: Double = 2 * Double.pi * Double(k) / points
            let gain: Double = first.powerResponse(omega: omega) * second.powerResponse(omega: omega)
            return Float(gain)
        }
    }
}
