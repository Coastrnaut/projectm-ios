// AVInAppPlaybackBackend.swift — In-App Playback on AVAudioEngine: the audio session, route and
// interruption handling around InAppPlaybackGraph (tasks T046 and AUD-001-T12; research R-04).
// `.playback` category, so the silent switch does not mute user-started media. Never touches the
// input node (FR-069).
#if os(iOS) && canImport(AVFAudio)
import AudioCore
import AVFAudio
import Foundation

@MainActor
public final class AVInAppPlaybackBackend: InAppPlaybackBackend {
    private let bundle: Bundle
    private let resource: String
    private let fileExtension: String
    private var graph: InAppPlaybackGraph?
    private var onEvent: (@Sendable (SourceEvent) -> Void)?
    private var observers: [any NSObjectProtocol] = []

    public init(bundle: Bundle = .main, resource: String = "reference", fileExtension: String = "wav") {
        self.bundle = bundle
        self.resource = resource
        self.fileExtension = fileExtension
    }

    public func start(track: InAppPlaybackTrack, sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) throws {
        // The reference track is read into memory; an imported file is streamed (AUD-001-R20). A
        // track that cannot be opened fails here; the other track is never played instead
        // (AUD-001-R19).
        let content: InAppPlaybackGraph.Content
        do {
            content = try InAppPlaybackGraph.load(track, bundle: bundle, resource: resource, fileExtension: fileExtension)
        } catch {
            throw SourceError(.inAppPlaybackFailed)
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            Self.deactivateSession()   // mirror stop() on every failed start path
            throw SourceError(.inAppPlaybackFailed)
        }
        // From here on the session is active. Every failure path deactivates it, as stop() does:
        // InAppPlaybackSource never calls stop() after a failed start, so a session left active
        // would keep other apps' audio interrupted.

        let graph = InAppPlaybackGraph(content: content)
        do {
            try graph.installTap(into: sink)
            try graph.start()
        } catch {
            graph.stop()
            Self.deactivateSession()
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
        Self.deactivateSession()
    }

    public func pause() {
        graph?.pause()
    }

    public func resume() throws {
        guard let graph else { throw SourceError(.inAppPlaybackFailed) }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try graph.resume()
        } catch {
            throw SourceError(.inAppPlaybackFailed)
        }
    }

    /// Releases the session and lets interrupted apps resume. Used by stop() and by every
    /// start() failure after activation.
    private static func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observe() {
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
    }
}
#endif
