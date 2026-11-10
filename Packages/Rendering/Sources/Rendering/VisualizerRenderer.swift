// VisualizerRenderer.swift — the renderer contract (task T070; contracts/projectm-bridge.md).
//
// A renderer hosts the engine's output in a UIView, drains NormalizedPCMReader once per frame (up
// to the engine's maxSamplesPerFrame), and reports its frame rate for the FR-048 overlay. Backends:
// GLESRenderer (Apple OpenGL ES 3.0, Phase C Option A); ANGLERenderer if ADR-0003 selects it.
import AudioCore
import UIKit

/// The blend into a newly selected preset (T091: at most 2 s).
public let presetBlendSeconds: Double = 2

@MainActor
public protocol VisualizerRenderer: AnyObject {
    /// Hosted by SwiftUI through UIViewRepresentable.
    var view: UIView { get }
    /// The audio source; read once per frame. A renderer with no reader renders without new audio.
    func attach(pcm: any NormalizedPCMReader)
    /// Loads a preset within 1 s (SC-007). On failure throws, and the previous preset keeps running
    /// (FR-045).
    func setPreset(_ preset: Preset) async throws
    /// Stops the display link within one frame (FR-046, FR-050).
    func pause()
    func resume()
    /// Limit rapid full-screen brightness changes (FR-072).
    var reduceFlashing: Bool { get set }
    /// Frame rate and frame time, for the FR-048 overlay.
    var metrics: RenderMetrics { get }
}

/// A preset the renderer can load (data-model.md §Preset). PresetRepository (T074) builds these from
/// the bundled presets joined with LICENSES.md.
public struct Preset: Sendable, Hashable, Identifiable {
    /// Stable: the relative bundle path.
    public var id: String
    /// Display name, from the file name.
    public var name: String
    public var fileURL: URL
    public var packID: String
    public var author: String
    public var license: String
    public var sourceURL: String
    public var sourceVersion: String

    public init(id: String, name: String, fileURL: URL, packID: String = "", author: String = "",
                license: String = "", sourceURL: String = "", sourceVersion: String = "") {
        self.id = id
        self.name = name
        self.fileURL = fileURL
        self.packID = packID
        self.author = author
        self.license = license
        self.sourceURL = sourceURL
        self.sourceVersion = sourceVersion
    }
}

/// Frame statistics over the last completed 1-second window (FR-048).
public struct RenderMetrics: Sendable, Equatable {
    public var framesPerSecond: Double
    public var meanFrameTimeMs: Double
    public var maxFrameTimeMs: Double

    public static let zero = RenderMetrics(framesPerSecond: 0, meanFrameTimeMs: 0, maxFrameTimeMs: 0)

    public init(framesPerSecond: Double, meanFrameTimeMs: Double, maxFrameTimeMs: Double) {
        self.framesPerSecond = framesPerSecond
        self.meanFrameTimeMs = meanFrameTimeMs
        self.maxFrameTimeMs = maxFrameTimeMs
    }
}

/// Computes RenderMetrics from frame presentation timestamps, in 1-second windows (contract: "fps
/// from presentation timestamps in 1 s windows"). A pause longer than the window starts a new one,
/// so paused time never counts as slow frames.
public struct FrameRateMeter: Sendable {
    public static let window: Double = 1.0
    /// A gap longer than this between two frames is a pause, not a frame time.
    public static let pauseGap: Double = 0.5

    private var windowStart: Double?
    private var last: Double?
    private var frames = 0
    private var frameTimeSum: Double = 0
    private var frameTimeMax: Double = 0

    public private(set) var metrics = RenderMetrics.zero

    public init() {}

    /// Records a frame presented at `timestamp` (seconds). Returns true when a window completed and
    /// `metrics` changed.
    @discardableResult
    public mutating func record(presentedAt timestamp: Double) -> Bool {
        guard let start = windowStart, let previous = last, timestamp - previous <= FrameRateMeter.pauseGap else {
            restart(at: timestamp)
            return false
        }
        let frameTime = timestamp - previous
        frames += 1
        frameTimeSum += frameTime
        frameTimeMax = max(frameTimeMax, frameTime)
        last = timestamp
        let elapsed = timestamp - start
        guard elapsed >= FrameRateMeter.window else { return false }
        metrics = RenderMetrics(framesPerSecond: Double(frames) / elapsed,
                                meanFrameTimeMs: frameTimeSum / Double(frames) * 1000,
                                maxFrameTimeMs: frameTimeMax * 1000)
        restart(at: timestamp)
        return true
    }

    /// Forgets the current window (after a pause).
    public mutating func reset() {
        windowStart = nil
        last = nil
        frames = 0
        frameTimeSum = 0
        frameTimeMax = 0
    }

    private mutating func restart(at timestamp: Double) {
        windowStart = timestamp
        last = timestamp
        frames = 0
        frameTimeSum = 0
        frameTimeMax = 0
    }
}
