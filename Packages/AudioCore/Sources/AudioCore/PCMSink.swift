// PCMSink.swift — the real-time entry point every source writes into (task T027;
// contracts/audio-source.md §PCMSink; research R-06).
//
// Real-time safety (Constitution VII): `write…` never allocates, locks, logs, or calls async
// code. All storage is preallocated in `init`; statistics are lock-free atomics.
// Loops on the producer path are index `while` loops, not `for … in 0..<n`: at -Onone (Debug,
// which is what Xcode's Run and Test actions build) iterating a Range goes through the
// unspecialized IndexingIterator, whose call to Range's subscript read coroutine heap-allocates
// its frame on every iteration. Optimized builds do not, but evidence runs use Debug.
//
// Session time (FR-022): `firstSampleSeconds`, `lastSampleSeconds` and `startToFirstAudioMs` are
// measured from the session start, which is the moment the source has actually started
// (`markSessionStart()`, called by the manager right after the source's `start` returned), not
// from before the system picker or permission prompt. A buffer that arrived before that mark
// counts as time 0.
//
// Storage: interleaved Float32 for up to `maxChannels` channels at the native rate. Integer
// samples are converted to Float32; planar input is interleaved. Streams with more channels
// keep the first `maxChannels` (the Normalizer downmixes, FR-017; research R-05). The ring holds
// 1 s of audio at up to `maxSampleRate` (capacity = maxSampleRate × maxChannels samples).
//
// Phase A consumers (level metering, classification) are channel-agnostic, so a format change
// mid-stream needs no flush; the new format is recorded and counted.
//
// Discontinuities (AUD-006): a source that jumps in its content (In-App Playback seeking or
// changing track) calls `discardBufferedAudio()` from its control side, so that nothing written
// before the jump is delivered after it. The consumer (AudioAnalyzer) registers how to do that for
// every stage behind the ring. This is not on the producer path.
import Synchronization

public final class PCMSink: @unchecked Sendable {
    public static let maxChannels = 8
    public static let maxSampleRate = 96_000
    public static let maxFramesPerWrite = 16_384

    public let ring: SPSCRingBuffer
    private let scratch: UnsafeMutablePointer<Float>
    private let scratchCapacity: Int
    /// Producer-owned plane-pointer scratch for planar `AudioBufferList` input.
    let planeScratch: UnsafeMutablePointer<UnsafeRawPointer?>

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
    /// The source's channel layout tag (`ChannelLayoutTag.rawValue`), 0 when unknown.
    private let layoutTag = Atomic<UInt32>(0)
    /// Longest capture delivery (arrival − capture timestamp) since the last take, in ns.
    private let deliveryMaxNs = Atomic<UInt64>(0)
    /// Deliveries longer than this are treated as a clock mismatch and ignored.
    static let maxPlausibleDeliveryNs: UInt64 = 10_000_000_000
    /// How the consumer discards undelivered audio (control side only; never used by `write…`).
    private let discardHandler = Mutex<(@Sendable () -> Void)?>(nil)

    public init() {
        ring = SPSCRingBuffer(capacity: PCMSink.maxSampleRate * PCMSink.maxChannels)
        scratchCapacity = PCMSink.maxFramesPerWrite * PCMSink.maxChannels
        scratch = UnsafeMutablePointer<Float>.allocate(capacity: scratchCapacity)
        scratch.initialize(repeating: 0, count: scratchCapacity)
        planeScratch = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: PCMSink.maxChannels)
        planeScratch.initialize(repeating: nil, count: PCMSink.maxChannels)
    }

    deinit {
        scratch.deinitialize(count: scratchCapacity)
        scratch.deallocate()
        planeScratch.deinitialize(count: PCMSink.maxChannels)
        planeScratch.deallocate()
    }

    /// Starts a new session: clears statistics and buffered audio. Call from the control side
    /// while no producer is writing (before `start`, after `stop`). `markSessionStart()` later
    /// moves the session start to when the source actually started.
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
        layoutTag.store(0, ordering: .relaxed)
        deliveryMaxNs.store(0, ordering: .relaxed)
        sessionStartNs.store(start, ordering: .releasing)
    }

    /// Sets the session start (time 0 for sample timestamps and start-to-first-audio) to `start`,
    /// normally the moment the source's `start` returned. Without it, the time of `reset` is used.
    /// A single lock-free atomic store; safe while a producer is writing, and buffers written
    /// before the mark are reported at 0 rather than negative.
    public func markSessionStart(atNanoseconds start: UInt64 = MonotonicClock.nowNanoseconds()) {
        sessionStartNs.store(start, ordering: .releasing)
    }

    // MARK: - Discontinuities (control side; AUD-006, contracts/transport.md)

    /// Discards every sample that was written but not yet delivered to a consumer. For the source
    /// that owns the producer, when its content jumps (seek, track change).
    ///
    /// The caller guarantees that no `write…` is in flight and none starts until this returns.
    /// When it returns, nothing written before the call can still reach a consumer: with an
    /// `AudioAnalyzer` attached that covers the ring, the converter's state and the normalized
    /// ring. Synchronous; never call it from an audio callback or from the analysis queue. The
    /// session (statistics, start time, audio state) is not touched: a jump is not a new session.
    public func discardBufferedAudio() {
        let handler = discardHandler.withLock { $0 }
        if let handler { handler() } else { ring.drain() }
    }

    /// Sets how the consumer discards undelivered audio; the handler must also empty this sink's
    /// ring. `AudioAnalyzer` registers itself at init. nil restores the default (drain the ring).
    public func setDiscardHandler(_ handler: (@Sendable () -> Void)?) {
        discardHandler.withLock { $0 = handler }
    }

    // MARK: - Producer API (real-time safe)

    /// Interleaved samples (`format.isInterleaved` must be true). `layout` is the source's channel
    /// layout, if it reports one; the Normalizer uses it to downmix more than 2 channels (R-05).
    public func writeInterleaved(_ samples: UnsafeRawPointer, frames: Int, format: AudioFormat,
                                 layout: ChannelLayoutTag = .unknown, captureTimeNs: UInt64 = 0,
                                 hostTimeNs: UInt64 = MonotonicClock.nowNanoseconds()) {
        guard frames > 0, format.isValid else { return }
        let inChannels = format.channelCount
        let outChannels = min(inChannels, PCMSink.maxChannels)
        var offset = 0
        while offset < frames {
            let n = min(frames - offset, PCMSink.maxFramesPerWrite)
            // Index loops, not `for in 0..<n`: see the header (Range iteration allocates at -Onone).
            var f = 0
            while f < n {
                let base = (offset + f) * inChannels
                var c = 0
                while c < outChannels {
                    scratch[f * outChannels + c] = PCMSink.sample(samples, index: base + c, type: format.sampleType)
                    c += 1
                }
                f += 1
            }
            ring.write(scratch, count: n * outChannels)
            offset += n
        }
        record(frames: frames, format: format, layout: layout, captureTimeNs: captureTimeNs, hostTimeNs: hostTimeNs)
    }

    /// Planar samples: `planes[c]` points at channel c's samples (`format.isInterleaved` false).
    public func writePlanar(_ planes: UnsafePointer<UnsafeRawPointer?>, planeCount: Int, frames: Int,
                            format: AudioFormat, layout: ChannelLayoutTag = .unknown, captureTimeNs: UInt64 = 0,
                            hostTimeNs: UInt64 = MonotonicClock.nowNanoseconds()) {
        guard frames > 0, format.isValid, planeCount > 0 else { return }
        let outChannels = min(planeCount, PCMSink.maxChannels)
        var offset = 0
        while offset < frames {
            let n = min(frames - offset, PCMSink.maxFramesPerWrite)
            // Index loops, not `for in 0..<n`: see the header (Range iteration allocates at -Onone).
            var c = 0
            while c < outChannels {
                if let plane = planes[c] {
                    var f = 0
                    while f < n {
                        scratch[f * outChannels + c] = PCMSink.sample(plane, index: offset + f, type: format.sampleType)
                        f += 1
                    }
                }
                c += 1
            }
            ring.write(scratch, count: n * outChannels)
            offset += n
        }
        record(frames: frames, format: format, layout: layout, captureTimeNs: captureTimeNs, hostTimeNs: hostTimeNs)
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

    /// Returns the longest capture delivery since the previous call, in nanoseconds (0 if no
    /// write carried a capture timestamp), and starts a new measurement. Consumer side.
    public func takeCaptureDeliveryMaxNs() -> UInt64 {
        deliveryMaxNs.exchange(0, ordering: .relaxed)
    }

    /// Channel layout of the latest write (`.unknown` if the source reported none).
    public var currentLayout: ChannelLayoutTag {
        ChannelLayoutTag(rawValue: layoutTag.load(ordering: .acquiring))
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

    private func record(frames: Int, format: AudioFormat, layout: ChannelLayoutTag, captureTimeNs: UInt64,
                        hostTimeNs: UInt64) {
        layoutTag.store(layout.rawValue, ordering: .releasing)
        if captureTimeNs > 0, hostTimeNs >= captureTimeNs, hostTimeNs - captureTimeNs < PCMSink.maxPlausibleDeliveryNs {
            let delivery = hostTimeNs - captureTimeNs
            var currentMax = deliveryMaxNs.load(ordering: .relaxed)
            while delivery > currentMax {
                let (exchanged, original) = deliveryMaxNs.compareExchange(
                    expected: currentMax, desired: delivery, ordering: .relaxed)
                if exchanged { break }
                currentMax = original
            }
        }
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
