// PlaybackDebugProbe.swift — QA-011 device tests only (DEBUG builds; Release contains none of this): what the
// In-App Playback tap really delivered, buffer by buffer, so a device test can check on hardware that no audio from
// before a seek or a queue edit reaches the sink (AUD-006-T38; research question "does player.stop() precede the
// render cycle in flight?") and that edits leave no gap (AUD-003-T22, AUD-004-T19, AUD-005-T17).
//
// The tap writes one small record per delivered buffer (the first and last sample of channel 0, the buffer's peak,
// whether it is the first buffer after a cut) into a preallocated single-producer ring; the app drains it on the
// main actor and reads the records against the generated ramp fixtures (channel 0 is a slow ramp whose value
// names the track and the position in it). Off unless the app calls `enable()` (`-uitestPlaybackProbe`), and the
// tap captures the instance on the control side, so a tap never initialises anything.
//
// Real-time safety (Constitution VII): `record` does a bounded loop over the buffer, plain stores into memory
// allocated in `init`, and one atomic store. No allocation, no lock, no system call.
#if DEBUG
import Synchronization

public final class PlaybackDebugProbe: @unchecked Sendable {
    /// One delivered tap buffer.
    public struct Record: Sendable, Equatable {
        public var first: Float
        public var last: Float
        public var peak: Float
        public var frames: Int32
        public var sampleRate: Float
        public var firstAfterCut: Bool
        /// Frames at the buffer's start before channel 0's first non-zero sample, and that sample. The first buffer after
        /// a cut can start with zeros when the player starts inside a render cycle; `first` then names no position (QA-011
        /// device run 2026-11-18, D1-D3: 20 seeks, no cut and no jump recognised). `voiced` is the first position heard.
        public var leadingZeros: Int32 = 0
        public var voiced: Float = 0
    }

    public static let capacity = 8192
    private static let on = Atomic<Bool>(false)
    public static let shared = PlaybackDebugProbe()

    /// Turns recording on (main actor, before playback starts). Allocates the ring here, never in the tap.
    public static func enable() {
        _ = shared
        on.store(true, ordering: .sequentiallyConsistent)
    }

    /// The probe when recording is on; read on the control side when a tap is installed.
    public static var enabledInstance: PlaybackDebugProbe? {
        on.load(ordering: .sequentiallyConsistent) ? shared : nil
    }

    private let records: UnsafeMutablePointer<Record>
    private let written = Atomic<Int>(0)
    /// Consumer side only (the app's main actor).
    private var readIndex = 0
    /// Records the consumer missed because it fell more than `capacity` behind.
    public private(set) var lost = 0

    private init() {
        records = .allocate(capacity: Self.capacity)
        records.initialize(repeating: Record(first: 0, last: 0, peak: 0, frames: 0, sampleRate: 0, firstAfterCut: false),
                           count: Self.capacity)
    }

    /// Tap side. `channels` points at the buffer's channel data (`floatChannelData`); `stride` is the buffer's stride
    /// (1 for deinterleaved data, the channel count when interleaved in the first pointer).
    @inline(__always)
    public func record(_ channels: UnsafePointer<UnsafeMutablePointer<Float>>, channelCount: Int, stride: Int,
                       frames: Int, sampleRate: Double, firstAfterCut: Bool) {
        guard frames > 0, channelCount > 0, stride > 0 else { return }
        let c0 = channels[0]
        var peak: Float = 0
        if stride > 1 {
            for i in 0..<(frames * stride) { let m = abs(c0[i]); if m > peak { peak = m } }
        } else {
            for c in 0..<channelCount {
                let p = channels[c]
                for i in 0..<frames { let m = abs(p[i]); if m > peak { peak = m } }
            }
        }
        var lead = 0
        while lead < frames, abs(c0[lead * stride]) < 0.001 { lead += 1 }   // the ramps never go below 0.03; a literal, no static in the tap
        let index = written.load(ordering: .relaxed)
        records[index % Self.capacity] = Record(first: c0[0], last: c0[(frames - 1) * stride], peak: peak,
                                                frames: Int32(frames), sampleRate: Float(sampleRate),
                                                firstAfterCut: firstAfterCut, leadingZeros: Int32(lead),
                                                voiced: lead < frames ? c0[lead * stride] : 0)
        written.store(index + 1, ordering: .releasing)
    }

    /// Consumer side (one thread: the app's main actor): every record written since the last drain, in order.
    public func drain(_ body: (Record) -> Void) {
        let end = written.load(ordering: .acquiring)
        if end - readIndex > Self.capacity {
            lost += end - readIndex - Self.capacity
            readIndex = end - Self.capacity
        }
        while readIndex < end {
            body(records[readIndex % Self.capacity])
            readIndex += 1
        }
    }
}
#endif
