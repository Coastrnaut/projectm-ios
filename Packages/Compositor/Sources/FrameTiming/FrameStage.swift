// FrameStage.swift — the labelled stages of one frame (PERF-001-R1; specs/152-perf-001-stage-timings,
// contracts/frame-stage-timer.md C1). Declaration order is frame order.

/// One measured stage of a frame. The label is the stable text shown in the overlay and exported.
public enum FrameStage: Int, CaseIterable, Sendable {
    /// The frame thread's audio intake: reading the analysis output, smoothing and modulation, or
    /// feeding projectM its PCM. Never the audio callback itself (T063).
    case audio
    /// Drawing the visual: the projectM engine, or the native generator with its glow.
    case render
    /// The compositor's layer stack.
    case composite
    /// The final screen pass: flash guard, grade and output, or projectM's flash-limiter pass.
    case output
    /// Copying the frame for a running video recording (REC-003); conditional.
    case encode
    /// Handing the frame to the display: present and commit, or the swap.
    case present

    public var label: String {
        switch self {
        case .audio: return "audio"
        case .render: return "render"
        case .composite: return "composite"
        case .output: return "output"
        case .encode: return "encode"
        case .present: return "present"
        }
    }

    /// PERF-001-R5: a conditional stage is reported only when at least one frame in the window measured it.
    public var isConditional: Bool { self == .encode }

    /// The bit of this stage in a frame mask (bits 0-5).
    var bit: UInt16 { UInt16(1) << UInt16(rawValue) }

    public static let count = FrameStage.allCases.count
}
