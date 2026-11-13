// SpectrumStream.swift — framing a continuous stream into overlapping windowed spectra
// (ANL-001-R5 to R7, R13, R14, R17; research ANL-001-D6).
//
// A linear mono FIFO of 16,384 samples (twice the largest FFT) collects input. `nextFrame()`
// computes a spectrum whenever `size` samples are buffered, then advances by `hop` (one memmove of
// the remainder). Frame index = samples advanced past since creation or the last `reset()`: a
// deterministic sample clock. Each frame also carries the injected clock's reading
// (`MonotonicClock.nowNanoseconds()` by default) for alignment with other timestamped data.
//
// `append` never drops: it accepts at most the free space and returns how much it took, so frame
// indices stay exact; overflow is handled (and counted) once, by the normalized ring's analysis tap.
// A size or hop change takes effect at the next frame and keeps buffered audio and the index.
//
// Real-time safety (Constitution VII): everything is allocated in `init`; `append`, `nextFrame`,
// `pull` and `setConfiguration` only touch preallocated memory. Not Sendable: confined to the one
// worker that owns it (ANL-016 provides that worker). Nothing here is passed to projectM.
import AudioCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Metadata of one computed spectrum (ANL-001-R7). The magnitudes are read from the stream.
public struct SpectrumFrame: Sendable, Equatable {
    /// First input sample of the window, counted since the stream's creation or last reset.
    public let index: Int64
    public let size: FFTSize
    public let sampleRate: Double
    /// The stream's clock when the frame was computed (monotonic nanoseconds by default).
    public let timestampNanoseconds: UInt64

    public init(index: Int64, size: FFTSize, sampleRate: Double, timestampNanoseconds: UInt64) {
        self.index = index
        self.size = size
        self.sampleRate = sampleRate
        self.timestampNanoseconds = timestampNanoseconds
    }
}

public final class SpectrumStream {
    /// Mono samples the FIFO holds: twice the largest FFT size.
    public static let fifoCapacity = 2 * FFTSize.maximum.rawValue
    /// Stereo frames `pull(from:)` reads per chunk.
    public static let pullChunkFrames = 2_048

    public private(set) var configuration: SpectrumConfiguration
    private let analyzer: SpectrumAnalyzer
    private let clock: @Sendable () -> UInt64
    private let fifo: UnsafeMutablePointer<Float>
    private let output: UnsafeMutablePointer<Float>
    private let scratch: UnsafeMutablePointer<Float>
    private let scratchCount = SpectrumStream.pullChunkFrames * 2
    private var buffered = 0
    private var nextIndex: Int64 = 0
    private var lastBinCount = 0

    public init(configuration: SpectrumConfiguration, backend: SpectrumBackend = .automatic,
                clock: @escaping @Sendable () -> UInt64 = { MonotonicClock.nowNanoseconds() }) {
        self.configuration = configuration
        self.clock = clock
        analyzer = SpectrumAnalyzer(backend: backend)
        fifo = .allocate(capacity: SpectrumStream.fifoCapacity)
        fifo.initialize(repeating: 0, count: SpectrumStream.fifoCapacity)
        output = .allocate(capacity: FFTSize.maximum.binCount)
        output.initialize(repeating: 0, count: FFTSize.maximum.binCount)
        scratch = .allocate(capacity: scratchCount)
        scratch.initialize(repeating: 0, count: scratchCount)
    }

    deinit {
        fifo.deinitialize(count: SpectrumStream.fifoCapacity); fifo.deallocate()
        output.deinitialize(count: FFTSize.maximum.binCount); output.deallocate()
        scratch.deinitialize(count: scratchCount); scratch.deallocate()
    }

    /// The backend actually used (`.accelerated` or `.portable`).
    public var resolvedBackend: SpectrumBackend { analyzer.resolvedBackend }

    /// Mono samples waiting in the FIFO.
    public var bufferedSamples: Int { buffered }

    /// Takes effect at the next frame; keeps buffered audio and the frame index (ANL-001-R17).
    public func setConfiguration(_ configuration: SpectrumConfiguration) {
        self.configuration = configuration
    }

    /// Empties the FIFO and restarts frame indices at 0.
    public func reset() {
        buffered = 0
        nextIndex = 0
        lastBinCount = 0
    }

    /// Appends interleaved audio with `channels` channels (1 = mono, taken as is; ≥ 2 = the first
    /// two channels mixed per `configuration.channelMode`). Returns the frames accepted, at most the
    /// FIFO's free space; call `nextFrame()` to make room for the rest.
    @discardableResult
    public func append(interleaved samples: UnsafePointer<Float>, frames: Int, channels: Int) -> Int {
        guard channels > 0, frames > 0 else { return 0 }
        let count = min(frames, SpectrumStream.fifoCapacity - buffered)
        guard count > 0 else { return 0 }
        let destination = fifo + buffered
        if channels == 1 {
            destination.update(from: samples, count: count)
        } else {
            switch configuration.channelMode {
            case .mid:
                for i in 0..<count {
                    destination[i] = (samples[i * channels] + samples[i * channels + 1]) * 0.5
                }
            case .left:
                for i in 0..<count { destination[i] = samples[i * channels] }
            case .right:
                for i in 0..<count { destination[i] = samples[i * channels + 1] }
            }
        }
        buffered += count
        return count
    }

    /// Appends mono samples; returns how many were accepted (at most the free space).
    @discardableResult
    public func append(mono samples: UnsafePointer<Float>, count: Int) -> Int {
        append(interleaved: samples, frames: count, channels: 1)
    }

    /// Computes the next spectrum if a whole window is buffered, then advances by the hop.
    /// The magnitudes are in `magnitudes` until the next call.
    public func nextFrame() -> SpectrumFrame? {
        let size = configuration.size
        let n = size.rawValue
        guard buffered >= n else { return nil }
        analyzer.magnitudes(of: fifo, size: size, into: output)
        lastBinCount = size.binCount
        let frame = SpectrumFrame(index: nextIndex, size: size, sampleRate: configuration.sampleRate,
                                  timestampNanoseconds: clock())
        let hop = configuration.hop
        let remaining = buffered - hop
        if remaining > 0 { memmove(fifo, fifo + hop, remaining * MemoryLayout<Float>.stride) }   // overlapping
        buffered = remaining
        nextIndex += Int64(hop)
        return frame
    }

    /// The last frame's linear magnitudes (`binCount` values); empty before the first frame and
    /// after `reset()`. Valid until the next `nextFrame()`.
    public var magnitudes: UnsafeBufferPointer<Float> {
        UnsafeBufferPointer(start: output, count: lastBinCount)
    }

    /// Copies the last frame's magnitudes into `destination` (room for `binCount` values).
    public func copyMagnitudes(into destination: UnsafeMutablePointer<Float>) {
        destination.update(from: output, count: lastBinCount)
    }

    /// Reads stereo frames from `reader` (the normalized ring's analysis tap) until it is empty,
    /// calling `body` for every frame that becomes ready. Returns the stereo frames read.
    @discardableResult
    public func pull(from reader: some NormalizedPCMReader,
                     _ body: (SpectrumFrame, UnsafeBufferPointer<Float>) -> Void) -> Int {
        var total = 0
        while true {
            let room = SpectrumStream.fifoCapacity - buffered
            let wanted = min(SpectrumStream.pullChunkFrames, room)
            let read = wanted > 0 ? reader.read(into: scratch, maxFrames: wanted) : 0
            if read > 0 {
                let accepted = append(interleaved: scratch, frames: read, channels: NormalizedPCMRing.channelCount)
                precondition(accepted == read, "pull read only what fits")
                total += read
            }
            var produced = false
            while let frame = nextFrame() {
                body(frame, magnitudes)
                produced = true
            }
            if read == 0 && !produced { return total }
            if read < wanted && !produced { return total }
        }
    }
}
