// SourceHandoff.swift — AUD-012: the renderer boundary's sanitizer and the source-switch envelope
// (specs/092-aud-012-source-crossfade, contracts/source-handoff.md C1; research AUD-012-D2 to D4).
//
// Both run where `NormalizedPCMRing.write` hands samples to projectM's ring and the analysis tap, on
// the analysis work queue (never an audio callback).
//
// * `PCMSanitizer`: NaN and ±Inf become 0, finite values beyond ±`bound` (2.0, +6 dBFS) are clamped.
//   `isClean` is one compare per sample (a NaN fails `<=`), so clean audio is never copied.
// * `HandoffEnvelope`: a duck, not a crossfade (AUD-012-D1). An integer ramp position 0…`fadeFrames`
//   (100 ms at 44.1 kHz) gives gain = position / fadeFrames, so the end points are exactly 0 and 1.
//   Unity → fading out (old source still delivering) → silent → fading in (new source) → unity. A
//   fade-out that cannot wait for audio is completed from the last written frame over
//   min(position, `maxForcedFrames`) frames, so the step it adds is at most |last| / 1,024 and it
//   fits, with the 1,024-frame silence, inside R-06's 2,205-frame freshness window.
//
// Real-time safety (Constitution VII): scalar state, index `while` loops (Range iteration allocates
// at -Onone, see PCMSink.swift), no allocation, lock or logging. Not thread-safe: one producer.

/// Replaces non-finite and out-of-range samples (AUD-012-R9, R10).
public enum PCMSanitizer {
    /// The largest magnitude handed to the renderer: ±2.0 (+6 dBFS; AUD-012 clarification 3).
    public static let bound: Float = 2

    /// True when every sample is finite and within ±`bound`. One compare per sample.
    @inline(__always)
    public static func isClean(_ samples: UnsafePointer<Float>, count: Int, bound: Float = PCMSanitizer.bound) -> Bool {
        var i = 0
        while i < count {
            let magnitude: Float = abs(samples[i])
            if !(magnitude <= bound) { return false }   // NaN and ±Inf fail here too
            i += 1
        }
        return true
    }

    /// NaN/±Inf → 0, x > bound → bound, x < −bound → −bound. Returns how many samples changed.
    @discardableResult
    public static func sanitize(_ samples: UnsafeMutablePointer<Float>, count: Int, bound: Float = PCMSanitizer.bound) -> Int {
        var replaced = 0
        var i = 0
        while i < count {
            let value = samples[i]
            if !value.isFinite {
                samples[i] = 0
                replaced += 1
            } else if value > bound {
                samples[i] = bound
                replaced += 1
            } else if value < -bound {
                samples[i] = -bound
                replaced += 1
            }
            i += 1
        }
        return replaced
    }

    /// NaN/±Inf → 0 only (the analyzer's input stage, before levels and conversion; AUD-012-D4).
    @discardableResult
    public static func replaceNonFinite(_ samples: UnsafeMutablePointer<Float>, count: Int) -> Int {
        var replaced = 0
        var i = 0
        while i < count {
            if !samples[i].isFinite {
                samples[i] = 0
                replaced += 1
            }
            i += 1
        }
        return replaced
    }
}

/// The gain ramp of a source switch on interleaved stereo frames (data-model.md).
public struct HandoffEnvelope: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case unity, fadingOut, silent, fadingIn
    }

    /// 100 ms at 44.1 kHz: each linear ramp (fade-out and fade-in).
    public static let fadeFrames = 4_410
    /// The silence between the two sources: 1,024 frames (23 ms).
    public static let silenceFrames = 1_024
    /// The longest synthesized ramp when a fade-out completes without audio.
    public static let maxForcedFrames = 1_024

    public private(set) var phase: Phase = .unity
    /// 0…fadeFrames; gain = position / fadeFrames.
    public private(set) var position: Int = HandoffEnvelope.fadeFrames
    /// The last frame written (after the gain), the start of a forced fade-out.
    public private(set) var lastLeft: Float = 0
    public private(set) var lastRight: Float = 0

    public init() {}

    public var gain: Float {
        let p = Float(position)
        let n = Float(HandoffEnvelope.fadeFrames)
        return p / n
    }

    public var isUnity: Bool { phase == .unity }

    /// Back to unity (a new session that is not a handoff).
    public mutating func reset() {
        phase = .unity
        position = HandoffEnvelope.fadeFrames
        lastLeft = 0
        lastRight = 0
    }

    /// Starts (or continues) fading to silence from the current position. Silent stays silent.
    public mutating func beginFadeOut() {
        switch phase {
        case .unity, .fadingIn: phase = position > 0 ? .fadingOut : .silent
        case .fadingOut, .silent: break
        }
    }

    /// Starts fading in from the current position (0 after a handoff's silence).
    public mutating func beginFadeIn() {
        switch phase {
        case .silent, .fadingOut: phase = position < HandoffEnvelope.fadeFrames ? .fadingIn : .unity
        case .unity, .fadingIn: break
        }
    }

    /// Silent with position 0 (the handoff's silence was written; nothing of the old source remains).
    public mutating func markSilent() {
        phase = .silent
        position = 0
        lastLeft = 0
        lastRight = 0
    }

    /// Remembers the last frame of a write that bypassed `apply` (the unity fast path).
    @inline(__always)
    public mutating func noteLast(left: Float, right: Float) {
        lastLeft = left
        lastRight = right
    }

    /// Scales `frames` interleaved stereo frames in place, advancing the ramp one step per frame.
    public mutating func apply(_ samples: UnsafeMutablePointer<Float>, frames: Int) {
        guard frames > 0 else { return }
        let n = Float(HandoffEnvelope.fadeFrames)
        var f = 0
        while f < frames {
            switch phase {
            case .unity:
                break
            case .fadingOut:
                position -= 1
                if position <= 0 {
                    position = 0
                    phase = .silent
                }
            case .fadingIn:
                position += 1
                if position >= HandoffEnvelope.fadeFrames {
                    position = HandoffEnvelope.fadeFrames
                    phase = .unity
                }
            case .silent:
                position = 0
            }
            let p = Float(position)
            let g: Float = p / n
            if g != 1 {
                samples[2 * f] *= g
                samples[2 * f + 1] *= g
            }
            f += 1
        }
        lastLeft = samples[2 * frames - 2]
        lastRight = samples[2 * frames - 1]
    }

    /// Frames a forced completion writes: min(position, maxForcedFrames); 0 unless fading out.
    public var forcedFrames: Int {
        phase == .fadingOut ? min(position, HandoffEnvelope.maxForcedFrames) : 0
    }

    /// Writes the next ≤ `maxFrames` frames of a forced fade-out ramp from the last frame into `dst`,
    /// with `index` the ramp frame of `dst[0]` and `total` the ramp length (`forcedFrames` at its
    /// start). Frame k = last · (total − 1 − k) / total, so the last frame is exactly 0.
    public static func forcedRamp(into dst: UnsafeMutablePointer<Float>, from index: Int, frames: Int,
                                  total: Int, left: Float, right: Float) {
        let t = Float(total)
        var f = 0
        while f < frames {
            let remaining = Float(total - 1 - (index + f))
            let g: Float = remaining / t
            dst[2 * f] = left * g
            dst[2 * f + 1] = right * g
            f += 1
        }
    }
}
