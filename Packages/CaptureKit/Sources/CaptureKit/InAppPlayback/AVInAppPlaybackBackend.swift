// AVInAppPlaybackBackend.swift — In-App Playback on AVAudioEngine: the audio session, route and
// interruption handling around InAppPlaybackGraph (tasks T046, AUD-001-T12 and AUD-006-T18;
// research R-04). `.playback` category, so the silent switch does not mute user-started media.
// Never touches the input node (FR-069).
//
// The transport members (AUD-006) forward to the graph. The audio session exists on iOS only; the
// rest compiles wherever AVFAudio does, so that tests on the Mac and the simulator can run this
// backend with the graph in offline rendering (internal initializer; research AUD-006-D10).
//
// Interruptions, routes, hardware changes and resets (AUD-014; specs/009-aud-014-audio-session-
// interruption-recovery): everything arrives as an `AudioSessionSignal` in `handle(_:)`: from
// `AudioSessionObserver` on iOS, from the engine's configuration-change notification everywhere,
// and from tests directly.
// * Interruption began: the graph holds its position now (iOS has stopped or will stop the audio),
//   then the source event goes out. Whether playback resumes is CaptureManager's decision
//   (InterruptionPolicy); a resume comes back as `resume()`, which cuts in at the held frame.
// * Output route lost: hold, then `.outputRouteLost` (FR-051).
// * Engine configuration change: the engine stopped itself. If the graph was playing it is held
//   and resumed at once, through the same cut; if it was held it stays held (the next resume
//   starts the engine). The policy decides with "no interruption".
// * Media services reset: the graph is rebuilt from the current track at the old position, held;
//   it continues only if it was playing. A track that cannot be opened again, or an engine that
//   cannot be started, ends the session as "In-App Playback failed".
#if canImport(AVFAudio)
import AudioCore
import AVFAudio
import Foundation

@MainActor
public final class AVInAppPlaybackBackend: InAppPlaybackBackend {
    private let bundle: Bundle
    private let resource: String
    private let fileExtension: String
    /// Tests only: render offline at this rate instead of to the device.
    private let offline: (sampleRate: Double, maximumFrameCount: AVAudioFrameCount)?
    private let center: NotificationCenter
    private var graph: InAppPlaybackGraph?
    private var onEvent: (@Sendable (SourceEvent) -> Void)?
    /// The engine's configuration-change observer (one per graph).
    private var engineObserver: (any NSObjectProtocol)?
    #if os(iOS)
    private var sessionObserver: AudioSessionObserver?
    #endif
    /// What a rebuild after a media-services reset needs: the track being played and the sink.
    private var currentTrack: InAppPlaybackTrack?
    private var sink: PCMSink?
    /// A reset happened while playback was on hold: the next resume sets the session category again.
    private var sessionNeedsCategory = false
    /// Engine restarts and graph rebuilds carried out (tests).
    private(set) var recoveryCount = 0

    public var loopsCurrentTrack = true {
        didSet { graph?.loops = loopsCurrentTrack }
    }
    public var onTrackEnded: (@MainActor () -> Void)?

    public init(bundle: Bundle = .main, resource: String = "reference", fileExtension: String = "wav") {
        self.bundle = bundle
        self.resource = resource
        self.fileExtension = fileExtension
        offline = nil
        center = .default
    }

    /// Tests: the graph renders offline (`renderOffline(frames:)`), with no audio session.
    /// `notificationCenter`: where this backend observes its notifications (tests: a private one).
    init(offlineSampleRate: Double, maximumFrameCount: AVAudioFrameCount = 1024, bundle: Bundle = .main,
         resource: String = "reference", fileExtension: String = "wav", notificationCenter: NotificationCenter = .default) {
        self.bundle = bundle
        self.resource = resource
        self.fileExtension = fileExtension
        offline = (offlineSampleRate, maximumFrameCount)
        center = notificationCenter
    }

    public func start(track: InAppPlaybackTrack, sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) throws {
        // Every track is streamed from its file (AUD-001-R20). A track that cannot be opened fails
        // here; the other track is never played instead (AUD-001-R19).
        let content: InAppPlaybackGraph.Content
        do {
            content = try InAppPlaybackGraph.load(track, bundle: bundle, resource: resource, fileExtension: fileExtension)
        } catch {
            throw SourceError(.inAppPlaybackFailed)
        }

        do {
            try activateSession()
        } catch {
            deactivateSession()   // mirror stop() on every failed start path
            throw SourceError(.inAppPlaybackFailed)
        }
        // From here on the session is active. Every failure path deactivates it, as stop() does:
        // InAppPlaybackSource never calls stop() after a failed start, so a session left active
        // would keep other apps' audio interrupted.

        let graph: InAppPlaybackGraph
        do {
            graph = try makeGraph(content, sink: sink)
            try graph.start()
        } catch {
            deactivateSession()
            throw SourceError(.inAppPlaybackFailed)
        }
        // A start while started (not done by InAppPlaybackSource) must not leave a second graph playing.
        self.graph?.stop()
        self.graph = graph
        self.onEvent = onEvent
        self.sink = sink
        currentTrack = track
        observe(graph)
    }

    /// A graph for `content`, tapped into `sink`, not started. On failure nothing is left running.
    private func makeGraph(_ content: InAppPlaybackGraph.Content, sink: PCMSink) throws -> InAppPlaybackGraph {
        let graph = InAppPlaybackGraph(content: content)
        graph.loops = loopsCurrentTrack
        graph.onTrackEnded = { [weak self] in self?.onTrackEnded?() }
        do {
            if let offline {
                try graph.enableOfflineRendering(sampleRate: offline.sampleRate, maximumFrameCount: offline.maximumFrameCount)
            }
            try graph.installTap(into: sink)
        } catch {
            graph.stop()
            throw error
        }
        return graph
    }

    public func stop() {
        graph?.stop()
        graph = nil
        stopObserving()
        onEvent = nil
        sink = nil
        currentTrack = nil
        sessionNeedsCategory = false
        deactivateSession()
    }

    public func pause() {
        graph?.pause()
    }

    public func resume() throws {
        guard let graph else { throw SourceError(.inAppPlaybackFailed) }
        do {
            try activateSession(setCategory: sessionNeedsCategory)
            sessionNeedsCategory = false
            try graph.resume()
        } catch {
            throw SourceError(.inAppPlaybackFailed)
        }
    }

    // MARK: - Transport (AUD-006)

    public var position: PlaybackPosition {
        guard let graph, graph.sampleRate > 0 else { return .zero }
        return PlaybackPosition(seconds: Double(graph.positionFrame) / graph.sampleRate,
                                durationSeconds: Double(graph.lengthFrames) / graph.sampleRate)
    }

    public func seek(to seconds: Double) {
        guard let graph else { return }
        graph.seek(toFrame: PlaybackPositionMath.frame(seconds: seconds, sampleRate: graph.sampleRate, length: graph.lengthFrames))
    }

    public func replaceTrack(_ track: InAppPlaybackTrack) throws {
        guard let graph else { throw SourceError(.inAppPlaybackFailed) }
        do {
            let content = try InAppPlaybackGraph.load(track, bundle: bundle, resource: resource, fileExtension: fileExtension)
            graph.loops = loopsCurrentTrack
            try graph.replace(content: content)
            currentTrack = track
        } catch {
            // The old track must not go on playing in place of the one asked for (AUD-006-R19).
            graph.silence()
            throw SourceError(.inAppPlaybackFailed)
        }
    }

    /// Tests: renders up to `frames` frames of an offline backend; 0 when not started.
    func renderOffline(frames: AVAudioFrameCount) throws -> Int {
        try graph?.renderOffline(frames: frames) ?? 0
    }

    // MARK: - Audio session (iOS)

    private func activateSession(setCategory: Bool = true) throws {
        #if os(iOS)
        guard offline == nil else { return }
        let session = AVAudioSession.sharedInstance()
        if setCategory { try session.setCategory(.playback, mode: .default) }
        try session.setActive(true)
        #endif
    }

    /// Releases the session and lets interrupted apps resume. Used by stop() and by every
    /// start() failure after activation.
    private func deactivateSession() {
        #if os(iOS)
        guard offline == nil else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Session and engine signals (AUD-014)

    private func observe(_ graph: InAppPlaybackGraph) {
        observeEngine(of: graph)
        #if os(iOS)
        sessionObserver?.invalidate()
        sessionObserver = AudioSessionObserver(center: center, session: AVAudioSession.sharedInstance()) { [weak self] signal in
            self?.handle(signal)
        }
        #endif
    }

    /// Observes the configuration change of this graph's engine, and of no other.
    private func observeEngine(of graph: InAppPlaybackGraph) {
        if let engineObserver { center.removeObserver(engineObserver) }
        engineObserver = center.addObserver(forName: .AVAudioEngineConfigurationChange, object: graph.notificationObject,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handle(.engineConfigurationChanged) }
        }
    }

    private func stopObserving() {
        if let engineObserver { center.removeObserver(engineObserver) }
        engineObserver = nil
        #if os(iOS)
        sessionObserver?.invalidate()
        sessionObserver = nil
        #endif
    }

    /// One signal from the audio session or the engine. No effect unless started.
    func handle(_ signal: AudioSessionSignal) {
        guard let graph, let onEvent else { return }
        switch signal {
        case .interruptionBegan(let outputDisconnected):
            // Hold the position of this moment (AUD-014-R10); iOS has stopped the audio.
            graph.pause()
            onEvent(.interruptionBegan)
            if outputDisconnected { onEvent(.outputRouteLost) }
        case .interruptionEnded(let shouldResume):
            onEvent(.interruptionEnded(shouldResume: shouldResume))
        case .outputRouteLost:
            // Output lost (e.g. headphones unplugged): pause, report "Paused — audio route changed".
            graph.pause()
            onEvent(.outputRouteLost)
        case .engineConfigurationChanged:
            recover(graph, rebuild: false, onEvent: onEvent)
        case .mediaServicesReset:
            recover(graph, rebuild: true, onEvent: onEvent)
        }
    }

    /// Brings playback back after the engine stopped itself (`rebuild` false) or every audio object
    /// died (`rebuild` true), in the state the policy gives: playing only if it was playing.
    private func recover(_ old: InAppPlaybackGraph, rebuild: Bool, onEvent: @Sendable (SourceEvent) -> Void) {
        let wasHeld = old.isPaused
        var current = old
        var usable = true
        if rebuild {
            // The old graph's objects are dead; only its bookkeeping is read (the position), then it
            // is stopped so its tap and callbacks end.
            let frame = old.positionFrame
            do {
                guard let currentTrack, let sink else { throw SourceError(.inAppPlaybackFailed) }
                let content = try InAppPlaybackGraph.load(currentTrack, bundle: bundle, resource: resource, fileExtension: fileExtension)
                // Playing: the session is set up again now. On hold (a pause, an open interruption):
                // activating could fail or interrupt others, so the next resume does it.
                if wasHeld { sessionNeedsCategory = true } else { try activateSession() }
                let rebuilt = try makeGraph(content, sink: sink)
                try rebuilt.start(atFrame: frame, held: true)
                old.stop()
                graph = rebuilt
                observeEngine(of: rebuilt)
                current = rebuilt
            } catch {
                usable = false
            }
        }
        let decision = InterruptionPolicy.decide(InterruptionPolicy.Input(
            source: .inAppPlayback, before: wasHeld ? .paused : .playing, pausedBy: .nobody, signal: .notInterrupted,
            isPresentable: true, userChangedTransport: false, sourceIsUsable: usable))
        switch decision {
        case .resume:
            do {
                current.pause()                           // hold where it was, then cut in there
                try current.resume()
                recoveryCount += 1
            } catch {
                onEvent(.failed(.inAppPlaybackFailed))
            }
        case .fail(let reason):
            onEvent(.failed(reason))
        case .stayPaused, .stayStopped, .notApplicable:
            if rebuild, usable { recoveryCount += 1 }
        }
    }

    /// Tests: the engine of the current graph (the configuration-change notification's object).
    var engineForTesting: AnyObject? { graph?.notificationObject }

    /// Tests: stops the engine as iOS does, without telling the graph.
    func stopEngineForTesting() {
        graph?.stopEngineForTesting()
    }
}
#endif
