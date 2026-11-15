// VideoLayerSource.swift — a video as a CMP-001 layer (MED-002-R9 to R13, R19; research MED-002-D1
// to D5, D8; contracts/video-layer.md "Layer source").
//
// Setting `content` to a stored copy creates a `VideoDecodePipeline` (one decode thread, at most 3
// decoded pictures) and starts it at playback time 0. Per frame, `render`:
//   1. advances the `VideoPlaybackClock` by the frame context's presentation time (intended rate;
//      a gap over 1 s, e.g. a pause, adds nothing);
//   2. takes the latest queued picture due at that playback time (`take(upTo:)`, which never waits;
//      older due pictures are dropped as late) and keeps it as the held picture;
//   3. draws the held picture with its CMP-006 fit (fill by default) on the upright size and the
//      track's rotation (`VideoPictureGeometry`), transparent outside the picture,
//      sampling a `.bgra8Unorm_srgb` texture (linear light), alpha 1 (premultiplied = color).
// Until a picture is due, with no content, or after the session failed, `render` throws `.notReady`
// and the compositor shows the transparent fallback. It never decodes, waits or does I/O: the
// failure flag is read with a lock taken only if free this instant. `suspendDecoding()` (background)
// releases the decoder and pictures; `resumeDecoding()` restarts at the clock's playback time.
// MED-003: `loopRegion` (nil: the whole file) is passed to every start; changing it restarts decoding
// at the shown picture when that lies inside the new region, otherwise at in, keeping the clock (a
// held picture outside the new region is dropped at once). `resumeDecoding()` restarts at the shown
// picture. A wrap (the shown picture's file time going back) records its lateness, the joint's gap.
// MED-004: `playbackSpeed` scales the clock's steps (video time = presentation time × speed) and the
// pipeline's pre-roll lead; a change never stops, starts or seeks the decoder and keeps the held
// picture (the timeline is video time, so queued pictures stay valid; research MED-004-D4).
// MED-005 (reverse, research MED-005-D5): `reverse` on a file starts a background cache build
// (`VideoReverseDriver`); forward plays meanwhile. The first frame that finds the cache ready (try-lock) stops the
// forward decoder and shows cached pictures picked by `VideoReverseTimeline` from the same clock (speed, region),
// starting at the shown picture. Off, a failed build or new content restart the forward decoder at the shown picture;
// suspend drops the cache and resume rebuilds it.
// Not Sendable: the compositor's thread (the main thread in the app) sets `content`, renders and
// suspends; `onStateChange` is called on the main actor.
import CameraLayer
import Foundation
import ImageLayer

/// What the video layer plays.
public enum VideoLayerContent: Sendable, Equatable {
    case none
    /// A stored copy on the device (MED-002-R3).
    case file(URL)
}

/// The video layer's state (data-model "VideoLayerState").
public enum VideoLayerState: Sendable, Equatable {
    case empty
    case loading
    /// Playing; the upright picture size.
    case playing(width: Int, height: Int)
    case failed(VideoImportError)
}

#if canImport(AVFoundation) && canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import os

public final class VideoLayerSource: LayerSource, LayerFitting {
    public let layerName = "video"
    public let fallback = LayerFallback.transparent
    public let device: MTLDevice
    public let capacity: Int
    /// CMP-006: the stack entry's fit (set by the compositor; nil: fill at the centre). Shown from the
    /// next frame; decoding is not restarted.
    public var fit: LayerFit?
    private let slot = VideoStateSlot()
    private var pipeline: VideoDecodePipeline<AVVideoFrameReader>?
    private var clock = VideoPlaybackClock()
    private var held: TimedFrame<VideoTextureFrame>?
    private var suspended = false
    private var renderPipeline: MTLRenderPipelineState?
    private var sampler: MTLSamplerState?
    /// Frames that showed a video picture (diagnostics, tests).
    public private(set) var framesShown = 0
    /// The playback-timeline time of the picture shown last (nil when none).
    public private(set) var shownPresentationNanoseconds: Int64?
    /// The playback time of the last rendered frame.
    public var playbackNanoseconds: Int64 { clock.playbackNanoseconds }
    /// MED-003: the file time of the picture shown last (nil when none).
    public private(set) var shownMediaNanoseconds: Int64?
    /// MED-003: wraps seen on screen (the shown picture's file time went back).
    public private(set) var wraps = 0
    /// MED-003: the largest lateness of the first picture after a wrap (playback time minus its
    /// presentation time): the joint's gap; 0 when the next pass was ready in time.
    public private(set) var maxWrapLatenessNanoseconds: Int64 = 0
    /// MED-003: the first picture after a restart (region edit, resume) is not a wrap.
    private var restarted = false
    // MED-005: reverse playback.
    private let reverseSlot = VideoReverseStateSlot()
    private var reverseDriver: VideoReverseDriver?
    private var reverseCache: VideoReverseCache<MTLTexture>?
    /// Playback time and shown media time when the cache started playing.
    private var reverseBase: Int64 = 0
    private var reverseStart: Int64?
    /// The last reversed picture, shown until forward decoding delivers one after reverse ends.
    private var reverseHold: (texture: MTLTexture, rotation: CameraRotation)?
    /// MED-005: the cached picture shown last (nil when none).
    public private(set) var reverseShownIndex: Int?
    /// MED-005: the active cache's peak accounted bytes (0 before one played).
    public private(set) var reversePeakBytes = 0
    /// MED-005: limits and budget read when a build starts.
    public var reverseLimits: VideoReverseLimits = .standard
    public var reverseBudgetBytes: Int = AnimatedFrameBudget.current

    /// MED-005: play the file backwards from a cache (a supported clip; otherwise forward with the reason).
    public var reverse = false {
        didSet { if reverse != oldValue { restartReverse(resumeForward: true) } }
    }

    /// MED-005: the reverse state (takes the slot's lock; not for the render path).
    public var reverseState: VideoReverseState { reverseSlot.lock.withLockUnchecked { $0.state } }

    /// MED-005: called on the main actor after every reverse state change.
    public var onReverseStateChange: (@MainActor @Sendable (VideoReverseState) -> Void)? {
        get { reverseSlot.lock.withLockUnchecked { $0.handler } }
        set { reverseSlot.lock.withLockUnchecked { $0.handler = newValue } }
    }

    /// MED-005 tests: waits until the current build ended (true when there is none).
    @discardableResult
    public func waitUntilReverseBuilt(timeout: Double = 10) -> Bool { reverseDriver?.waitUntilFinished(timeout: timeout) ?? true }

    /// Drops any cache or build, resumes forward decoding at the shown picture when a cache was playing (and
    /// `resumeForward`), and starts a new build when reverse is on for a file.
    private func restartReverse(resumeForward: Bool) {
        reverseDriver?.cancel()
        reverseDriver = nil
        let wasPlaying: Bool = reverseCache != nil
        reverseCache = nil
        reverseShownIndex = nil
        if wasPlaying, resumeForward, let pipeline, !suspended {
            restarted = true
            pipeline.start(atNanoseconds: clock.playbackNanoseconds, region: loopRegion, mediaStartNanoseconds: shownMediaNanoseconds)
        }
        guard reverse, case .file(let url) = content else {
            _ = reverseSlot.begin(.off)
            return
        }
        let generation: UInt64 = reverseSlot.begin(.preparing)
        guard !suspended else { return }
        let slot = reverseSlot
        reverseDriver = VideoReverseDriver(url: url, device: device, limits: reverseLimits, budgetBytes: reverseBudgetBytes) {
            (state: VideoReverseState) -> Void in
            slot.report(state, generation: generation)
        }
    }

    /// MED-003: the opened video's duration (nil until it opened; takes the slot's lock).
    public var mediaDurationNanoseconds: Int64? { slot.lock.withLockUnchecked { $0.durationNanoseconds } }

    /// MED-003: the loop region (nil: the whole file). Applied from the next frame.
    public var loopRegion: VideoLoopRegion? {
        didSet {
            guard loopRegion != oldValue else { return }
            if let media = shownMediaNanoseconds, let duration = mediaDurationNanoseconds,
               !VideoLoopRegion.effective(loopRegion, duration: duration).contains(media) {
                held = nil
                shownPresentationNanoseconds = nil
                shownMediaNanoseconds = nil
            }
            if reverseCache != nil {   // MED-005: the reverse timeline restarts at the shown picture
                reverseBase = clock.playbackNanoseconds
                reverseStart = shownMediaNanoseconds
                return
            }
            guard let pipeline, !suspended else { return }
            restarted = true
            pipeline.start(atNanoseconds: clock.playbackNanoseconds, region: loopRegion, mediaStartNanoseconds: shownMediaNanoseconds)
        }
    }

    /// MED-004: the playback speed (1× by default). Applied from the next frame, without a restart.
    public var playbackSpeed: VideoPlaybackSpeed = .normal {
        didSet {
            guard playbackSpeed != oldValue else { return }
            clock.setSpeed(playbackSpeed)
            pipeline?.setSpeed(playbackSpeed)
        }
    }

    /// MED-004 diagnostics: presentation time counted and video time added since the last speed change.
    public var speedMeasurement: (presentation: Int64, playback: Int64) {
        (clock.presentationSinceSpeedChange, clock.playbackSinceSpeedChange)
    }

    /// Called on the main actor after every state change.
    public var onStateChange: (@MainActor @Sendable (VideoLayerState) -> Void)? {
        get { slot.lock.withLockUnchecked { $0.handler } }
        set { slot.lock.withLockUnchecked { $0.handler = newValue } }
    }

    public init(device: MTLDevice, capacity: Int = 3) {
        self.device = device
        self.capacity = capacity
    }

    deinit { pipeline?.stop() }

    /// The current state (under the slot's lock; not for the render path).
    public var state: VideoLayerState { slot.lock.withLockUnchecked { $0.state } }

    /// The decode queue's counters (diagnostics, tests; takes the session's lock).
    public var statistics: VideoPipelineStatistics { pipeline?.statistics ?? VideoPipelineStatistics() }

    /// Tests: waits until the decode queue is full or the session ended.
    @discardableResult
    public func waitUntilBuffered(timeout: Double = 5) -> Bool { pipeline?.waitUntilIdle(timeout: timeout) ?? true }

    /// The content played. Setting it drops the current picture at once (the next frame is
    /// transparent), stops the old decoder and, for a file, starts playback at 0.
    public var content: VideoLayerContent = .none {
        didSet {
            guard content != oldValue else { return }
            pipeline?.stop()
            pipeline = nil
            held = nil
            reverseCache = nil   // MED-005: rebuilt below for the new file
            reverseHold = nil
            shownPresentationNanoseconds = nil
            shownMediaNanoseconds = nil
            clock.reset()
            let generation: UInt64 = slot.lock.withLockUnchecked { s in
                s.generation &+= 1
                s.durationNanoseconds = nil
                s.state = content == .none ? .empty : .loading
                s.failed = false
                return s.generation
            }
            slot.notify()
            defer { restartReverse(resumeForward: false) }   // MED-005
            guard case .file(let url) = content else { return }
            let slot = self.slot, device = self.device
            pipeline = VideoDecodePipeline<AVVideoFrameReader>(capacity: capacity, onEvent: { (event: VideoPipelineEvent) in
                slot.report(event, generation: generation)
            }, makeReader: { () -> AVVideoFrameReader in
                AVVideoFrameReader(url: url, device: device)
            })
            pipeline?.setSpeed(playbackSpeed)   // MED-004: the new session's pre-roll lead
            if !suspended { pipeline?.start(atNanoseconds: 0, region: loopRegion, mediaStartNanoseconds: nil) }
        }
    }

    /// Background or scene loss (R13): stops decoding and releases every picture. Playback resumes
    /// at the same playback time on `resumeDecoding()`.
    public func suspendDecoding() {
        guard !suspended else { return }
        suspended = true
        pipeline?.stop()
        held = nil
        reverseHold = nil
        clock.forgetPresentation()
        restartReverse(resumeForward: false)   // MED-005-R9: the cache is released; resume rebuilds it
    }

    /// Restarts decoding at the playback time it stopped at.
    public func resumeDecoding() {
        guard suspended else { return }
        suspended = false
        clock.forgetPresentation()
        restarted = true
        pipeline?.start(atNanoseconds: clock.playbackNanoseconds, region: loopRegion, mediaStartNanoseconds: shownMediaNanoseconds)
        if reverse { restartReverse(resumeForward: false) }   // MED-005-R9
    }

    public func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {
        if renderPipeline != nil { return }   // a size change keeps playback (spec edge cases)
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            guard let vertex = library.makeFunction(name: "vid_fullscreen"),
                  let fragment = library.makeFunction(name: "vid_picture") else {
                throw LayerSourceError.resourceUnavailable("video shader functions")
            }
            let d = MTLRenderPipelineDescriptor()
            d.label = "MED-002 video"
            d.vertexFunction = vertex
            d.fragmentFunction = fragment
            d.colorAttachments[0].pixelFormat = LayerPictureDescriptor.metalPixelFormat
            renderPipeline = try device.makeRenderPipelineState(descriptor: d)
        } catch let error as LayerSourceError {
            throw error
        } catch {
            throw .resourceUnavailable("video pipeline: \(error)")
        }
        let s = MTLSamplerDescriptor()
        s.minFilter = .linear
        s.magFilter = .linear
        s.sAddressMode = .clampToEdge
        s.tAddressMode = .clampToEdge
        guard let state = device.makeSamplerState(descriptor: s) else {
            renderPipeline = nil
            throw .resourceUnavailable("video sampler")
        }
        sampler = state
    }

    public func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                       audio: LayerAudioContext) throws(LayerSourceError) {
        guard let pipeline, !suspended else { throw .notReady }
        if slot.lock.withLockIfAvailableUnchecked({ $0.failed }) == true {
            held = nil
            shownPresentationNanoseconds = nil
            shownMediaNanoseconds = nil
            throw .notReady
        }
        let playback = clock.advance(to: frame.presentationTimeNanoseconds)
        if reverseCache == nil, let driver = reverseDriver, let cache = driver.readyCache() {   // MED-005: try-lock only
            pipeline.stop()
            held = nil
            reverseCache = cache
            reverseBase = playback
            reverseStart = shownMediaNanoseconds
            reversePeakBytes = cache.peakBytes
        }
        if let cache = reverseCache {
            let index: Int = cache.timeline.index(elapsedNanoseconds: playback - reverseBase, region: loopRegion,
                                                  startMediaNanoseconds: reverseStart)
            let texture: MTLTexture = cache.pictures[index]
            try draw(texture, rotation: cache.info.rotation, into: picture, commandBuffer: commandBuffer)
            reverseHold = (texture, cache.info.rotation)
            reverseShownIndex = index
            shownPresentationNanoseconds = playback
            shownMediaNanoseconds = cache.timeline.mediaNanoseconds[index]
            return
        }
        if let newest = pipeline.take(upTo: playback) {
            if restarted {
                restarted = false
            } else if let previous = held, newest.mediaNanoseconds < previous.mediaNanoseconds,
               newest.presentationNanoseconds > previous.presentationNanoseconds {
                wraps += 1
                let lateness: Int64 = playback - newest.presentationNanoseconds
                maxWrapLatenessNanoseconds = max(maxWrapLatenessNanoseconds, lateness)
            }
            held = newest
            reverseHold = nil
        }
        guard let shown = held else {
            if let hold = reverseHold { try draw(hold.texture, rotation: hold.rotation, into: picture, commandBuffer: commandBuffer); return }
            throw .notReady
        }
        try draw(shown.frame.texture, rotation: shown.frame.rotation, into: picture, commandBuffer: commandBuffer)
        shownPresentationNanoseconds = shown.presentationNanoseconds
        shownMediaNanoseconds = shown.mediaNanoseconds
    }

    /// Draws `texture` with the fit and rotation (both directions) and counts the frame.
    private func draw(_ texture: MTLTexture, rotation: CameraRotation, into picture: MTLTexture,
                      commandBuffer: MTLCommandBuffer) throws(LayerSourceError) {
        guard let renderPipeline, let sampler else { throw .notReady }
        let geometry = VideoPictureGeometry(pictureWidth: texture.width, pictureHeight: texture.height, rotation: rotation,
                                            outputWidth: picture.width, outputHeight: picture.height, fit: fit ?? .default)
        var uniforms = VideoUniforms(geometry: geometry, outputWidth: picture.width, outputHeight: picture.height)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = picture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { throw .frameSkipped }
        encoder.label = "MED-002 video"
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<VideoUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        framesShown += 1
    }

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VidOut { float4 position [[position]]; };

    vertex VidOut vid_fullscreen(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        VidOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return o;
    }

    struct VidUniforms {
        float2 visible;
        float2 offset;
        float2 outputSize;
        uint rotation;   // quarter turns clockwise to upright
        uint pad;
    };

    // Output point (0...1, top-left) -> visible part of the upright picture -> video texture
    // (VideoPictureGeometry.textureCoordinate does the same). The texture is sRGB, so the sample
    // is linear light; the video is opaque, so alpha 1 makes it premultiplied. Outside the upright
    // picture (CMP-006 fit and pixelAccurate bars) nothing is drawn.
    fragment float4 vid_picture(VidOut in [[stage_in]], texture2d<float> video [[texture(0)]],
                                sampler s [[sampler(0)]], constant VidUniforms &u [[buffer(0)]]) {
        float2 p = in.position.xy / u.outputSize;
        float2 ab = u.offset + p * u.visible;
        if (any(ab < 0.0) || any(ab > 1.0)) { return float4(0.0); }
        float2 t = ab;
        if (u.rotation == 1u) { t = float2(ab.y, 1.0 - ab.x); }
        else if (u.rotation == 2u) { t = float2(1.0 - ab.x, 1.0 - ab.y); }
        else if (u.rotation == 3u) { t = float2(1.0 - ab.y, ab.x); }
        float3 c = video.sample(s, t).rgb;
        return float4(max(c, float3(0.0)), 1.0);
    }
    """
}

/// The layer's state, shared between the decode thread's events and the compositor's thread.
final class VideoStateSlot: Sendable {
    struct State {
        var generation: UInt64 = 0
        var state: VideoLayerState = .empty
        /// Read by `render` (try-lock): the session failed, show the fallback.
        var failed = false
        /// MED-003: the opened video's duration.
        var durationNanoseconds: Int64?
        var handler: (@MainActor @Sendable (VideoLayerState) -> Void)?
    }
    let lock = OSAllocatedUnfairLock(uncheckedState: State())

    /// A decode-thread event of content `generation` (stale generations are ignored).
    func report(_ event: VideoPipelineEvent, generation: UInt64) {
        let changed: Bool = lock.withLockUnchecked { s in
            guard s.generation == generation else { return false }
            let new: VideoLayerState
            switch event {
            case .opened(let info):
                new = .playing(width: info.uprightWidth, height: info.uprightHeight)
                s.durationNanoseconds = info.durationNanoseconds
            case .failed(let error):
                new = .failed(error)
                s.failed = true
            }
            guard new != s.state else { return false }
            s.state = new
            return true
        }
        if changed { notify() }
    }

    /// Hands the state to the handler on the main actor, read when it is delivered.
    func notify() {
        guard lock.withLockUnchecked({ $0.handler != nil }) else { return }
        Task { @MainActor [self] in
            let (state, handler) = lock.withLockUnchecked { ($0.state, $0.handler) }
            handler?(state)
        }
    }
}

/// Matches `VidUniforms` in the shader (32 bytes).
struct VideoUniforms {
    var visible: SIMD2<Float>
    var offset: SIMD2<Float>
    var outputSize: SIMD2<Float>
    var rotation: UInt32
    var pad: UInt32 = 0

    init(geometry: VideoPictureGeometry, outputWidth: Int, outputHeight: Int) {
        visible = SIMD2(geometry.visibleWidth, geometry.visibleHeight)
        offset = SIMD2(geometry.offsetX, geometry.offsetY)
        outputSize = SIMD2(Float(max(outputWidth, 1)), Float(max(outputHeight, 1)))
        rotation = UInt32(geometry.rotation.rawValue / 90)
    }
}
#endif
