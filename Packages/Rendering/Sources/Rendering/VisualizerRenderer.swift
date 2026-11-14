// VisualizerRenderer.swift — the renderer contract (task T070; contracts/projectm-bridge.md).
//
// A renderer hosts the engine's output in a UIView, drains NormalizedPCMReader once per frame (up
// to the engine's maxSamplesPerFrame), and reports its frame rate for the FR-048 overlay. Backends:
// GLESRenderer (Apple OpenGL ES 3.0, Phase C Option A); ANGLERenderer if ADR-0003 selects it.
import AudioCore
import PresentationLifecycle
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
    /// Directories searched (recursively) for preset textures (feature 002 T215).
    func setTextureSearchPaths(_ paths: [URL])
    /// Stops the display link within one frame (FR-046, FR-050).
    func pause()
    func resume()
    /// Limit rapid full-screen brightness changes (FR-072).
    var reduceFlashing: Bool { get set }
    /// Whether `reduceFlashing` has any effect with this renderer (both current renderers: yes, T119;
    /// Settings says so when not, T116).
    var supportsReduceFlashing: Bool { get }
    /// Frame rate and frame time, for the FR-048 overlay.
    var metrics: RenderMetrics { get }
    /// Frames presented so far (SC-007 timing: the first frame after a preset switch).
    var presentedFrameCount: Int { get }
    /// Feature 002 SC-104: presets likely to be chosen next. A renderer may build their GPU
    /// pipelines in the background so the switch does not wait for shader compiles. Replaces any
    /// earlier request; does nothing by default.
    func prewarm(_ presets: [Preset])
    /// PERF-011: what this renderer stops and releases while the app cannot present frames
    /// (background, device lock), in registration order. The app registers them with its
    /// PresentationResourceRegistry. While suspended a renderer draws no frame and runs no frame
    /// loop, whatever `pause()`/`resume()` calls it receives; `setPreset` still loads. None by
    /// default.
    var presentationResources: [any PresentationBoundResource] { get }
    /// PRE-012: tries a preset the user imported on an engine that is not the visible one, before
    /// it may ever be loaded with `setPreset`. Nil when this renderer cannot run a second engine;
    /// imported presets then wait unchecked and are not playable.
    var presetTrial: (any PresetTrialing)? { get }
    /// PRE-001: draws presets off screen into small pictures for the browser's thumbnails. Nil when
    /// this renderer cannot run a second engine; rows then keep their placeholders.
    var presetThumbnails: (any PresetThumbnailDrawing)? { get }
    /// PERF-006: what this renderer frees on memory pressure (caches it rebuilds lazily, optional
    /// background work). The app registers them with its MemoryPressureRecovery. Never the visible
    /// engine or its surface. None by default.
    var memoryPressureResponders: [any MemoryPressureResponder] { get }
}

public extension VisualizerRenderer {
    func prewarm(_ presets: [Preset]) {}
    var presentationResources: [any PresentationBoundResource] { [] }
    var presetTrial: (any PresetTrialing)? { nil }
    var presetThumbnails: (any PresetThumbnailDrawing)? { nil }
    var memoryPressureResponders: [any MemoryPressureResponder] { [] }
}

/// How an off-screen trial of an untrusted preset ended (PRE-012-R16).
public enum PresetTrialOutcome: Sendable, Equatable {
    /// The engine loaded the preset and drew its frames.
    case passed
    /// The engine refused the preset; its message.
    case failed(String)
    /// The trial did not finish in time. Its work was abandoned and may still be running.
    case timedOut
    /// No trial could run now (the app cannot present frames, or an abandoned trial still runs).
    case unavailable(String)
}

/// Loads a preset's text on a separate engine and drawing context and draws it for a few frames
/// with audio input (PRE-012-R14, R15). The visible picture is never involved. `run` never throws
/// and returns within `timeout` (plus scheduling slack), whatever the preset does.
public protocol PresetTrialing: AnyObject, Sendable {
    func run(_ contents: Data, timeout: Duration) async -> PresetTrialOutcome
}

/// How an off-screen thumbnail drawing ended (PRE-001, contract thumbnail-cache.md C4).
public enum PresetThumbnailDrawResult: Sendable, Equatable {
    /// RGBA8 pixels, top row first, `width * height * 4` bytes.
    case pixels(Data)
    /// The engine refused the preset or could not draw it; its message.
    case failed(String)
    /// Nothing can be drawn now (the app cannot present frames, or an abandoned drawing still runs).
    case unavailable(String)
}

/// Draws a preset's text on a separate engine and drawing context for `frames.count` frames, feeding
/// one block of interleaved stereo audio before each, and returns the last frame's pixels (PRE-001).
/// The visible picture is never involved; `draw` returns within `timeout` (plus scheduling slack).
public protocol PresetThumbnailDrawing: AnyObject, Sendable {
    func draw(_ contents: Data, width: Int, height: Int, frames: [[Float]], timeout: Duration) async -> PresetThumbnailDrawResult
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
    /// The preset's contents when it does not live in a file (feature 002: pack presets come from
    /// the compressed archive, research R-30). When set, renderers load it instead of `fileURL`.
    public var data: Data?

    public init(id: String, name: String, fileURL: URL, packID: String = "", author: String = "",
                license: String = "", sourceURL: String = "", sourceVersion: String = "", data: Data? = nil) {
        self.id = id
        self.name = name
        self.fileURL = fileURL
        self.packID = packID
        self.author = author
        self.license = license
        self.sourceURL = sourceURL
        self.sourceVersion = sourceVersion
        self.data = data
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
