// InAppPlaybackGraph.swift — the In-App Playback engine graph: player → main mixer, a mixer tap
// into PCMSink, and looping (tasks T046 and AUD-001-T10; research R-04 and AUD-001-D7, D8).
//
// Two kinds of content:
// * `.buffer`: the bundled reference track, read into memory once and looped by the player.
// * `.file`: an imported library file, streamed from disk by the player, so its length never
//   costs memory (AUD-001-R20). Two passes of the file are kept queued; each time the player has
//   consumed one, another is queued, so the loop continues without a gap.
//
// Real-time safety (Constitution VII): the tap closure only writes to PCMSink. File reads happen on
// AVAudioPlayerNode's own scheduling thread, never on the render thread.
//
// Threading: every call into the player is made on the main actor. The player's completion
// callback (its own serial queue) only posts a main-actor task and never calls the player:
// `play()` and `stop()` wait synchronously for that queue, so scheduling from inside the callback
// deadlocks against them (seen in this graph's tests on 2026-11-12 with `play()`).
//
// AVAudioSession, route changes and interruptions stay in AVInAppPlaybackBackend (iOS only). This
// type has none of that, so the macOS host can run it in offline manual-rendering mode.
#if canImport(AVFAudio)
import AudioCore
import AVFAudio
import Foundation

@MainActor
final class InAppPlaybackGraph {
    enum Content {
        case buffer(AVAudioPCMBuffer)
        /// The same file opened twice, so two passes can be queued without sharing a read position.
        case file(AVAudioFile, AVAudioFile)

        var format: AVAudioFormat {
            switch self {
            case .buffer(let buffer): return buffer.format
            case .file(let file, _): return file.processingFormat
            }
        }
    }

    /// Opens a track. `.reference` is `reference.wav` in `bundle`; `.file` is used as given. A
    /// track that cannot be opened throws; no other track is ever substituted (AUD-001-R19).
    static func load(_ track: InAppPlaybackTrack, bundle: Bundle, resource: String = "reference",
                     fileExtension: String = "wav") throws -> Content {
        switch track {
        case .reference:
            guard let url = bundle.url(forResource: resource, withExtension: fileExtension) else {
                throw SourceError(.inAppPlaybackFailed)
            }
            return try loadIntoMemory(url)
        case .file(let url):
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            guard file.length > 0, format.sampleRate > 0, (1...2).contains(format.channelCount) else {
                throw SourceError(.inAppPlaybackFailed)
            }
            return .file(file, try AVAudioFile(forReading: url))
        }
    }

    /// Reads a short file into one buffer (the reference track is 60 s).
    static func loadIntoMemory(_ url: URL) throws -> Content {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw SourceError(.inAppPlaybackFailed)
        }
        try file.read(into: buffer)
        return .buffer(buffer)
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let content: Content
    private var tapInstalled = false
    /// False once `stop()` ran: late completion callbacks schedule nothing.
    private var looping = false
    /// How many times content was handed to the player (tests: the loop, and its end after stop).
    private(set) var scheduleCount = 0
    private(set) var isRunning = false

    init(content: Content) {
        self.content = content
        engine.attach(player)
    }

    /// Connects the player and taps the app's own mix into `sink`. Call once, before `start()`.
    func installTap(into sink: PCMSink) throws {
        engine.connect(player, to: engine.mainMixerNode, format: content.format)
        let mixer = engine.mainMixerNode
        let tapFormat = mixer.outputFormat(forBus: 0)
        guard let format = AudioFormat(asbd: tapFormat.streamDescription.pointee) else {
            throw SourceError(.inAppPlaybackFailed)
        }
        // @Sendable makes the tap nonisolated. Without it the closure inherits this class's
        // @MainActor isolation, and Swift 6's runtime isolation check traps when AVFAudio calls
        // it on its real-time messenger queue. CaptureLabUITests hit this trap in this tap on the
        // iOS Simulator (crash reports fault in this closure); AVMicrophoneBackend's input tap
        // had the same pattern and got the same fix.
        let layout = ChannelLayoutTag(rawValue: tapFormat.channelLayout?.layoutTag ?? 0)
        warmUp(tapFormat)   // no first-call method-cache allocation in the tap (T063)
        mixer.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { @Sendable tapBuffer, when in
            // Capture delivery (task T062): the buffer's host time, in ns on the uptime clock.
            let captureNs: UInt64 = when.isHostTimeValid
                ? UInt64(AVAudioTime.seconds(forHostTime: when.hostTime) * 1_000_000_000) : 0
            sink.write(tapBuffer.audioBufferList, format: format, frameCount: Int(tapBuffer.frameLength),
                       layout: layout, captureTimeNs: captureNs)
        }
        tapInstalled = true
    }

    /// Starts the engine and looping playback. On failure the graph is stopped.
    func start() throws {
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            throw SourceError(.inAppPlaybackFailed)
        }
        switch content {
        case .buffer(let buffer):
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            scheduleCount += 1
        case .file:
            looping = true
            scheduleNextPass()
            scheduleNextPass()
        }
        player.play()
        warmUp(engine.mainMixerNode.outputFormat(forBus: 0))   // again: starting the engine can reset the caches
        isRunning = true
    }

    /// Queues one more pass of the file, alternating between its two handles.
    private func scheduleNextPass() {
        guard looping, case .file(let first, let second) = content else { return }
        let file = scheduleCount.isMultiple(of: 2) ? first : second
        scheduleCount += 1
        player.scheduleFile(file, at: nil, completionCallbackType: .dataConsumed) { @Sendable [weak self] _ in
            // On the player's completion queue: hand over to the main actor and return at once.
            Task { @MainActor [weak self] in self?.scheduleNextPass() }
        }
    }

    /// Idempotent. Ends the loop first, so no completion callback schedules into a stopped player.
    func stop() {
        looping = false
        if tapInstalled {
            engine.mainMixerNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        player.stop()
        engine.stop()
        isRunning = false
    }

    func pause() {
        player.pause()
        engine.pause()
    }

    func resume() throws {
        try engine.start()
        player.play()
    }

    private func warmUp(_ format: AVAudioFormat) {
        #if os(iOS)
        AVAudioTapWarmUp.run(format: format)
        #endif
    }

    // MARK: - Offline rendering (tests)

    /// Switches the engine to offline manual rendering. Call before `installTap(into:)`.
    func enableOfflineRendering(sampleRate: Double, maximumFrameCount: AVAudioFrameCount) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw SourceError(.inAppPlaybackFailed)
        }
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maximumFrameCount)
    }

    /// Renders up to `frames` frames offline and returns how many were produced.
    func renderOffline(frames: AVAudioFrameCount) throws -> Int {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                            frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw SourceError(.inAppPlaybackFailed)
        }
        let status = try engine.renderOffline(min(frames, buffer.frameCapacity), to: buffer)
        return status == .success ? Int(buffer.frameLength) : 0
    }
}
#endif
