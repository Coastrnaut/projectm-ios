// TestSupport.swift — test-only helpers for ANL-001: a Double-precision reference DFT with the same
// window and normalization as the production analyzer, fixed-seed noise, bitwise comparison and
// channel extraction. No Accelerate, AVFAudio or SwiftUI here (runs on Linux and with
// -DANALYSIS_NO_ACCELERATE).
import XCTest
@testable import AnalysisFeatures
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum TestSupport {
    /// Every backend compiled into this build (the portable one always).
    static var backends: [SpectrumBackend] {
        SpectrumBackend.isAcceleratedAvailable ? [.accelerated, .portable] : [.portable]
    }

    /// Linear-amplitude magnitudes by the defining sum, in Double: periodic Hann, `|X[k]|·4/N` for
    /// interior bins and `|X[k]|·2/N` for DC and Nyquist (research ANL-001-D4). Slow; small N only.
    static func referenceMagnitudes(_ samples: ArraySlice<Float>, size: Int) -> [Double] {
        let start = samples.startIndex
        var windowed = [Double](repeating: 0, count: size)
        var cosines = [Double](repeating: 0, count: size)
        var sines = [Double](repeating: 0, count: size)
        for n in 0..<size {
            let angle = 2 * Double.pi * Double(n) / Double(size)
            cosines[n] = cos(angle)
            sines[n] = sin(angle)
            windowed[n] = Double(samples[start + n]) * (0.5 - 0.5 * cos(angle))
        }
        var result = [Double](repeating: 0, count: size / 2 + 1)
        let mask = size - 1
        for k in 0...(size / 2) {
            var re = 0.0, im = 0.0, index = 0
            for n in 0..<size {
                re += windowed[n] * cosines[index]
                im -= windowed[n] * sines[index]
                index = (index + k) & mask
            }
            let scale = (k == 0 || k == size / 2) ? 2.0 / Double(size) : 4.0 / Double(size)
            result[k] = (re * re + im * im).squareRoot() * scale
        }
        return result
    }

    /// Deterministic uniform noise in [-amplitude, amplitude) from a 64-bit LCG.
    static func noise(count: Int, seed: UInt64 = 0x5EED, amplitude: Float = 0.5) -> [Float] {
        var state = seed
        return (0..<count).map { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let unit = Float(state >> 40) / Float(1 << 24)        // [0, 1)
            return (unit * 2 - 1) * amplitude
        }
    }

    /// A sine of `amplitude` at `bin` cycles per `size` samples (centred on that bin).
    static func binCentredSine(bin: Int, size: Int, amplitude: Float, count: Int? = nil) -> [Float] {
        (0..<(count ?? size)).map { n in
            amplitude * Float(sin(2 * Double.pi * Double(bin) * Double(n) / Double(size)))
        }
    }

    static func bitPattern(_ values: [Float]) -> [UInt32] { values.map(\.bitPattern) }

    static func channel(_ interleaved: [Float], _ index: Int, of channels: Int) -> [Float] {
        stride(from: index, to: interleaved.count, by: channels).map { interleaved[$0] }
    }

    static func peakBin(_ values: [Float]) -> Int {
        values.indices.max { values[$0] < values[$1] }!
    }

    static func peakBin(_ values: UnsafeBufferPointer<Float>) -> Int {
        var best = 0
        for k in values.indices where values[k] > values[best] { best = k }
        return best
    }

    /// Runs a stream over `samples` (mono) and returns every frame with a copy of its magnitudes.
    static func frames(of samples: [Float], configuration: SpectrumConfiguration,
                       backend: SpectrumBackend) -> [(frame: SpectrumFrame, magnitudes: [Float])] {
        let stream = SpectrumStream(configuration: configuration, backend: backend, clock: { 0 })
        var out: [(SpectrumFrame, [Float])] = []
        samples.withUnsafeBufferPointer { buffer in
            var offset = 0
            while offset < buffer.count || stream.bufferedSamples >= configuration.size.rawValue {
                if offset < buffer.count {
                    offset += stream.append(mono: buffer.baseAddress! + offset, count: buffer.count - offset)
                }
                while let frame = stream.nextFrame() {
                    out.append((frame, Array(stream.magnitudes)))
                }
                if offset >= buffer.count { break }
            }
        }
        return out
    }
}
