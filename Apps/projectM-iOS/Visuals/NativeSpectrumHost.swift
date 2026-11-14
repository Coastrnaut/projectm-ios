// NativeSpectrumHost.swift — the native spectra on screen: the circular spectrum (VIS-001-R12 to R16,
// R18; research VIS-001-D8; ADR-0009) and the linear spectrum (VIS-002-R10 to R13; research
// VIS-002-D5). Formerly CircularSpectrumHost.swift.
//
// * One host, one frame loop, one analyzer and one glow chain for both visuals: the generator is
//   `any SpectrumTextureGenerator`. `apply(style:)` swaps the generator when the kind changes (the
//   new one's pipeline is built here on the main thread, outside the frame callback; a failure
//   throws and the caller falls back to projectM) and only updates the configuration when the
//   linear spectrum's orientation or spacing changes. The bar count carries over.
//
// * A `CAMetalLayer` view (`bgra8Unorm_srgb`, opaque). Its drawable size follows the view's bounds
//   × display scale × QualityGovernor's render scale at every layout, so rotation and iPad sizes need
//   nothing else: the generator lays out for whatever size it gets (VIS-001-R5).
// * A `CADisplayLink` on the main run loop at QualityGovernor's frame-rate range (FR-049, as
//   ANGLERenderer). Each frame takes the newest band vector from `LiveBandAnalyzer` without waiting,
//   encodes it with the generator into the next drawable and presents it.
// * `LiveBandAnalyzer` pulls the capture manager's analysis tap on its own queue (VIS-001-R14); it
//   runs only while the frame loop runs.
// * pause()/resume() (FR-046; also used while projectM is shown) and PERF-011 suspension are
//   independent, like ANGLERenderer: the loop runs only when neither applies. Suspension stops the
//   display link and the analyzer before it returns and drops nothing else; resuming restarts the
//   Reduce-flashing limiter from the next frame (no ramp from a stale picture).
// * Glow (FX-001, ADR-0010): a `BloomEffect` in an `EffectChain` built with the host. While the glow
//   is pass-through (off or intensity 0) the generator draws straight into the drawable, exactly as
//   VIS-001; otherwise it draws into the chain's image and the bloom composites into the drawable.
//   The generator's `downstreamLuminance` is the bloom's luminance model, so Reduce flashing bounds
//   the composited frame (FX-001-R10). If the bloom cannot be built (or its textures cannot be
//   created later) the visual keeps rendering without it and `glowUnavailable` is set (FX-001-R13).
//   The view's accessibility value names the glow state.
// * Per frame, this file's code allocates nothing: the band scratch is preallocated; the chain's
//   textures are created only when the drawable size changes; Metal's command buffer and drawable
//   are the system's.
// * Audio feature bindings (MOD-002; research MOD-002-D6, D8): the host owns an
//   `AudioFeatureModulator` over the visual catalog. With no binding nothing below changes. With a
//   binding, each frame advances it with the frame's bands and display time and resolves the
//   effective glow from the manual `glow` (which modulation never writes): the bloom gets the
//   effective intensity (an intensity-only change updates its uniforms, no plan rebuild) and the
//   generator's downstream luminance is a `ModulatedGlowLuminance` reference whose model follows
//   the effective glow, so Reduce flashing (FX-019) bounds the frame actually shown. No allocation
//   per frame. Unbinding returns to the manual glow at once.
// * Oscilloscope (VIS-003; research VIS-003-D1): the host hands the analyzer a `WaveformTap` around
//   the analysis tap (a pass-through: the analyzer's bands are unchanged) that also keeps the newest
//   4,096 mono samples. While the oscilloscope is shown, each frame copies the newest history into a
//   preallocated scratch and passes it to the generator instead of the bands; modulation still advances
//   with the bands. The oscilloscope's line and window change only its configuration.
// * REC-001 (research REC-001-D1): `captureFrame` turns the layer's `framebufferOnly` off until the
//   next readable drawable is drawn, blits that drawable (the frame as shown: glow and Reduce
//   flashing included) into a shared buffer and delivers 8-bit sRGB BGRA on the main actor; then
//   `framebufferOnly` returns to true. Stopping the loop cancels a pending capture.
// * Spectral smoothing (ANL-003-R2, R3, R5; research ANL-003-D1): each frame the newest raw bands
//   go through a `BandSmoother` (attack/release from `smoothing`, the real interval between display
//   link timestamps, the bus frame's session as its generation) and the spectra draw the result;
//   MOD-002 modulation keeps the raw bands. Instant (the default) is a bit-exact copy. Starting the
//   loop and changing the bar count reset it, so nothing ramps from a stale picture. Preallocated;
//   nothing allocates per frame.
import AnalysisFeatures
import AudioCore
import FrameCapture
import Metal
import ParameterGraph
import PerformanceControlAnalysis
import PresentationLifecycle
import QuartzCore
import Rendering
import UIKit
import VisualBandFeed
import VisualEffects
import VisualGenerators
import VisualParameters

@MainActor
final class NativeSpectrumHost: PresentationBoundResource {
    let view: NativeSpectrumLayerView
    private var generator: any SpectrumTextureGenerator
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    /// Which native spectrum is drawn (VIS-002-D5).
    private(set) var style: NativeSpectrumStyle
    private let analyzer: LiveBandAnalyzer
    private let reader: (any NormalizedPCMReader)?
    /// VIS-003: the analyzer reads through this tap; it keeps the newest samples for the oscilloscope.
    private let waveform: WaveformTap?
    private let bands: UnsafeMutablePointer<Float>
    /// VIS-003: the newest sample history (zeros until the first one arrives).
    private let samples: UnsafeMutablePointer<Float>
    private var bandCount = 0
    /// ANL-003: the smoother, the newest frame's session and the previous display-link timestamp.
    private let smoother = BandSmoother()
    private var bandSession: UInt64 = 0
    /// ANL-007: the newest frame's kick envelope, fed to the bindings (MOD-002's Kick source).
    private var kickEnvelope: Float = 0
    /// ANL-010: the newest frame's normalized spectral centroid, fed to the bindings (MOD-002's
    /// Centroid source).
    private var centroid: Float = 0
    private var lastLinkTimestamp: CFTimeInterval?
    private var displayLink: CADisplayLink?
    private var paused = true
    private(set) var isSuspended = false
    private var meter = FrameRateMeter()
    private var quality = QualityGovernor.current()
    private var observers: [NSObjectProtocol] = []

    /// Frame rate and frame time for the FR-048 overlay.
    private(set) var metrics = RenderMetrics.zero
    private(set) var presentedFrameCount = 0
    /// FR-072: the app's Reduce flashing setting.
    var reduceFlashing = false

    /// FX-001: the bloom and the chain that runs it; nil when the glow is unavailable.
    private let bloom: BloomEffect?
    private var chain: EffectChain?
    /// The glow could not be built on this device (FX-001-R13); the visual renders without it.
    private(set) var glowUnavailable: Bool

    /// The glow settings; applied from the next frame (no shader rebuild, FX-001-R12).
    var glow = BloomParameters() {
        didSet { applyGlow() }
    }

    /// The bloom runs (available and the effective glow not pass-through).
    var glowActive: Bool { chain != nil && !effectiveGlow.isPassThrough }

    /// MOD-002: the glow actually rendered, `glow` with any bound intensity applied.
    private(set) var effectiveGlow = BloomParameters()
    /// MOD-002: audio feature bindings over the visual catalog (nil only if the catalog failed to
    /// validate, which `VisualParameterCatalogTests` rules out in CI).
    private let modulator: AudioFeatureModulator? = (try? VisualParameterCatalog.makeRegistry()).map(AudioFeatureModulator.init(registry:))
    /// MOD-002: the luminance model the generator sees while the glow intensity is bound.
    private let glowLuminance = ModulatedGlowLuminance()
    /// REC-001: the handler waiting for the next readable frame.
    private var pendingCapture: (@MainActor (CapturedPixels?) -> Void)?
    /// REC-003: the attached video recording; the drawables stay readable while it is set.
    var videoRecording: VideoRecordingTap? {
        didSet { view.metalLayer.framebufferOnly = videoRecording == nil && pendingCapture == nil }
    }
    /// REC-003: the device the recording's pixel buffers are made for.
    var recordingDevice: MTLDevice { device }

    /// ANL-003: attack and release of the drawn bands (Instant by default); from the next frame.
    var smoothing: SmoothingTimes {
        get { smoother.times }
        set { smoother.times = newValue }
    }

    var barCount: SpectrumBarCount {
        get { generator.barCount }
        set {
            guard newValue != generator.barCount else { return }
            generator.barCount = newValue
            analyzer.setBarCount(newValue)
            bandCount = 0   // the old vector does not match the new bars
            smoother.reset()   // ANL-003-R5
        }
    }

    /// Throws `VisualGeneratorError` when there is no Metal device or the pipeline cannot be built
    /// (VIS-001-R16); the caller falls back to projectM.
    /// A glow that cannot be built does not throw: the host renders without it (FX-001-R13).
    /// `forceGlowFailure` simulates that failure (DEBUG UI tests).
    static func make(device: MTLDevice?, reader: (any NormalizedPCMReader)?, style: NativeSpectrumStyle = .circular,
                     barCount: SpectrumBarCount, glow: BloomParameters = BloomParameters(),
                     forceGlowFailure: Bool = false) throws -> NativeSpectrumHost {
        guard let device, let queue = device.makeCommandQueue() else { throw VisualGeneratorError.noDevice }
        let generator = try makeGenerator(device: device, style: style, barCount: barCount)
        let analyzer = try LiveBandAnalyzer(barCount: barCount)
        var bloom: BloomEffect?
        var chain: EffectChain?
        if !forceGlowFailure {
            do {
                let effect = try BloomEffect(device: device, pixelFormat: .bgra8Unorm_srgb, parameters: glow)
                chain = try EffectChain(device: device, pixelFormat: .bgra8Unorm_srgb, effects: [effect])
                bloom = effect
            } catch {
                bloom = nil
                chain = nil
            }
        }
        let host = NativeSpectrumHost(device: device, queue: queue, style: style, generator: generator, analyzer: analyzer,
                                      reader: reader, bloom: bloom, chain: chain)
        host.glow = glow
        return host
    }

    /// The generator of `style` (pipeline built here).
    private static func makeGenerator(device: MTLDevice, style: NativeSpectrumStyle,
                                      barCount: SpectrumBarCount) throws -> any SpectrumTextureGenerator {
        switch style {
        case .circular:
            return try CircularSpectrumGenerator(device: device, pixelFormat: .bgra8Unorm_srgb,
                                                 configuration: CircularSpectrumConfiguration(barCount: barCount))
        case let .linear(orientation, spacing):
            return try LinearSpectrumGenerator(device: device, pixelFormat: .bgra8Unorm_srgb,
                                               configuration: LinearSpectrumConfiguration(barCount: barCount, orientation: orientation,
                                                                                          spacing: spacing))
        case let .oscilloscope(line, window):
            let generator = try OscilloscopeGenerator(device: device, pixelFormat: .bgra8Unorm_srgb,
                                                      configuration: oscilloscopeConfiguration(line: line, windowMilliseconds: window))
            generator.barCount = barCount
            return generator
        }
    }

    /// VIS-003: the oscilloscope's configuration for the app's choices.
    private static func oscilloscopeConfiguration(line: OscilloscopeLine, windowMilliseconds: Int) -> OscilloscopeConfiguration {
        OscilloscopeConfiguration(windowMilliseconds: Double(windowMilliseconds), lineThickness: line.thickness)
    }

    private init(device: MTLDevice, queue: MTLCommandQueue, style: NativeSpectrumStyle, generator: any SpectrumTextureGenerator,
                 analyzer: LiveBandAnalyzer, reader: (any NormalizedPCMReader)?, bloom: BloomEffect?, chain: EffectChain?) {
        self.device = device
        self.queue = queue
        self.style = style
        self.generator = generator
        self.analyzer = analyzer
        self.reader = reader
        waveform = reader.map { (r: any NormalizedPCMReader) -> WaveformTap in WaveformTap(r) }
        self.bloom = bloom
        self.chain = chain
        glowUnavailable = chain == nil
        bands = .allocate(capacity: SpectrumBarCount.maximum)
        bands.initialize(repeating: 0, count: SpectrumBarCount.maximum)
        samples = .allocate(capacity: WaveformFrameBuffer.capacity)
        samples.initialize(repeating: 0, count: WaveformFrameBuffer.capacity)
        view = NativeSpectrumLayerView(device: device)
        view.onLayout = { [weak self] in self?.layoutDrawable() }
        observeFrameRatePressure()
        applyGlow()
    }

    /// Switches the drawn spectrum (VIS-002-D5). Another kind builds its generator (throws
    /// `VisualGeneratorError` when its pipeline fails; the current one keeps drawing); the linear
    /// spectrum's orientation and spacing only change its configuration. The envelope's history
    /// starts over with a new generator (a new visual, FX-019-R11).
    func apply(style newStyle: NativeSpectrumStyle) throws {
        guard newStyle != style else { return }
        if case let .linear(orientation, spacing) = newStyle, let linear = generator as? LinearSpectrumGenerator {
            var configuration = linear.configuration
            configuration.orientation = orientation
            configuration.spacing = spacing
            linear.configuration = configuration
        } else if case let .oscilloscope(line, window) = newStyle, let scope = generator as? OscilloscopeGenerator {
            var configuration = scope.configuration
            let wanted = Self.oscilloscopeConfiguration(line: line, windowMilliseconds: window)
            configuration.lineThickness = wanted.lineThickness
            configuration.windowMilliseconds = wanted.windowMilliseconds
            scope.configuration = configuration
        } else {
            let replacement = try Self.makeGenerator(device: device, style: newStyle, barCount: generator.barCount)
            generator = replacement
        }
        style = newStyle
        applyGlow()
    }

    private func applyGlow() {
        resolveEffectiveGlow()
        view.accessibilityLabel = "\(style.title) visualization"
        view.accessibilityIdentifier = style.accessibilityIdentifier
        view.accessibilityValue = Self.accessibilityValue(style: style, glowEnabled: glow.enabled, glowUnavailable: glowUnavailable)
    }

    // MARK: - Audio feature bindings (MOD-002)

    private var glowIntensityIsBound: Bool { modulator?.isBound(VisualParameterIDs.bloomIntensity) ?? false }

    /// Applies `glow` with any bound intensity to the bloom and the luminance model. Unbound, this is
    /// exactly the FX-001 path.
    private func resolveEffectiveGlow() {
        var resolved = glow
        if let modulator, glowIntensityIsBound {
            resolved.intensity = Float(modulator.value(for: VisualParameterIDs.bloomIntensity, manual: Double(glow.intensity)))
        }
        effectiveGlow = resolved
        bloom?.parameters = resolved
        if glowIntensityIsBound {
            glowLuminance.model = BloomLuminanceModel(parameters: resolved)
            generator.downstreamLuminance = glowActive ? glowLuminance : nil   // a class reference: no allocation
        } else {
            generator.downstreamLuminance = glowActive ? BloomLuminanceModel(parameters: resolved) : nil
        }
    }

    /// Binds an audio feature to a catalog parameter (validated, MOD-002 contract C2); effective
    /// from the next frame.
    func bind(_ binding: AudioFeatureBinding) throws(AudioFeatureBindingError) {
        guard let modulator else { throw .unknownTarget(binding.target) }
        try modulator.bind(binding)
        resolveEffectiveGlow()
    }

    /// The live bindings in order (SCN-002 captures them into the current scene).
    var bindings: [AudioFeatureBinding] { modulator?.bindings ?? [] }

    /// Removes a binding; the parameter returns to its manual value at once.
    @discardableResult
    func unbind(_ target: ParameterID) -> Bool {
        let removed = modulator?.unbind(target) ?? false
        resolveEffectiveGlow()
        return removed
    }

    /// Advances the bindings with one frame's bands at the frame's display time and applies the
    /// result. Does nothing without bindings. Called by `frame(_:)`; tests call it directly.
    func applyModulation(bands: UnsafeBufferPointer<Float>, kick: Float? = nil, centroid: Float? = nil,
                         timeNanoseconds: UInt64) {
        guard let modulator, modulator.hasBindings else { return }
        modulator.advance(frame: AudioFeatureFrame(bands: bands, kick: kick, centroid: centroid), timeNanoseconds: timeNanoseconds)
        resolveEffectiveGlow()
    }

    /// "bound, manual 0.50, effective 0.73" (MOD-002-R12; the Debug readout and tests).
    var glowModulationReadout: String {
        let state = glowIntensityIsBound ? "bound" : "unbound"
        return "\(state), manual \(String(format: "%.2f", Double(glow.intensity))), effective \(String(format: "%.2f", Double(effectiveGlow.intensity)))"
    }

    /// The bloom's current parameters (nil without a bloom).
    var bloomParameters: BloomParameters? { bloom?.parameters }

    /// The luminance model Reduce flashing applies to the generator's output.
    var downstreamLuminance: (any FrameLuminanceTransfer)? { generator.downstreamLuminance }

    /// The accessibility value naming the glow state.
    static func glowDescription(enabled: Bool, unavailable: Bool) -> String {
        guard enabled else { return "Glow off" }
        return unavailable ? "Glow unavailable" : "Glow on"
    }

    /// The visual's accessibility value: the glow state, preceded by the orientation for the linear
    /// spectrum ("Vertical, Glow off"; VIS-002-R13) and the window for the oscilloscope ("20 ms, Glow
    /// off"; VIS-003-R13).
    static func accessibilityValue(style: NativeSpectrumStyle, glowEnabled: Bool, glowUnavailable: Bool) -> String {
        let glow = glowDescription(enabled: glowEnabled, unavailable: glowUnavailable)
        switch style {
        case .circular: return glow
        case let .linear(orientation, _): return "\(orientation.title), \(glow)"
        case let .oscilloscope(_, window): return "\(window) ms, \(glow)"
        }
    }

    /// The chain's textures could not be created: continue without the glow (FX-001-R13).
    private func dropGlow() {
        chain = nil
        glowUnavailable = true
        applyGlow()
    }

    isolated deinit {
        displayLink?.invalidate()
        analyzer.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        bands.deinitialize(count: SpectrumBarCount.maximum)
        bands.deallocate()
        samples.deinitialize(count: WaveformFrameBuffer.capacity)
        samples.deallocate()
    }

    /// SHOW-011 (research SHOW-011-D3): while this visual is shown its analyzer is the analysis tap's
    /// only reader, so the tap tempo reads this subscription on its pipeline.
    private(set) lazy var tempoReader: TempoSubscriptionReader? = (try? analyzer.subscribe()).map {
        TempoSubscriptionReader(subscription: $0, sampleRate: analyzer.sampleRate)
    }

    /// True while the frame loop runs (resumed and not suspended).
    var isRunning: Bool { displayLink != nil }

    // MARK: - Pause (FR-046) and presentation (PERF-011)

    func pause() {
        paused = true
        updateLoop()
    }

    func resume() {
        paused = false
        updateLoop()
    }

    var presentationResources: [any PresentationBoundResource] { [self] }
    var presentationResourceName: String { "Native spectrum frame loop and analysis" }

    func suspendForPresentationLoss() {
        guard !isSuspended else { return }
        isSuspended = true
        updateLoop()
    }

    func resumeForPresentation() {
        guard isSuspended else { return }
        isSuspended = false
        layoutDrawable()
        updateLoop()
    }

    private func updateLoop() {
        let run = !paused && !isSuspended
        if run, displayLink == nil {
            generator.restartLoop()
            smoother.reset()   // ANL-003-R5: no ramp from the picture before the pause
            lastLinkTimestamp = nil
            kickEnvelope = 0   // ANL-007: no kick carried over a pause
            centroid = 0       // ANL-010: the analysis session restarts, so its centroid does too
            if let waveform { analyzer.start(reader: waveform) }   // VIS-003: the tap through the pass-through wrapper
            let link = CADisplayLink(target: NativeSpectrumLinkProxy(self), selector: #selector(NativeSpectrumLinkProxy.fire(_:)))
            link.preferredFrameRateRange = quality.frameRateRange
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else if !run, let link = displayLink {
            link.invalidate()
            displayLink = nil
            analyzer.stop()
            meter.reset()
            cancelCapture()   // REC-001-R14: no frame comes while the loop is stopped
        }
    }

    // MARK: - Frame capture (REC-001)

    func captureFrame(_ handler: @escaping @MainActor (CapturedPixels?) -> Void) {
        pendingCapture?(nil)
        pendingCapture = handler
        view.metalLayer.framebufferOnly = false   // the next drawables can be read
    }

    func cancelCapture() {
        let handler = pendingCapture
        pendingCapture = nil
        view.metalLayer.framebufferOnly = videoRecording == nil   // REC-003 keeps the drawables readable
        handler?(nil)
    }

    /// Encodes the read-back of the drawn `target` when a capture waits and the drawable is readable.
    private func encodeCaptureIfPending(_ target: MTLTexture, commands: MTLCommandBuffer) {
        guard let handler = pendingCapture, !target.isFramebufferOnly else { return }
        pendingCapture = nil
        view.metalLayer.framebufferOnly = videoRecording == nil   // REC-003 keeps the drawables readable
        let width = target.width, height = target.height, rowBytes = width * 4
        guard target.pixelFormat == .bgra8Unorm_srgb || target.pixelFormat == .bgra8Unorm,
              let buffer = device.makeBuffer(length: rowBytes * height, options: .storageModeShared),
              let blit = commands.makeBlitCommandEncoder() else {
            handler(nil)
            return
        }
        blit.label = "REC-001 native capture"
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: buffer, destinationOffset: 0,
                  destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * height)
        blit.endEncoding()
        // Read only after the GPU finished; nothing else holds the buffer.
        nonisolated(unsafe) let readBack = buffer
        commands.addCompletedHandler { (completed: MTLCommandBuffer) in
            var pixels: CapturedPixels?
            if completed.status == .completed {
                let bytes = readBack.contents().bindMemory(to: UInt8.self, capacity: rowBytes * height)
                pixels = CapturedPixels(width: width, height: height,
                                        layout: .sRGBBGRA8TopDown(Array(UnsafeBufferPointer(start: bytes, count: rowBytes * height))))
            }
            Task { @MainActor in handler(pixels) }
        }
    }

    /// REC-003: a blit of the readable drawable's top-left region into the recording's texture.
    private static func encodeRecordingCopy(from target: MTLTexture, into texture: MTLTexture, commands: MTLCommandBuffer) -> Bool {
        guard !target.isFramebufferOnly, target.pixelFormat == texture.pixelFormat,
              texture.width <= target.width, texture.height <= target.height,
              let blit = commands.makeBlitCommandEncoder() else { return false }
        blit.label = "REC-003 native recording copy"
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: texture,
                  destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        return true
    }

    // MARK: - Frames

    fileprivate func frame(_ link: CADisplayLink) {
        let layer = view.metalLayer
        guard view.window != nil, layer.drawableSize.width >= 1, layer.drawableSize.height >= 1 else { return }
        if let info = analyzer.output.readLatest(into: bands, capacity: SpectrumBarCount.maximum) {
            bandCount = info.count
            bandSession = info.session
            kickEnvelope = info.kickEnvelope
            centroid = info.centroid
        }
        // ANL-003: the real interval since the previous frame (the first frame after a start snaps).
        let interval: Double = lastLinkTimestamp.map { (previous: CFTimeInterval) -> Double in link.timestamp - previous } ?? 0
        lastLinkTimestamp = link.timestamp
        let smoothedBands = smoother.update(target: bands, count: bandCount, frameInterval: interval, generation: bandSession)
        guard let drawable = layer.nextDrawable(), let commands = queue.makeCommandBuffer() else { return }
        let context = VisualFrameContext(timeNanoseconds: UInt64(max(link.targetTimestamp, 0) * 1e9),
                                         frameDuration: link.targetTimestamp - link.timestamp, reduceFlashing: reduceFlashing)
        let bandInput = UnsafeBufferPointer(start: bands, count: bandCount)
        applyModulation(bands: bandInput, kick: kickEnvelope, centroid: centroid, timeNanoseconds: context.timeNanoseconds)   // MOD-002; no-op without bindings
        // VIS-003: the oscilloscope draws the newest sample history (kept when nothing new arrived).
        let input: UnsafeBufferPointer<Float>
        if case .oscilloscope = style {
            _ = waveform?.output.readLatest(into: samples, capacity: WaveformFrameBuffer.capacity)
            input = UnsafeBufferPointer(start: samples, count: WaveformFrameBuffer.capacity)
        } else {
            input = smoothedBands   // ANL-003: the spectra draw the smoothed bands
        }
        let target = drawable.texture
        var drawn = false
        if let chain, glowActive {
            do {
                try chain.prepare(width: target.width, height: target.height)   // creates textures only on a size change
                drawn = chain.encode(output: target, commandBuffer: commands) { image in
                    generator.encode(into: image, commandBuffer: commands, bands: input, context: context)
                }
            } catch {
                dropGlow()
            }
        }
        if !drawn && !glowActive {
            drawn = generator.encode(into: target, commandBuffer: commands, bands: input, context: context)
        }
        guard drawn else { return }
        encodeCaptureIfPending(target, commands: commands)   // REC-001; nothing without a request
        // REC-003: the drawn drawable (glow included) copied into the recording's pixel buffer.
        videoRecording?.record(commandBuffer: commands, presentationNanoseconds: context.timeNanoseconds,
                               drawable: target) { (texture: MTLTexture) -> Bool in
            Self.encodeRecordingCopy(from: target, into: texture, commands: commands)
        }
        commands.present(drawable)
        commands.commit()
        presentedFrameCount += 1
        if meter.record(presentedAt: link.timestamp) { metrics = meter.metrics }
    }

    private func layoutDrawable() {
        guard !isSuspended else { return }
        let displayScale = view.traitCollection.displayScale > 0 ? view.traitCollection.displayScale : 2
        let scale = displayScale * quality.renderScale
        view.contentScaleFactor = scale
        let size = CGSize(width: (view.bounds.width * scale).rounded(), height: (view.bounds.height * scale).rounded())
        if size.width >= 1, size.height >= 1, size != view.metalLayer.drawableSize {
            view.metalLayer.drawableSize = size
        }
    }

    /// FR-049: frame-rate cap and render scale follow the thermal state and Low Power Mode.
    private func observeFrameRatePressure() {
        let center = NotificationCenter.default
        for name in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let quality = QualityGovernor.current()
                    guard quality != self.quality else { return }
                    self.quality = quality
                    self.displayLink?.preferredFrameRateRange = quality.frameRateRange
                    self.layoutDrawable()
                }
            })
        }
    }
}

/// The CAMetalLayer-backed view; one accessibility element (VIS-001-R18, VIS-002-R13). The host sets
/// its label, identifier and value for the shown visual.
final class NativeSpectrumLayerView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    var onLayout: (() -> Void)?

    init(device: MTLDevice) {
        super.init(frame: .zero)
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm_srgb
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        isOpaque = true
        backgroundColor = .black
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = "Circular Spectrum visualization"
        accessibilityTraits = .image
        accessibilityIdentifier = "circularSpectrum"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

/// Breaks the CADisplayLink → target retain cycle.
private final class NativeSpectrumLinkProxy: NSObject {
    weak var host: NativeSpectrumHost?
    init(_ host: NativeSpectrumHost) { self.host = host }
    @MainActor @objc func fire(_ link: CADisplayLink) { host?.frame(link) }
}

/// MOD-002 (research MOD-002-D6): the bloom's luminance model behind a class reference, so the frame
/// loop can follow a modulated intensity without boxing a new existential every frame. Mutated and
/// read only on the main thread (the frame loop encodes there), hence `@unchecked Sendable`.
final class ModulatedGlowLuminance: FrameLuminanceTransfer, @unchecked Sendable {
    var model = BloomLuminanceModel(parameters: BloomParameters())

    func outputLuminance(ofFlatColor color: LinearColor) -> Double { model.outputLuminance(ofFlatColor: color) }
    func outputRedness(ofFlatColor color: LinearColor) -> Double { model.outputRedness(ofFlatColor: color) }
    func spreadRadius(width: Int, height: Int) -> Double { model.spreadRadius(width: width, height: height) }
}

/// Which native spectrum the host draws (VIS-002-D5).
enum NativeSpectrumStyle: Equatable, Sendable {
    case circular
    case linear(LinearSpectrumOrientation, spacing: Double)
    /// VIS-003: the waveform oscilloscope.
    case oscilloscope(line: OscilloscopeLine, windowMilliseconds: Int)

    var title: String {
        switch self {
        case .circular: VisualChoice.circularSpectrum.title
        case .linear: VisualChoice.linearSpectrum.title
        case .oscilloscope: VisualChoice.oscilloscope.title
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .circular: "circularSpectrum"
        case .linear: "linearSpectrum"
        case .oscilloscope: "oscilloscope"
        }
    }
}

extension LinearSpectrumOrientation {
    /// Settings and VoiceOver.
    var title: String {
        switch self {
        case .vertical: "Vertical"
        case .horizontal: "Horizontal"
        }
    }
}
