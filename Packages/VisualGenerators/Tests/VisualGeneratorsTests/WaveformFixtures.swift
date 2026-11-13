// WaveformFixtures.swift — VIS-003-T02: deterministic time-domain fixtures for the oscilloscope tests.
// A signal is a pure function of the absolute sample index, so a rolling history can be rebuilt for
// any end index and the true phase of any (fractional) history position is known exactly. No clock,
// no randomness beyond a fixed-seed hash.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

enum WaveformShape: String {
    case sine, square, saw, noise, silence
    /// sin(2πφ) + 0.7·sin(2π·3φ + 0.5): several rising crossings per period.
    case complex
}

struct WaveformSignal: CustomStringConvertible {
    var shape: WaveformShape
    var frequency: Double
    var sampleRate: Double = 44_100
    var amplitude: Double = 0.8
    var offset: Double = 0

    var description: String { "\(shape.rawValue) \(Int(frequency)) Hz @ \(Int(sampleRate)) offset \(offset)" }

    /// Cycles at absolute (fractional) sample position `n`, in 0..<1.
    func phase(at n: Double) -> Double {
        let t: Double = n * frequency / sampleRate
        return t - t.rounded(.down)
    }

    func value(at n: Int64) -> Float {
        let p: Double = phase(at: Double(n))
        let twoPi: Double = 2 * Double.pi
        let v: Double
        switch shape {
        case .sine: v = sin(twoPi * p)
        case .square: v = p < 0.5 ? 1 : -1
        case .saw: v = 2 * p - 1
        case .complex: v = (sin(twoPi * p) + 0.7 * sin(twoPi * 3 * p + 0.5)) / 1.7
        case .silence: v = 0
        case .noise:
            // splitmix64 of the index: uniform in −1…1, the same for the same index.
            var z: UInt64 = UInt64(bitPattern: n) &+ 0x9E37_79B9_7F4A_7C15
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z = z ^ (z >> 31)
            let unit: Double = Double(z >> 11) / Double(UInt64(1) << 53)
            v = 2 * unit - 1
        }
        return Float(amplitude * v + offset)
    }

    /// The `count` samples ending just before absolute index `end` (oldest first).
    func history(endingAt end: Int64, count: Int = 4_096) -> [Float] {
        (0..<count).map { (i: Int) -> Float in value(at: end - Int64(count) + Int64(i)) }
    }
}

enum WaveformFrames {
    /// A deterministic, varying advance of 700…770 samples per frame (about 60 fps at 44.1 kHz).
    static func advance(frame f: Int) -> Int64 { 700 + Int64((f * 37) % 71) }

    /// Signed difference of two phases in cycles, wrapped to −0.5…0.5.
    static func phaseDifference(_ a: Double, _ b: Double) -> Double {
        let d: Double = a - b
        return d - d.rounded()
    }
}
