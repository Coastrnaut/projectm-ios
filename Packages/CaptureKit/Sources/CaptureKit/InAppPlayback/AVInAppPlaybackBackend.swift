// AVInAppPlaybackBackend.swift — In-App Playback on AVAudioEngine: the audio session, route and
// interruption handling around InAppPlaybackGraph (tasks T046, AUD-001-T12 and AUD-006-T18;
// research R-04). `.playback` category, so the silent switch does not mute user-started media.
// Never touches the input node (FR-069).
//
// The transport members (AUD-006) forward to the graph. The audio session exists on iOS only; the
// rest compiles wherever AVFAudio does, so that tests on the Mac and the simulator can run this
// backend with the graph in offline rendering (internal initializer; research AUD-006-D10).
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
    private var graph: InAppPlaybackGraph?
    private var onEvent: (@Sendable (SourceEvent) -> Void)?
    private var observers: [any NSObjectProtocol] = []

    public var loopsCurrentTrack = true {
        didSet { graph?.loops = loopsCurrentTrack }
    }
    public var onTrackEnded: (@MainActor () -> Void)?

    public init(bundle: Bundle = .main, resource: String = "reference", fileExtension: String = "wav") {
        self.bundle = bundle
        self.resource = resource
        self.fileExtension = fileExtension
        offline = nil
    }

    /// Tests: the graph renders offline (`renderOffline(frames:)`), with no audio session.
    init(offlineSampleRate: Double, maximumFrameCount: AVAudioFrameCount = 1024, bundle: Bundle = .main,
         resource: String = "reference", fileExtension: String = "wav") {
        self.bundle = bundle
        self.resource = resource
        self.fileExtension = fileExtension
        offline = (offlineSampleRate, maximumFrameCount)
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

        let graph = InAppPlaybackGraph(content: content)
        graph.loops = loopsCurrentTrack
        graph.onTrackEnded = { [weak self] in self?.onTrackEnded?() }
        do {
            if let offline {
                try graph.enableOfflineRendering(sampleRate: offline.sampleRate, maximumFrameCount: offline.maximumFrameCount)
            }
            try graph.installTap(into: sink)
            try graph.start()
        } catch {
            graph.stop()
            deactivateSession()
            throw SourceError(.inAppPlaybackFailed)
        }
        self.graph = graph
        self.onEvent = onEvent
        observe()
    }

    public func stop() {
        graph?.stop()
        graph = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        onEvent = nil
        deactivateSession()
    }

    public func pause() {
        graph?.pause()
    }

    public func resume() throws {
        guard let graph else { throw SourceError(.inAppPlaybackFailed) }
        do {
            try activateSession(setCategory: false)
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

    private func observe() {
        #if os(iOS)
        guard offline == nil else { return }
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            MainActor.assumeIsolated {
                guard let self, reason == .oldDeviceUnavailable else { return }
                // Output lost (e.g. headphones unplugged): pause, report "Paused — audio route changed".
                self.pause()
                self.onEvent?(.outputRouteLost)
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated {
                guard let self, let onEvent = self.onEvent else { return }
                switch type {
                case .began: onEvent(.interruptionBegan)
                case .ended: onEvent(.interruptionEnded(shouldResume: options.contains(.shouldResume)))
                default: break
                }
            }
        })
        #endif
    }
}
#endif
