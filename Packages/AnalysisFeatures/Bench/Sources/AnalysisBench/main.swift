// AnalysisBench — CPU per spectrum frame for every FFT size and backend (ANL-001-T21; research
// ANL-001-D9). Reported, never asserted. Run in Release:
//   swift run -c release --package-path Packages/AnalysisFeatures/Bench AnalysisBench
// Pass `--loop-seconds N` to repeat the timed loops for about N seconds (for an allocation trace
// with `xcrun xctrace record --template Allocations --launch -- <binary> --loop-seconds 5`).
import AnalysisFeatures
import AudioCore

let arguments = CommandLine.arguments
let loopSeconds = arguments.firstIndex(of: "--loop-seconds").flatMap { Int(arguments[$0 + 1]) } ?? 0
let sampleRate = 44_100.0
let framesPerRun = 2_000

// Fixed-seed noise, long enough for every size at its default hop.
var state: UInt64 = 0x5EED
let maxSamples = FFTSize.maximum.rawValue + framesPerRun * FFTSize.maximum.rawValue / 2
let noise: [Float] = (0..<maxSamples).map { _ in
    state = state &* 6364136223846793005 &+ 1442695040888963407
    return (Float(state >> 40) / Float(1 << 24) * 2 - 1) * 0.5
}

var backends: [SpectrumBackend] = [.portable]
if SpectrumBackend.isAcceleratedAvailable { backends.insert(.accelerated, at: 0) }

print("ANL-001 AnalysisBench: \(framesPerRun) frames per size, default hop (N/2), \(Int(sampleRate)) Hz")
print("backend      size   ns/frame   frames/s needed   % of one core")
var sink: Float = 0
let deadline = MonotonicClock.nowNanoseconds() + UInt64(loopSeconds) * 1_000_000_000
repeat {
    for backend in backends {
        let analyzer = SpectrumAnalyzer(backend: backend)
        var output = [Float](repeating: 0, count: FFTSize.maximum.binCount)
        for size in FFTSize.allCases {
            let hop = size.rawValue / 2
            noise.withUnsafeBufferPointer { input in
                output.withUnsafeMutableBufferPointer { out in
                    // Warm-up, then the timed loop (allocation-free: pointers only).
                    for i in 0..<50 { analyzer.magnitudes(of: input.baseAddress! + i * hop, size: size, into: out.baseAddress!) }
                    let start = MonotonicClock.nowNanoseconds()
                    for i in 0..<framesPerRun {
                        analyzer.magnitudes(of: input.baseAddress! + i * hop, size: size, into: out.baseAddress!)
                        sink += out[1]
                    }
                    let elapsed = MonotonicClock.nowNanoseconds() - start
                    let perFrame = Double(elapsed) / Double(framesPerRun)
                    let framesPerSecond = sampleRate / Double(hop)
                    let share = perFrame * framesPerSecond / 1e9 * 100
                    if loopSeconds == 0 || MonotonicClock.nowNanoseconds() >= deadline {
                        let name = backend == .accelerated ? "accelerated" : "portable   "
                        print("\(name)  \(String(size.rawValue).padding(5))  \(String(Int(perFrame.rounded())).padding(9))  \(String(format1(framesPerSecond)).padding(16))  \(format3(share))")
                    }
                }
            }
        }
    }
    // The streaming path (interleaved stereo append + nextFrame at the default hop), 2,048 points.
    let stereo: [Float] = (0..<(noise.count / 2 * 2)).map { noise[$0 / 2] }
    let stream = SpectrumStream(configuration: try! SpectrumConfiguration(size: .n2048))
    let streamStart = MonotonicClock.nowNanoseconds()
    var streamFrames = 0
    stereo.withUnsafeBufferPointer { input in
        var offset = 0
        let frames = min(input.count / 2, 2_048 + framesPerRun * 1_024)
        while offset < frames {
            offset += stream.append(interleaved: input.baseAddress! + 2 * offset, frames: min(512, frames - offset), channels: 2)
            while stream.nextFrame() != nil { streamFrames += 1; sink += stream.magnitudes[1] }
        }
    }
    let streamNs = Double(MonotonicClock.nowNanoseconds() - streamStart) / Double(max(1, streamFrames))
    if loopSeconds == 0 || MonotonicClock.nowNanoseconds() >= deadline {
        print("stream (\(stream.resolvedBackend == .accelerated ? "accelerated" : "portable"), 2048, append 512-frame blocks + nextFrame): \(Int(streamNs.rounded())) ns/frame over \(streamFrames) frames")
    }
} while MonotonicClock.nowNanoseconds() < deadline
print("checksum \(sink)")

func format1(_ value: Double) -> String { String(Double(Int(value * 10)) / 10) }
func format3(_ value: Double) -> String { String(Double(Int(value * 1000)) / 1000) }

extension String {
    func padding(_ width: Int) -> String { count >= width ? self : String(repeating: " ", count: width - count) + self }
}
