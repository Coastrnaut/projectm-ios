// ChannelSelection.swift — AUD-009: which channel of the analysis copy the analyzers see
// (specs/089-aud-009-channel-selection, contracts/channel-selection.md C1-C3; research AUD-009-D1 to D4).
//
// Where it sits: `ChannelSelectionReader` wraps the normalized ring's analysis tap (ANL-001-R9), inside
// AUD-008's `InputTrimReader`: tap → selection → trim → `WaveformTap` → ANL-016 pipeline. Each read
// forwards to the tap, which copies frames into the consumer's buffer; only then are both channels of
// each frame replaced by the selected signal s, in that buffer. projectM's ring, the PCM sink, the
// audio-state classifier's levels and playback never see it.
//
// Modes (s per frame; k = 1/√2):
//   mix   (L + R)·0.5   today's behaviour: the reader returns at once (bit-exact) and the downstream
//                        mono mix computes it, exactly as before;
//   left  L;  right R;
//   mid   (L + R)·k     the M of the orthonormal (equal-power) mid/side pair;
//   side  (L − R)·k     its S, so M² + S² = L² + R².
// Writing s into both channels makes every downstream mono mix ((s + s)·0.5, `.left`, `.right`) equal s
// exactly, so the pipeline and the oscilloscope need no change and always agree.
//
// Real-time safety (Constitution VII): a read does one relaxed atomic load and at most an add and a
// multiply per frame; it never allocates, locks or logs, and runs on the analysis worker only.
import Synchronization

/// The analysed channel (data-model.md). The raw value is the atomic's; `storedValue` is the setting's.
public enum AnalysisChannelMode: UInt8, CaseIterable, Sendable {
    case mix = 0
    case left = 1
    case right = 2
    case mid = 3
    case side = 4

    /// Unknown raw values read as `.mix`.
    public init(validating raw: UInt8) {
        self = AnalysisChannelMode(rawValue: raw) ?? .mix
    }

    /// The string stored in UserDefaults.
    public var storedValue: String {
        switch self {
        case .mix: return "mix"
        case .left: return "left"
        case .right: return "right"
        case .mid: return "mid"
        case .side: return "side"
        }
    }

    /// Missing or unknown strings read as `.mix`.
    public init(storedValue: String?) {
        let match = AnalysisChannelMode.allCases.first { (mode: AnalysisChannelMode) -> Bool in mode.storedValue == storedValue }
        self = match ?? .mix
    }
}

/// The modes' maths (contract C1).
public enum ChannelSelection {
    /// 1/√2, the orthonormal mid/side scale.
    public static let inverseSquareRootOfTwo: Float = 0.707_106_77

    /// Replaces both channels of `frames` interleaved stereo frames with the selected signal, in place.
    /// `.mix` touches nothing (bit-exact).
    public static func apply(_ samples: UnsafeMutablePointer<Float>, frames: Int, mode: AnalysisChannelMode) {
        guard frames > 0 else { return }
        let k: Float = inverseSquareRootOfTwo
        switch mode {
        case .mix:
            return
        case .left:
            for i in 0..<frames {
                let index = 2 * i
                samples[index + 1] = samples[index]
            }
        case .right:
            for i in 0..<frames {
                let index = 2 * i
                samples[index] = samples[index + 1]
            }
        case .mid:
            for i in 0..<frames {
                let index = 2 * i
                let sum: Float = samples[index] + samples[index + 1]
                let s: Float = sum * k
                samples[index] = s
                samples[index + 1] = s
            }
        case .side:
            for i in 0..<frames {
                let index = 2 * i
                let difference: Float = samples[index] - samples[index + 1]
                let s: Float = difference * k
                samples[index] = s
                samples[index + 1] = s
            }
        }
    }
}

/// The shared mode: written by the app (any thread), read by each analysis read (contract C2).
public final class ChannelSelectionControl: Sendable {
    private let raw: Atomic<UInt8>

    public init(mode: AnalysisChannelMode = .mix) {
        raw = Atomic(mode.rawValue)
    }

    /// Lock-free.
    public var mode: AnalysisChannelMode {
        get { AnalysisChannelMode(validating: raw.load(ordering: .relaxed)) }
        set { raw.store(newValue.rawValue, ordering: .relaxed) }
    }
}

/// The analysis tap seen through the channel selection (contract C3). One consumer thread only.
public final class ChannelSelectionReader: NormalizedPCMReader, AnalysisSessionReporting, @unchecked Sendable {
    private let reader: any NormalizedPCMReader
    /// The wrapped reader's session reporting, cast once (no cast per read).
    private let reporting: (any AnalysisSessionReporting)?
    private let control: ChannelSelectionControl

    public init(_ reader: any NormalizedPCMReader, control: ChannelSelectionControl) {
        self.reader = reader
        reporting = reader as? any AnalysisSessionReporting
        self.control = control
    }

    /// Forwarded; 0 when the wrapped reader reports none.
    public var analysisSessionGeneration: UInt64 { reporting?.analysisSessionGeneration ?? 0 }

    public func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        let frames = reader.read(into: dst, maxFrames: maxFrames)
        guard frames > 0 else { return frames }
        ChannelSelection.apply(dst, frames: frames, mode: control.mode)
        return frames
    }
}
