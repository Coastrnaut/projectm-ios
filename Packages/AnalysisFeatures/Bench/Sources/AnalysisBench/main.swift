// AnalysisBench — CPU per spectrum frame for every FFT size and backend (ANL-001-T21; research
// ANL-001-D9), per band reduction (ANL-002-T16) and per onset `process` (ANL-004-T21). Reported,
// never asserted. Run in Release:
//   swift run -c release --package-path Packages/AnalysisFeatures/Bench AnalysisBench
// Pass `--loop-seconds N` to repeat the timed loops for about N seconds (for an allocation trace
// with `xcrun xctrace record --template Allocations --launch -- <binary> --loop-seconds 5`).
// `--anl001-sweep` and `--anl004-sweep` run the full acceptance cross-products instead
// (AcceptanceSweeps.swift; owner rule 7, 2026-11-13) and exit 1 on any failure.
import AnalysisFeatures
import AudioCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

let arguments = CommandLine.arguments
if arguments.contains("--anl001-sweep") { exit(runANL001Sweep()) }
if arguments.contains("--anl004-sweep") { exit(runANL004Sweep()) }
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
    // ANL-002: band reduction of one spectrum (ns per reduce), every band count at 2,048 and 8,192.
    for backend in backends {
        let reducer = try! BandReducer(sampleRate: sampleRate, backend: backend)
        let analyzer = SpectrumAnalyzer(backend: backend)
        var spectrum = [Float](repeating: 0, count: FFTSize.maximum.binCount)
        var bands = [Float](repeating: 0, count: BandCount.b128.rawValue)
        for size in [FFTSize.n2048, .n8192] {
            noise.withUnsafeBufferPointer { input in
                spectrum.withUnsafeMutableBufferPointer { s in
                    analyzer.magnitudes(of: input.baseAddress!, size: size, into: s.baseAddress!)
                    bands.withUnsafeMutableBufferPointer { out in
                        for count in BandCount.allCases {
                            for _ in 0..<50 { reducer.reduce(magnitudes: s.baseAddress!, size: size, bandCount: count, into: out.baseAddress!) }
                            let start = MonotonicClock.nowNanoseconds()
                            for _ in 0..<framesPerRun {
                                reducer.reduce(magnitudes: s.baseAddress!, size: size, bandCount: count, into: out.baseAddress!)
                                sink += out[0]
                            }
                            let perReduce = Double(MonotonicClock.nowNanoseconds() - start) / Double(framesPerRun)
                            if loopSeconds == 0 || MonotonicClock.nowNanoseconds() >= deadline {
                                let name = backend == .accelerated ? "accelerated" : "portable   "
                                print("bands \(name)  N=\(String(size.rawValue).padding(5))  B=\(String(count.rawValue).padding(3))  \(Int(perReduce.rounded())) ns/reduce")
                            }
                        }
                    }
                }
            }
        }
    }
    // ANL-004: one onset `process` call (band reduction + flux + threshold), alternating a noise
    // spectrum with a quieter copy so rises and decays both occur; contiguous frames at the default hop.
    for backend in backends {
        let detector = SpectralFluxOnsetDetector(backend: backend)
        let analyzer = SpectrumAnalyzer(backend: backend)
        for size in [FFTSize.n2048, .n8192] {
            var loud = [Float](repeating: 0, count: size.binCount)
            noise.withUnsafeBufferPointer { input in
                loud.withUnsafeMutableBufferPointer { analyzer.magnitudes(of: input.baseAddress!, size: size, into: $0.baseAddress!) }
            }
            let quiet = loud.map { $0 * 0.01 }
            let hop = size.rawValue / 2
            detector.reset()
            var index: Int64 = 0
            var events = 0
            loud.withUnsafeBufferPointer { l in
                quiet.withUnsafeBufferPointer { q in
                    func step() {
                        let frame = SpectrumFrame(index: index, size: size, sampleRate: sampleRate, timestampNanoseconds: 0, hop: hop)
                        if detector.process(frame, magnitudes: (index / Int64(hop)) % 8 == 0 ? l : q) != nil { events += 1 }
                        index += Int64(hop)
                    }
                    for _ in 0..<50 { step() }
                    let start = MonotonicClock.nowNanoseconds()
                    for _ in 0..<framesPerRun { step(); sink += detector.lastFlux }
                    let perProcess = Double(MonotonicClock.nowNanoseconds() - start) / Double(framesPerRun)
                    if loopSeconds == 0 || MonotonicClock.nowNanoseconds() >= deadline {
                        let name = backend == .accelerated ? "accelerated" : "portable   "
                        print("onsets \(name)  N=\(String(size.rawValue).padding(5))  B=64  \(Int(perProcess.rounded())) ns/process  (\(events) events)")
                    }
                }
            }
        }
    }
} while MonotonicClock.nowNanoseconds() < deadline
print("checksum \(sink)")

func format1(_ value: Double) -> String { String(Double(Int(value * 10)) / 10) }
func format3(_ value: Double) -> String { String(Double(Int(value * 1000)) / 1000) }

extension String {
    func padding(_ width: Int) -> String { count >= width ? self : String(repeating: " ", count: width - count) + self }
}
