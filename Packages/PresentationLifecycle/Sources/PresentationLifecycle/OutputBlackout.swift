// OutputBlackout.swift — OUT-010: the output blackout's state machine (spec
// specs/051-out-010-output-blackout-isolation, data-model.md, contracts/output-blackout.md).
//
// Black out is immediate: `blackOut()` makes the output black before it returns, so the next frame
// is black (OUT-010-R2). Restore fades the output's luminance in linearly over frame time, 1 s with
// Reduce flashing off and 4 s with it on (a white picture then rises at most 0.25 per second,
// FX-019-R8), and a restore starts at least 1 s of frame time after the previous one started, so
// toggling cannot strobe (research OUT-010-D2, D3). Time is the sum of frame times clamped to
// 0…0.1 s (FX-019-R10); there is no clock here. Pure Swift with no allocation, tested on the host
// and on Linux (OUT-010-R12). The app's ExternalDisplayCoordinator applies `coverOpacity` to an
// opaque black cover over the visual.
import Foundation

public struct OutputBlackout: Equatable, Sendable {
    public enum Phase: String, Equatable, Sendable {
        /// The visualization is shown.
        case live
        /// The output is black; the user asked for it.
        case blackedOut
        /// The user asked to restore; the output stays black until the restore spacing has passed.
        case restoreWaiting
        /// The output fades in from black.
        case fadingIn
    }

    /// The shortest frame time between two restore starts (OUT-010-R7).
    public static let restoreSpacing: Double = 1
    /// Frame times are clamped to 0…this (FX-019-R10).
    public static let maxFrameTime: Double = 0.1

    /// The restore fade's length in frame time (OUT-010-R6).
    public static func fadeDuration(reduceFlashing: Bool) -> Double { reduceFlashing ? 4 : 1 }

    /// The black cover's opacity that gives a white picture the luminance factor `f`: Core Animation
    /// blends the encoded (sRGB) values, so the shown encoded value is 1 − a = sRGBEncode(f).
    public static func coverOpacity(forLuminanceFactor f: Double) -> Double {
        let f = f.isFinite ? min(max(f, 0), 1) : 0
        if f <= 0 { return 1 }
        if f >= 1 { return 0 }
        let encoded = f <= 0.0031308 ? 12.92 * f : 1.055 * pow(f, 1 / 2.4) - 0.055
        return min(max(1 - encoded, 0), 1)
    }

    public private(set) var phase: Phase = .live
    /// The output's luminance as a fraction of the content's: 0 is black, 1 is the visualization.
    public private(set) var luminanceFactor: Double = 1
    /// Clamped frame time since the last restore started (+∞ before the first).
    public private(set) var sinceRestoreStart: Double = .infinity

    public init() {}

    public var coverOpacity: Double { Self.coverOpacity(forLuminanceFactor: luminanceFactor) }
    public var isBlack: Bool { luminanceFactor <= 0 }
    /// The user wants the output black (the control offers Restore).
    public var isBlackoutRequested: Bool { phase == .blackedOut || phase == .restoreWaiting }
    /// Frames must be delivered (`advance`) for the fade or the restore spacing.
    public var needsFrames: Bool {
        phase == .restoreWaiting || phase == .fadingIn || sinceRestoreStart < Self.restoreSpacing
    }

    /// Black at once, from any phase (OUT-010-R2, R6).
    public mutating func blackOut() {
        phase = .blackedOut
        luminanceFactor = 0
    }

    /// Starts the fade, or waits black until the restore spacing has passed (OUT-010-R7). Never
    /// raises the luminance by itself; only `advance` does.
    public mutating func restore() {
        guard phase == .blackedOut else { return }
        if sinceRestoreStart >= Self.restoreSpacing {
            startFade()
        } else {
            phase = .restoreWaiting
        }
    }

    /// One presented frame of `frameTime` seconds.
    public mutating func advance(frameTime: Double, reduceFlashing: Bool) {
        let dt = frameTime.isFinite ? min(max(frameTime, 0), Self.maxFrameTime) : 0
        if sinceRestoreStart.isFinite { sinceRestoreStart += dt }
        switch phase {
        case .live, .blackedOut:
            break
        case .restoreWaiting:
            if sinceRestoreStart >= Self.restoreSpacing { startFade() }
        case .fadingIn:
            luminanceFactor = min(luminanceFactor + dt / Self.fadeDuration(reduceFlashing: reduceFlashing), 1)
            if luminanceFactor >= 1 { phase = .live }
        }
    }

    private mutating func startFade() {
        phase = .fadingIn
        luminanceFactor = 0
        sinceRestoreStart = 0
    }
}
