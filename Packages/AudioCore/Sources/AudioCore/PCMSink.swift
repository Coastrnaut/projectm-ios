// PCMSink.swift — the real-time entry point every source writes into (task T027;
// contracts/audio-source.md §PCMSink; research R-06).
//
// Real-time safety (Constitution VII): `write…` never allocates, locks, logs, or calls async
// code. All storage is preallocated in `init`; statistics are lock-free atomics.
//
// Storage: interleaved Float32 for up to `maxChannels` channels at the native rate. Integer
// samples are converted to Float32; planar input is interleaved. Streams with more channels
// keep the first `maxChannels` (proper downmixing is Plan Phase B, FR-017). The ring holds
// 1 s of audio at up to `maxSampleRate` (capacity = maxSampleRate × maxChannels samples).
//
// Phase A consumers (level metering, classification) are channel-agnostic, so a format change
// mid-stream needs no flush; the new format is recorded and counted.
import Synchronization

public final class PCMSink: @unchecked Sendable {
    public static let maxChannels = 8
    public static let maxSampleRate = 96_000
    public static let maxFramesPerWrite = 16_384

    public let ring: SPSCRingBuffer
    private let scratch: UnsafeMutablePointer<Float>
    private let scratchCapacity: Int

    // Statistics (written by the producer; read by the analysis queue).
    private let framesWritten = Atomic<Int>(0)
    private let buffersWritten = Atomic<Int>(0)
    private let firstHostNs = Atomic<UInt64>(0)
    private let lastHostNs = Atomic<UInt64>(0)
    private let intervalSumNs = Atomic<UInt64>(0)
    private let intervalMaxNs = Atomic<UInt64>(0)
    private let lateBuffers = Atomic<Int>(0)
    private let formatChanges = Atomic<Int>(0)
    private let packedFormat = Atomic<UInt64>(0)
    private let sessionStartNs = Atomic<UInt64>(0)

    public init() {
        ring = SPSCRingBuffer(capacity: PCMSink.maxSampleRate * PCMSink.maxChannels)
        scratchCapacity = PCMSink.maxFramesPerWrite * PCMSink.maxChannels
        scratch = UnsafeMutablePointer<Float>.allocate(capacity: scratchCapacity)
        scratch.initialize(repeating: 0, count: scratchCapacity)
    }

    deinit {
        scratch.deinitialize(count: scratchCapacity)
        scratch.deallocate()
    }

    /// Starts a new session: clears statistics and buffered audio. Call from the control side
    /// while no producer is writing (before `start`, after `stop`).
    public func reset(sessionStartNs start: UInt64 = MonotonicClock.nowNanoseconds()) {
        ring.drain()
        framesWritten.store(0, ordering: .relaxed)
        buffersWritten.store(0, ordering: .relaxed)
        firstHostNs.store(0, ordering: .relaxed)
        lastHostNs.store(0, ordering: .relaxed)
        intervalSumNs.store(0, ordering: .relaxed)
        intervalMaxNs.store(0, ordering: .relaxed)
        lateBuffers.store(0, ordering: .relaxed)
        formatChanges.store(0, ordering: .relaxed)
        packedFormat.store(0, ordering: .relaxed)
        sessionStartNs.store(start, ordering: .releasing)
    }

    // MARK: - Producer API (real-time safe)

    /// Interleaved samples (`format.isInterleaved` must be true).
    public func writeInterleaved(_ samples: UnsafeRawPointer, frames: Int, format: AudioFormat,
                                 hostTimeNs: UInt64 = MonotonicClock.nowNanoseconds()) {
        guard frames > 0, format.isValid else { return }
        let inChannels = format.channelCount
        let outChannels = min(inChannels, PCMSink.maxChannels)
        var offset = 0
        while offset < frames {
            let n = min(frames - offset, PCMSink.maxFramesPerWrite)
            for f in 0..<n {
                let base = (offset + f) * inChannels
                for c in 0..<outChannels {
                    scratch[f * outChannels + c] = PCMSink.sample(samples, index: base + c, type: format.sampleType)
                }
            }
            ring.write(scratch, count: n * outChannels)
            offset += n
        }
        record(frames: frames, format: format, hostTimeNs: hostTimeNs)
    }

    /// Planar samples: `planes[c]` points at channel c's samples (`format.isInterleaved` false).
    public func writePlanar(_ planes: UnsafePointer<UnsafeRawPointer?>, planeCount: Int, frames: Int,
                            format: AudioFormat, hostTimeNs: UInt64 = MonotonicClock.nowNanoseconds()) {
        guard frames > 0, format.isValid, planeCount > 0 else { return }
        let outChannels = min(planeCount, PCMSink.maxChannels)
        var offset = 0
        while offset < frames {
            let n = min(frames - offset, PCMSink.maxFramesPerWrite)
            for c in 0..<outChannels {
                guard let plane = planes[c] else { continue }
                for f in 0..<n {
                    scratch[f * outChannels + c] = PCMSink.sample(plane, index: offset + f, type: format.sampleType)
                }
            }
            ring.write(scratch, count: n * outChannels)
            offset += n
        }
        record(frames: frames, format: format, hostTimeNs: hostTimeNs)
    }

    // MARK: - Consumer API

    public func statistics() -> PCMSinkStatistics {
        let buffers = buffersWritten.load(ordering: .acquiring)
        let sumNs = intervalSumNs.load(ordering: .relaxed)
        let start = sessionStartNs.load(ordering: .acquiring)
        let first = firstHostNs.load(ordering: .relaxed)
        let last = lastHostNs.load(ordering: .relaxed)
        return PCMSinkStatistics(
            sampleCount: framesWritten.load(ordering: .relaxed),
            bufferCount: buffers,
            firstSampleSeconds: first == 0 ? nil : PCMSink.seconds(first, since: start),
            lastSampleSeconds: last == 0 ? nil : PCMSink.seconds(last, since: start),
            cadenceMeanMs: buffers > 1 ? Double(sumNs) / Double(buffers - 1) / 1_000_000 : 0,
            cadenceMaxMs: Double(intervalMaxNs.load(ordering: .relaxed)) / 1_000_000,
            droppedSamples: ring.droppedSamples,
            lateBuffers: lateBuffers.load(ordering: .relaxed),
            format: PCMSink.unpack(packedFormat.load(ordering: .acquiring)),
            formatChangeCount: formatChanges.load(ordering: .relaxed),
            startToFirstAudioMs: first == 0 ? nil : PCMSink.seconds(first, since: start) * 1000
        )
    }

    /// Current channel count of the buffered audio (0 before the first write).
    public var currentChannelCount: Int {
        min(PCMSink.unpack(packedFormat.load(ordering: .acquiring))?.channelCount ?? 0, PCMSink.maxChannels)
    }

    // MARK: - Private

    @inline(__always)
    private static func sample(_ base: UnsafeRawPointer, index: Int, type: SampleType) -> Float {
        switch type {
        case .float32:
            return base.load(fromByteOffset: index * 4, as: Float.self)
        case .int16:
            return Float(base.load(fromByteOffset: index * 2, as: Int16.self)) / 32_768
        case .int32:
            return Float(Double(base.load(fromByteOffset: index * 4, as: Int32.self)) / 2_147_483_648)
        }
    }

    private func record(frames: Int, format: AudioFormat, hostTimeNs: UInt64) {
        let packed = PCMSink.pack(format)
        let previous = packedFormat.exchange(packed, ordering: .acquiringAndReleasing)
        if previous != 0 && previous != packed {
            _ = formatChanges.add(1, ordering: .relaxed)
        }
        _ = framesWritten.add(frames, ordering: .relaxed)
        let count = buffersWritten.add(1, ordering: .acquiringAndReleasing).newValue
        if count == 1 {
            firstHostNs.store(hostTimeNs, ordering: .relaxed)
        } else {
            let last = lastHostNs.load(ordering: .relaxed)
            let interval = hostTimeNs > last ? hostTimeNs - last : 0
            let sum = intervalSumNs.add(interval, ordering: .relaxed).newValue
            let mean = sum / UInt64(count - 1)
            if count > 2 && interval > 2 * mean { _ = lateBuffers.add(1, ordering: .relaxed) }
            var currentMax = intervalMaxNs.load(ordering: .relaxed)
            while interval > currentMax {
                let (exchanged, original) = intervalMaxNs.compareExchange(
                    expected: currentMax, desired: interval, ordering: .relaxed)
                if exchanged { break }
                currentMax = original
            }
        }
        lastHostNs.store(hostTimeNs, ordering: .releasing)
    }

    private static func seconds(_ ns: UInt64, since start: UInt64) -> Double {
        ns >= start ? Double(ns - start) / 1_000_000_000 : 0
    }

    /// Bits: [63..32] sample rate (Hz), [31..16] channels, [15..8] sample type, [0] interleaved.
    static func pack(_ f: AudioFormat) -> UInt64 {
        let type: UInt64
        switch f.sampleType { case .float32: type = 1; case .int16: type = 2; case .int32: type = 3 }
        return (UInt64(max(0, min(f.sampleRate, 4_000_000_000))) << 32)
            | (UInt64(min(f.channelCount, 0xFFFF)) << 16) | (type << 8) | (f.isInterleaved ? 1 : 0)
    }

    static func unpack(_ v: UInt64) -> AudioFormat? {
        guard v != 0 else { return nil }
        let type: SampleType
        switch (v >> 8) & 0xFF { case 2: type = .int16; case 3: type = .int32; default: type = .float32 }
        return AudioFormat(sampleRate: Double(v >> 32), channelCount: Int((v >> 16) & 0xFFFF),
                           isInterleaved: v & 1 == 1, sampleType: type)
    }
}

/// Metadata-only view of the sink (no samples). Feeds DiagnosticsSnapshot (FR-020, FR-022).
public struct PCMSinkStatistics: Sendable, Equatable {
    public var sampleCount: Int
    public var bufferCount: Int
    public var firstSampleSeconds: Double?
    public var lastSampleSeconds: Double?
    public var cadenceMeanMs: Double
    public var cadenceMaxMs: Double
    public var droppedSamples: Int
    public var lateBuffers: Int
    public var format: AudioFormat?
    public var formatChangeCount: Int
    public var startToFirstAudioMs: Double?

    public init(sampleCount: Int = 0, bufferCount: Int = 0, firstSampleSeconds: Double? = nil,
                lastSampleSeconds: Double? = nil, cadenceMeanMs: Double = 0, cadenceMaxMs: Double = 0,
                droppedSamples: Int = 0, lateBuffers: Int = 0, format: AudioFormat? = nil,
                formatChangeCount: Int = 0, startToFirstAudioMs: Double? = nil) {
        self.sampleCount = sampleCount
        self.bufferCount = bufferCount
        self.firstSampleSeconds = firstSampleSeconds
        self.lastSampleSeconds = lastSampleSeconds
        self.cadenceMeanMs = cadenceMeanMs
        self.cadenceMaxMs = cadenceMaxMs
        self.droppedSamples = droppedSamples
        self.lateBuffers = lateBuffers
        self.format = format
        self.formatChangeCount = formatChangeCount
        self.startToFirstAudioMs = startToFirstAudioMs
    }
}
